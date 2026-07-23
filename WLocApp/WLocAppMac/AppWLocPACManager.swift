import Foundation
import GCDWebServer
import ServiceManagement
import CryptoKit

enum AppWLocPACError: Error, LocalizedError {
    case noNetworkService
    case helperApprovalRequired
    case helperNotFound
    case helperFailed(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noNetworkService:
            return "未找到可配置的 macOS 网络服务"
        case .helperApprovalRequired:
            return "请在“系统设置 > 通用 > 登录项与扩展”中允许 WLoc8.com 后台项目，然后重试"
        case .helperNotFound:
            return "应用内缺少 Privileged Helper，请将完整的 WLoc8.com 安装到“应用程序”后重试"
        case .helperFailed(let message):
            return message.isEmpty ? "Privileged Helper 启动失败" : "Privileged Helper 启动失败：\(message)"
        case .commandFailed(let message):
            return message.isEmpty ? "自动代理配置失败" : "自动代理配置失败：\(message)"
        }
    }
}

/// macOS PAC 模式：只让 Apple 定位域名经过应用内 HTTPS 代理。
final class AppWLocPACManager {
    private struct SavedPACSetting: Codable {
        let url: String?
        let enabled: Bool
    }

    private let queue = DispatchQueue(label: "com.wloc8.pac")
    private let proxyServer = AppWLocHTTPProxyServer(port: AppWLocConfig.localProxyPort)
    private let pacServer = GCDWebServer()
    private let savedSettingsKey = "AppWLoc.macOS.previousPACSettings.v1"
    private let registeredHelperSignatureKey = "AppWLoc.macOS.registeredHelperSignature.v2"
    private var previousSettings: [String: SavedPACSetting] = [:]
    private var fallbackPACReturn = "DIRECT"
    private var isRunning = false

    func lock(to place: AppWLocPlace, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            let coordinate = AppWLocCoordinateTool.wlocResponseCoordinate(fromAppleMapCoordinate: place.coordinate)
            try AppWLocStateStore.shared.lock(latitude: coordinate.latitude, longitude: coordinate.longitude)
        } catch {
            completion(.failure(error))
            return
        }

        queue.async {
            if self.isRunning {
                DispatchQueue.main.async { completion(.success(())) }
                return
            }

            do {
                try self.start()
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                AppWLocStateStore.shared.clear()
                AppWLocUtils.debugLog("\(AppWLocConfig.displayName) PAC 启动失败：\(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func stop(clearState: Bool = false, completion: ((Error?) -> Void)? = nil) {
        queue.async {
            let error = self.stop()
            if clearState {
                AppWLocStateStore.shared.clear()
            }
            DispatchQueue.main.async { completion?(error) }
        }
    }

    func stopForAppTermination() {
        queue.sync {
            _ = stop()
            AppWLocStateStore.shared.clear()
        }
    }

    private func start() throws {
        try ensureHelper()

        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: savedSettingsKey),
           let staleSettings = try? JSONDecoder().decode([String: SavedPACSetting].self, from: data),
           !staleSettings.isEmpty {
            restorePAC(staleSettings)
            defaults.removeObject(forKey: savedSettingsKey)
        }

        let services = try activeNetworkServices()
        guard !services.isEmpty else { throw AppWLocPACError.noNetworkService }
        AppWLocUtils.debugLog("PAC 当前网络服务：\(services.joined(separator: ", "))")

        previousSettings.removeAll()
        for service in services {
            let settingOutput = try run("/usr/sbin/networksetup", ["-getautoproxyurl", service])
            let lines = settingOutput.components(separatedBy: .newlines)
            let value = lines.first { $0.hasPrefix("URL:") }?.dropFirst(4)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let enabled = lines.first { $0.hasPrefix("Enabled:") }?
                .lowercased().contains("yes") == true
            previousSettings[service] = SavedPACSetting(
                url: value == nil || value == "(null)" ? nil : value,
                enabled: enabled
            )
        }
        defaults.set(try JSONEncoder().encode(previousSettings), forKey: savedSettingsKey)
        fallbackPACReturn = pacFallbackReturn(for: services)
        AppWLocUtils.debugLog("PAC 非定位流量回退：\(fallbackPACReturn)")

        do {
            try proxyServer.start()
            pacServer.removeAllHandlers()
            let script = """
            function FindProxyForURL(url, host) {
                if (dnsDomainIs(host, "gs-loc.apple.com") || dnsDomainIs(host, "gs-loc-cn.apple.com")) {
                    return "PROXY \(AppWLocConfig.localProxyHost):\(AppWLocConfig.localProxyPort)";
                }
                return "\(fallbackPACReturn)";
            }
            """
            pacServer.addHandler(forMethod: "GET", path: "/wloc.pac", request: GCDWebServerRequest.self) { _ in
                GCDWebServerDataResponse(
                    data: Data(script.utf8),
                    contentType: "application/x-ns-proxy-autoconfig"
                )
            }
            try pacServer.start(options: [
                GCDWebServerOption_Port: AppWLocConfig.pacServerPort,
                GCDWebServerOption_BindToLocalhost: true
            ])

            try setPAC(services.map {
                AppWLocPACNetworkSetting(service: $0, url: AppWLocConfig.pacURL.absoluteString, enabled: true)
            })
            isRunning = true
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) PAC 已启用：\(AppWLocConfig.pacURL.absoluteString)")
        } catch {
            _ = stop()
            throw error
        }
    }

