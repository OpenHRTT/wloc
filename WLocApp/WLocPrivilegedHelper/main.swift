import Foundation
import Darwin

private final class AppWLocPrivilegedHelper: NSObject, AppWLocPrivilegedHelperProtocol {
    
    func ping(withReply reply: @escaping (String?) -> Void) {
        reply(nil)
    }
    
    func applyPACSettings(_ data: Data, withReply reply: @escaping (String?) -> Void) {
        defer {
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                exit(EXIT_SUCCESS)
            }
        }
        do {
            let settings = try JSONDecoder().decode([AppWLocPACNetworkSetting].self, from: data)
            guard !settings.isEmpty, settings.allSatisfy({ !$0.service.isEmpty }) else {
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
