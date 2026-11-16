import Foundation
import Darwin

private final class AppWLocPrivilegedHelper: NSObject, AppWLocPrivilegedHelperProtocol {
    private let queue = DispatchQueue(label: "com.hrtt.applocmac.helper.operations")
    private let systemLocation = AppWLocSystemLocation()
    private var idleExit: DispatchWorkItem?

    func ping(withReply reply: @escaping (String?) -> Void) {
        reply(nil)
    }
    
    /// 先校验整批配置，再修改网络设置，避免把空地址或不完整地址交给 networksetup。
    func applyPACSettings(_ data: Data, withReply reply: @escaping (String?) -> Void) {
        perform { self.applyPACSettingsNow(data, withReply: reply) }
    }

    /// 读取备份状态，识别上一次未还原的本机定位。
    func systemLocationStatus(withReply reply: @escaping (Bool, String?) -> Void) {
        performSystemLocation({}, reply: reply)
    }

    /// 把选点坐标写入本机系统定位模拟设置，并刷新定位服务。
    func lockSystemLocation(latitude: Double, longitude: Double, altitude: NSNumber?, horizontalAccuracy: Double,
                            verticalAccuracy: NSNumber?, withReply reply: @escaping (Bool, String?) -> Void) {
        performSystemLocation({
            try self.systemLocation.lock(latitude: latitude, longitude: longitude, altitude: altitude?.doubleValue,
                                         horizontalAccuracy: horizontalAccuracy, verticalAccuracy: verticalAccuracy?.doubleValue)
        }, reply: reply)
    }

    /// 将本机定位恢复到首次锁定前的状态。
    func restoreSystemLocation(withReply reply: @escaping (Bool, String?) -> Void) {
        performSystemLocation({ try self.systemLocation.restore() }, reply: reply)
    }

    /// PAC 和本机定位操作串行，空闲时退出，由 launchd 按需重新启动。
    private func perform(_ operation: @escaping () -> Void) {
        queue.async {
            self.idleExit?.cancel()
            operation()
            let exitWhenIdle = DispatchWorkItem { exit(EXIT_SUCCESS) }
            self.idleExit = exitWhenIdle
            self.queue.asyncAfter(deadline: .now() + 2, execute: exitWhenIdle)
        }
    }

    /// 即使操作失败也返回是否仍有备份，方便应用保留还原入口。
    private func performSystemLocation(_ operation: @escaping () throws -> Void, reply: @escaping (Bool, String?) -> Void) {
        perform {
            do {
                try operation()
                reply(try self.systemLocation.hasBackup(), nil)
            } catch {
                reply((try? self.systemLocation.hasBackup()) ?? false, error.localizedDescription)
            }
        }
    }

    /// 逐项应用已校验的 PAC 设置，保留原有代理处理逻辑。
    private func applyPACSettingsNow(_ data: Data, withReply reply: @escaping (String?) -> Void) {
        do {
            let settings = try JSONDecoder().decode([AppWLocPACNetworkSetting].self, from: data)
                .map { try $0.validated() }
            guard !settings.isEmpty else {
                throw NSError(domain: AppWLocPrivilegedHelperConstants.machServiceName, code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "无效的 PAC 配置"])
            }

            var failures: [String] = []
            for setting in settings {
                do {
                    if let url = setting.url {
                        try runNetworkSetup(["-setautoproxyurl", setting.service, url])
                    }
                    try runNetworkSetup(["-setautoproxystate", setting.service, setting.enabled ? "on" : "off"])
                } catch {
                    failures.append("\(setting.service)：\(error.localizedDescription)")
                }
            }
            reply(failures.isEmpty ? nil : failures.joined(separator: "；"))
        } catch {
            reply(error.localizedDescription)
        }
    }

    private func runNetworkSetup(_ arguments: [String]) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C", "LC_ALL": "C"]
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw NSError(domain: AppWLocPrivilegedHelperConstants.machServiceName,
                          code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "networksetup 执行失败" : message])
        }
    }
}

private final class AppWLocPrivilegedHelperListener: NSObject, NSXPCListenerDelegate {
    private let helper = AppWLocPrivilegedHelper()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: AppWLocPrivilegedHelperProtocol.self)
        connection.exportedObject = helper
        connection.activate()
        return true
    }
}

private let delegate = AppWLocPrivilegedHelperListener()
private let listener = NSXPCListener(machServiceName: AppWLocPrivilegedHelperConstants.machServiceName)
listener.setConnectionCodeSigningRequirement(AppWLocPrivilegedHelperConstants.clientCodeSigningRequirement)
listener.delegate = delegate
listener.activate()
dispatchMain()
