import Foundation
import GCDWebServer
import ServiceManagement
import CryptoKit
import CFNetwork

enum AppWLocPACError: Error, LocalizedError {
    case noNetworkService
    case helperApprovalRequired
    case helperNotFound
    case helperFailed(String)
    case commandFailed(String)
    case pacServerUnavailable
    case invalidPACPort
    case invalidPACURL
    case systemLocation(String)

    /// 把服务启动和代理配置失败转换成可直接展示的提示。
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
        case .pacServerUnavailable:
            return "本地 PAC 服务未成功启动"
        case .invalidPACPort:
            return "本地 PAC 服务的监听端口无效"
        case .invalidPACURL:
            return "无法生成有效的本地 PAC URL"
        case .systemLocation(let message):
            return message
        }
    }
}

/// macOS PAC 模式：只让 Apple 定位域名经过应用内 HTTPS 代理。
final class AppWLocPACManager {
    enum SystemLocationOperation {
        case status
        case lock(latitude: Double, longitude: Double, parameters: AppWLocLockParameters?)
        case restore

        var title: String {
            switch self {
            case .status: return "查询状态"
            case .lock: return "锁定"
            case .restore: return "还原"
            }
        }
    }

    private struct SavedPACSetting: Codable {
        let url: String?
        let enabled: Bool
    }

    private let queue = DispatchQueue(label: "com.wloc8.pac")
    private let proxyServer = AppWLocHTTPProxyServer(port: AppWLocConfig.localProxyPort)
    private let pacServer = GCDWebServer()
    private let savedSettingsKey = "AppWLoc.macOS.previousPACSettings.v1"
    private let registeredHelperSignatureKey = "AppWLoc.macOS.registeredHelperSignature.v2"
    // 系统冷启动 Helper（包括 Rosetta 转译和签名校验）可能需要几秒。
    private let helperStartupTimeout: TimeInterval = 10
    private var previousSettings: [String: SavedPACSetting] = [:]
    private var fallbackPACReturn = "DIRECT"
    private var isRunning = false

    var hasPACToRestore: Bool {
        UserDefaults.standard.data(forKey: savedSettingsKey) != nil
    }

    /// 使用和 WLoc 相同的 Helper，只有锁定和还原才需要检查管理员授权。
    func performSystemLocation(_ operation: SystemLocationOperation, completion: @escaping (Bool?, Error?) -> Void) {
        queue.async {
            let reply: (active: Bool?, error: Error?)
            do {
                switch operation {
                case .status:
                    let service = SMAppService.daemon(plistName: AppWLocPrivilegedHelperConstants.launchDaemonPlistName)
                    guard service.status == .enabled else {
                        AppWLocUtils.debugLog("虚拟定位跳过状态查询：Helper 未启用（状态 \(service.status.rawValue)）")
                        DispatchQueue.main.async { completion(nil, nil) }
                        return
                    }
                case .lock(let latitude, let longitude, let parameters):
                    let details = parameters.map { "，海拔=\($0.altitude)，水平精度=\($0.horizontalAccuracy)，垂直精度=\($0.verticalAccuracy)" } ?? ""
                    AppWLocUtils.debugLog("虚拟定位开始锁定：lat=\(latitude)，lng=\(longitude)\(details)")
                    try self.loadSavedSettings()
                    guard !self.isRunning, self.previousSettings.isEmpty else {
                        throw AppWLocPACError.systemLocation("请先还原 WLoc 定位，再使用虚拟定位。")
                    }
                    try self.ensureHelper()
                case .restore:
                    AppWLocUtils.debugLog("虚拟定位开始还原")
                    try self.ensureHelper()
                }
                let response = try self.requestSystemLocation(operation)
                reply = (response.active, response.error)
            } catch {
                reply = (nil, error)
            }
            if let error = reply.error {
                AppWLocUtils.debugLog("虚拟定位\(operation.title)失败：\(error.localizedDescription)")
            } else {
                let status = reply.active == true ? "保留原设置备份" : "没有待还原的设置"
                AppWLocUtils.debugLog("虚拟定位\(operation.title)完成：\(status)")
            }
            DispatchQueue.main.async { completion(reply.active, reply.error) }
        }
    }