    @discardableResult
    private func stop() -> Error? {
        var restoreError: Error?
        if !previousSettings.isEmpty {
            restoreError = restorePAC(previousSettings)
            previousSettings.removeAll()
            if restoreError == nil {
                UserDefaults.standard.removeObject(forKey: savedSettingsKey)
            }
        }
        if pacServer.isRunning { pacServer.stop() }
        proxyServer.stop()
        fallbackPACReturn = "DIRECT"
        isRunning = false
        return restoreError
    }

    @discardableResult
    private func restorePAC(_ settings: [String: SavedPACSetting]) -> Error? {
        var restoreError: Error?
        for (service, setting) in settings {
            do {
                try setPAC([AppWLocPACNetworkSetting(
                    service: service,
                    url: setting.url,
                    enabled: setting.enabled
                )])
            } catch {
                restoreError = error
                AppWLocUtils.debugLog("PAC 忽略无法恢复的网络服务 \(service)：\(error.localizedDescription)")
            }
        }
        return restoreError
    }

    private func ensureHelper() throws {
        let service = SMAppService.daemon(plistName: AppWLocPrivilegedHelperConstants.launchDaemonPlistName)
        let defaults = UserDefaults.standard
        let helperURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/WLocPrivilegedHelper")
        let daemonURL = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/Library/LaunchDaemons/\(AppWLocPrivilegedHelperConstants.launchDaemonPlistName)"
        )
        guard var registrationData = try? Data(contentsOf: helperURL),
              let daemonData = try? Data(contentsOf: daemonURL) else {
            throw AppWLocPACError.helperNotFound
        }
        registrationData.append(daemonData)
        let signature = SHA256.hash(data: registrationData).map { String(format: "%02x", $0) }.joined()
        let helperLoaded = isHelperLoaded()
        
        var shouldRegister = service.status == .notRegistered || service.status == .notFound

        if service.status == .enabled,
           defaults.string(forKey: registeredHelperSignatureKey) != signature || !helperLoaded {
            try unregisterHelper(service)
            shouldRegister = true
        }

        if shouldRegister {
            try registerHelper(service)
        }
        
        let status = waitForHelperStatus(service, timeout: 2) { status in
            status == .enabled || status == .requiresApproval
        }

        switch status {
        case .enabled:
            if !waitForHelperLoaded(timeout: 3) || !pingHelper(timeout: 3) {
                defaults.removeObject(forKey: registeredHelperSignatureKey)
                try unregisterHelper(service)
                try registerHelper(service)
                guard waitForHelperLoaded(timeout: 3), pingHelper(timeout: 3) else {
                    throw AppWLocPACError.helperFailed("launchd 已注册但 Privileged Helper 无法启动")
                }
            }
            defaults.set(signature, forKey: registeredHelperSignatureKey)
            return
        case .requiresApproval:
            DispatchQueue.main.async { SMAppService.openSystemSettingsLoginItems() }
            throw AppWLocPACError.helperApprovalRequired
        case .notFound:
            throw AppWLocPACError.helperFailed("系统未能注册 Privileged Helper")
        case .notRegistered:
            throw AppWLocPACError.helperFailed("notRegistered")
        @unknown default:
            throw AppWLocPACError.helperFailed("default")
        }
    }
    
    private func unregisterHelper(_ service: SMAppService) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var unregisterError: Error?
        service.unregister { error in
            unregisterError = error
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 15) == .success else {
            throw AppWLocPACError.helperFailed("更新 Privileged Helper 超时")
        }
        if let unregisterError {
            throw AppWLocPACError.helperFailed(unregisterError.localizedDescription)
        }
        _ = waitForHelperStatus(service, timeout: 2) { status in
            status == .notRegistered || status == .notFound
        }
    }
    
    private func registerHelper(_ service: SMAppService) throws {
        let retryDelays: [TimeInterval] = [0, 0.2, 0.5, 1]
        var lastError: Error?

        for delay in retryDelays {
            if delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }

            do {
                try service.register()
                if waitForHelperLoaded(timeout: 2) {
                    return
                }
            } catch {
                lastError = error
                let status = waitForHelperStatus(service, timeout: 0.5) { status in
                    status == .requiresApproval
                }
                if status == .requiresApproval {
                    return
                }
                if isHelperLoaded() {
                    return
                }
            }
        }

        if service.status == .requiresApproval {
            return
        }
        throw AppWLocPACError.helperFailed(lastError?.localizedDescription ?? "")
    }
    
    private func isHelperLoaded() -> Bool {
        guard let output = try? run("/bin/launchctl", [
            "print",
            "system/\(AppWLocPrivilegedHelperConstants.machServiceName)"
        ]) else {
            return false
        }
        return !output.contains("job state = spawn failed")
            && !output.contains("last exit code = 78")
    }

    private func waitForHelperLoaded(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if isHelperLoaded() {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return isHelperLoaded()
    }

    private func pingHelper(timeout: TimeInterval) -> Bool {
        let connection = NSXPCConnection(
            machServiceName: AppWLocPrivilegedHelperConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: AppWLocPrivilegedHelperProtocol.self)
        connection.setCodeSigningRequirement(AppWLocPrivilegedHelperConstants.helperCodeSigningRequirement)
        
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var ok = false
        var finished = false
        let finish: (String?) -> Void = { message in
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            ok = message == nil
            semaphore.signal()
        }
        
        connection.activate()
        guard let helper = connection.remoteObjectProxyWithErrorHandler({ _ in finish("error") })
            as? AppWLocPrivilegedHelperProtocol else {
            connection.invalidate()
            return false
        }
        helper.ping(withReply: finish)

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            connection.invalidate()
            return false
        }
        connection.invalidate()
        return ok
    }
    
    private func waitForHelperStatus(
        _ service: SMAppService,
        timeout: TimeInterval,
        matching predicate: (SMAppService.Status) -> Bool
    ) -> SMAppService.Status {
        let deadline = Date().addingTimeInterval(timeout)
        var status = service.status
        while !predicate(status), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            status = service.status
        }
        return status
    }
    
    
    private func setPAC(_ settings: [AppWLocPACNetworkSetting]) throws {
        guard !settings.isEmpty else { return }
        let connection = NSXPCConnection(
            machServiceName: AppWLocPrivilegedHelperConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: AppWLocPrivilegedHelperProtocol.self)
        connection.setCodeSigningRequirement(AppWLocPrivilegedHelperConstants.helperCodeSigningRequirement)

        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: String? = "Privileged Helper 未响应"
        var finished = false
        let finish: (String?) -> Void = { message in
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            result = message
            semaphore.signal()
        }

        connection.activate()
        guard let helper = connection.remoteObjectProxyWithErrorHandler({ finish($0.localizedDescription) })
            as? AppWLocPrivilegedHelperProtocol else {
            connection.invalidate()
            throw AppWLocPACError.helperFailed("")
        }
        helper.applyPACSettings(try JSONEncoder().encode(settings), withReply: finish)

        guard semaphore.wait(timeout: .now() + 15) == .success else {
            connection.invalidate()
            throw AppWLocPACError.helperFailed("Privileged Helper 响应超时")
        }
        connection.invalidate()
        if let message = result {
            throw AppWLocPACError.commandFailed(message)
        }
    }

    private func activeNetworkServices() throws -> [String] {
        let output = try run("/usr/sbin/networksetup", ["-listallnetworkservices"])
        return output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") && !$0.hasPrefix("*") }
            .filter { service in
                guard let info = try? run("/usr/sbin/networksetup", ["-getinfo", service]) else {
                    return false
                }
                return info.components(separatedBy: .newlines).contains { line in
                    guard line.hasPrefix("IP address:") || line.hasPrefix("IPv6 IP address:") else {
                        return false
                    }
                    let address = line.split(separator: ":", maxSplits: 1)
                        .last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return !address.isEmpty && address != "none" && address != "(null)"
                }
            }
    }

    private func pacFallbackReturn(for services: [String]) -> String {
        for service in services {
            let http = proxyReturnValue(service: service, command: "-getwebproxy", type: "PROXY")
            let https = proxyReturnValue(service: service, command: "-getsecurewebproxy", type: "PROXY")
            let socks = proxyReturnValue(service: service, command: "-getsocksfirewallproxy", type: "SOCKS")
            var fallback = [String]()
            for value in [https, http, socks] {
                guard let value, !fallback.contains(value) else { continue }
                fallback.append(value)
            }
            if !fallback.isEmpty {
                fallback.append("DIRECT")
                return fallback.joined(separator: "; ")
            }
        }
        return "DIRECT"
    }

    private func proxyReturnValue(service: String, command: String, type: String) -> String? {
        guard let output = try? run("/usr/sbin/networksetup", [command, service]) else { return nil }
        let lines = output.components(separatedBy: .newlines)
        let enabled = lines.first { $0.hasPrefix("Enabled:") }?.lowercased().contains("yes") == true
        guard enabled,
              let server = lines.first(where: { $0.hasPrefix("Server:") })?.dropFirst(7)
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              let port = lines.first(where: { $0.hasPrefix("Port:") })?.dropFirst(5)
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !server.isEmpty,
              !port.isEmpty,
              Int(port) != nil else {
            return nil
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_:")
        let host = String(server.unicodeScalars.filter { allowed.contains($0) })
        guard !host.isEmpty else { return nil }
        return "\(type) \(host):\(port)"
    }

    private func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        var environment = ProcessInfo.processInfo.environment
        environment["LANG"] = "C"
        environment["LC_ALL"] = "C"
        process.environment = environment
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            throw AppWLocPACError.commandFailed(text)
        }
        return text
    }
    
}