    /// 只读取当前环境，不启动 Helper，也不修改系统代理。
    func logDiagnostics(completion: @escaping () -> Void) {
        queue.async {
            AppWLocUtils.logMacEnvironment(reason: "查看当前诊断状态")
            self.logProxySettings()
            AppWLocCertificateStore.shared.logMacCertificateDiagnostics()
            DispatchQueue.main.async(execute: completion)
        }
    }

    /// 记录系统实际使用的代理，便于发现 PAC 被 VPN 或其他软件覆盖。
    private func logProxySettings() {
        let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue()
        let helper = SMAppService.daemon(plistName: AppWLocPrivilegedHelperConstants.launchDaemonPlistName)
        AppWLocUtils.debugLog("PAC 状态：running=\(isRunning)，PAC服务=\(pacServer.isRunning)，端口=\(pacServer.port)，Helper状态=\(helper.status.rawValue)\n系统代理：\(String(describing: settings))")
    }

    /// 保存本次选择的坐标和定位参数，代理已启动时也会更新锁定状态。
    func lock(to place: AppWLocPlace, parameters: AppWLocLockParameters = AppWLocLockParameters(), completion: @escaping (Result<Void, Error>) -> Void) {
        AppWLocUtils.logMacEnvironment(reason: "开始锁定位置")
        AppWLocUtils.debugLog("地图坐标：lat=\(place.latitude)，lng=\(place.longitude)，海拔=\(parameters.altitude)，水平精度=\(parameters.horizontalAccuracy)，垂直精度=\(parameters.verticalAccuracy)")
        do {
            let coordinate = AppWLocCoordinateTool.wlocResponseCoordinate(fromAppleMapCoordinate: place.coordinate)
            try AppWLocStateStore.shared.lock(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                altitude: parameters.altitude,
                horizontalAccuracy: parameters.horizontalAccuracy,
                verticalAccuracy: parameters.verticalAccuracy
            )
        } catch {
            AppWLocUtils.debugLog("保存锁定位置失败：\(error as NSError)")
            completion(.failure(error))
            return
        }

        queue.async {
            if self.isRunning {
                AppWLocUtils.debugLog("PAC 已在运行，本次更新锁定坐标")
                self.logProxySettings()
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

    /// 恢复系统代理，并按用户操作决定是否清除锁定坐标。
    func stop(clearState: Bool = false, completion: ((Error?) -> Void)? = nil) {
        queue.async {
            let error = self.stop()
            if clearState {
                AppWLocStateStore.shared.clear()
            }
            DispatchQueue.main.async { completion?(error) }
        }
    }

    /// 退出前等待原代理恢复完成。
    func stopForAppTermination() {
        queue.sync {
            _ = stop()
            AppWLocStateStore.shared.clear()
        }
    }

    /// 保存原代理设置，启动本地服务，并确认实际监听地址有效后再启用系统 PAC。
    private func start() throws {
        logProxySettings()
        AppWLocCertificateStore.shared.logMacCertificateDiagnostics()
        try ensureHelper()
        let systemLocation = try requestSystemLocation(.status)
        if let error = systemLocation.error { throw error }
        guard !systemLocation.active else {
            throw AppWLocPACError.systemLocation("请先还原虚拟定位，再开启 WLoc。")
        }

        let defaults = UserDefaults.standard
        try loadSavedSettings()
        if let error = restorePAC(previousSettings) {
            throw error
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
                url: value?.isEmpty == false && value != "(null)" ? value : nil,
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
            AppWLocUtils.debugLog("PAC 脚本：\n\(script)")
            pacServer.addHandler(forMethod: "GET", path: AppWLocConfig.pacPath, request: GCDWebServerRequest.self) { request in
                AppWLocUtils.debugLog("PAC 脚本被读取：\(request.url.absoluteString)，请求头：\(request.headers)")
                return GCDWebServerDataResponse(
                    data: Data(script.utf8),
                    contentType: "application/x-ns-proxy-autoconfig"
                )
            }
            try pacServer.start(options: [
                GCDWebServerOption_Port: AppWLocConfig.pacServerPort,
                GCDWebServerOption_BindToLocalhost: true
            ])
            AppWLocUtils.debugLog(
                "\(AppWLocConfig.displayName) PAC server running=\(pacServer.isRunning) port=\(pacServer.port) serverURL=\(pacServer.serverURL?.absoluteString ?? "nil")"
            )
            guard pacServer.isRunning else { throw AppWLocPACError.pacServerUnavailable }
            let port = pacServer.port
            guard port > 0, port <= 65535 else { throw AppWLocPACError.invalidPACPort }
            // serverURL 可能为空，用服务实际监听端口和 loopback 地址生成 PAC URL。
            guard let pacURL = URL(string: "http://\(AppWLocConfig.localProxyHost):\(port)\(AppWLocConfig.pacPath)") else {
                throw AppWLocPACError.invalidPACURL
            }
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) PAC URL = \(pacURL.absoluteString)")

            try setPAC(services.map {
                AppWLocPACNetworkSetting(service: $0, url: pacURL.absoluteString, enabled: true)
            })
            isRunning = true
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) PAC 已启用：\(pacURL.absoluteString)")
            logProxySettings()
        } catch {
            _ = stop()
            throw error
        }
    }

    /// 先还原代理再关闭本地服务，记录未能恢复的具体错误。
    @discardableResult
    private func stop() -> Error? {
        var restoreError: Error?
        do {
            try loadSavedSettings()
            restoreError = restorePAC(previousSettings)
        } catch {
            restoreError = error
        }
        if pacServer.isRunning { pacServer.stop() }
        proxyServer.stop()
        fallbackPACReturn = "DIRECT"
        isRunning = false
        AppWLocUtils.debugLog("PAC 已停止，恢复原设置结果：\(restoreError.map { String(describing: $0 as NSError) } ?? "成功")")
        logProxySettings()
        return restoreError
    }

    private func loadSavedSettings() throws {
        guard previousSettings.isEmpty,
              let data = UserDefaults.standard.data(forKey: savedSettingsKey) else { return }
        previousSettings = try JSONDecoder().decode([String: SavedPACSetting].self, from: data)
    }

    /// 恢复原来的 PAC 状态；原地址为空时只恢复开关，不把空字符串交给 Helper。
    @discardableResult
    private func restorePAC(_ settings: [String: SavedPACSetting]) -> Error? {
        guard !settings.isEmpty else { return nil }
        var failures: [String] = []
        var remaining = settings
        for (service, setting) in settings {
            do {
                let url = setting.url?.trimmingCharacters(in: .whitespacesAndNewlines)
                try setPAC([AppWLocPACNetworkSetting(
                    service: service,
                    url: url?.isEmpty == false ? url : nil,
                    enabled: setting.enabled
                )])
                remaining.removeValue(forKey: service)
            } catch {
                failures.append("\(service)：\(error.localizedDescription)")
            }
        }
        previousSettings = remaining
        if remaining.isEmpty {
            UserDefaults.standard.removeObject(forKey: savedSettingsKey)
        } else {
            do {
                UserDefaults.standard.set(try JSONEncoder().encode(remaining), forKey: savedSettingsKey)
            } catch {
                return error
            }
        }
        return failures.isEmpty ? nil : AppWLocPACError.commandFailed(failures.sorted().joined(separator: "\n"))
    }

    /// 记录 Helper 注册和启动状态，区分权限、安装位置和连接故障。
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
        AppWLocUtils.debugLog("Helper 检查：status=\(service.status.rawValue)，loaded=\(helperLoaded)，文件=\(helperURL.path)，签名摘要=\(signature)")
        
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
        AppWLocUtils.debugLog("Helper 注册后状态：\(status.rawValue)")

        switch status {
        case .enabled:
            if !waitForHelperLoaded(timeout: 3) || !pingHelper(timeout: helperStartupTimeout) {
                defaults.removeObject(forKey: registeredHelperSignatureKey)
                try unregisterHelper(service)
                try registerHelper(service)
                guard waitForHelperLoaded(timeout: 3), pingHelper(timeout: helperStartupTimeout) else {
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
        let connection = helperConnection()
        
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
    
    
    /// 在建立 XPC 连接前校验配置，让无效 PAC 地址直接在主程序报错。
    private func setPAC(_ settings: [AppWLocPACNetworkSetting]) throws {
        guard !settings.isEmpty else { return }
        let settings = try settings.map { try $0.validated() }
        let payload = try JSONEncoder().encode(settings)
        AppWLocUtils.debugLog("通过 Helper 设置 PAC：\(String(decoding: payload, as: UTF8.self))")
        let connection = helperConnection()

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
        helper.applyPACSettings(payload, withReply: finish)

        guard semaphore.wait(timeout: .now() + 15) == .success else {
            connection.invalidate()
            throw AppWLocPACError.helperFailed("Privileged Helper 响应超时")
        }
        connection.invalidate()
        if let message = result {
            AppWLocUtils.debugLog("Helper 设置 PAC 失败：\(message)")
            throw AppWLocPACError.commandFailed(message)
        }
        AppWLocUtils.debugLog("Helper 设置 PAC 完成")
    }

    /// 向 Helper 请求本机定位，返回是否仍有需要还原的配置。
    private func requestSystemLocation(_ operation: SystemLocationOperation) throws -> (active: Bool, error: Error?) {
        let connection = helperConnection()
        defer { connection.invalidate() }
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: (active: Bool, error: Error?)?
        let finish: (Bool, Error?) -> Void = { active, error in
            lock.lock()
            defer { lock.unlock() }
            guard result == nil else { return }
            result = (active, error)
            semaphore.signal()
        }
        connection.activate()
        guard let helper = connection.remoteObjectProxyWithErrorHandler({ finish(false, $0) }) as? AppWLocPrivilegedHelperProtocol else {
            throw AppWLocPACError.helperFailed("")
        }
        let reply: (Bool, String?) -> Void = { active, message in
            finish(active, message.map(AppWLocPACError.systemLocation))
        }
        let timeout: TimeInterval
        switch operation {
        case .status:
            timeout = helperStartupTimeout
            helper.systemLocationStatus(withReply: reply)
        case .lock(let latitude, let longitude, let parameters):
            timeout = 30
            helper.lockSystemLocation(latitude: latitude, longitude: longitude, altitude: parameters.map { NSNumber(value: $0.altitude) },
                                      horizontalAccuracy: Double(parameters?.horizontalAccuracy ?? 5),
                                      verticalAccuracy: parameters.map { NSNumber(value: $0.verticalAccuracy) }, withReply: reply)
        case .restore:
            timeout = 30
            helper.restoreSystemLocation(withReply: reply)
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success, let result else {
            throw AppWLocPACError.helperFailed("本机定位操作响应超时")
        }
        return result
    }

    /// 两种定位方式共用签名校验和 XPC 接口。
    private func helperConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: AppWLocPrivilegedHelperConstants.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: AppWLocPrivilegedHelperProtocol.self)
        connection.setCodeSigningRequirement(AppWLocPrivilegedHelperConstants.helperCodeSigningRequirement)
        return connection
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

    /// 保留网络配置命令的实际输出，轮询 launchctl 时避免重复刷屏。
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
        if executable == "/usr/sbin/networksetup" {
            AppWLocUtils.debugLog("执行 \(executable) \(arguments.joined(separator: " "))，exit=\(process.terminationStatus)\n\(text)")
        }
        guard process.terminationStatus == 0 else {
            throw AppWLocPACError.commandFailed(text)
        }
        return text
    }
    
}
