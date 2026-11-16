import Foundation
import Security

enum AppWLocPrivilegedHelperConstants {
    static let machServiceName = "com.hrtt.applocmac.helper"
    static let launchDaemonPlistName = "\(machServiceName).plist"
    static let clientCodeSigningRequirement = codeSigningRequirement(identifier: "com.hrtt.applocmac")
    static let helperCodeSigningRequirement = codeSigningRequirement(identifier: machServiceName)

    /// 主应用和 Helper 各自从当前签名中读取 Team ID，再用它校验通信对端。
    /// 这样更换同一构建配置的签名证书后，不需要同步修改源码中的固定 Team ID。
    private static func codeSigningRequirement(identifier: String) -> String {
        let baseRequirement = "anchor apple generic and identifier \"\(identifier)\""
        guard let teamIdentifier = currentTeamIdentifier else {
            // 缺少 Team ID 通常意味着当前产物是 ad-hoc 签名；保持严格校验，让连接明确失败。
            return "\(baseRequirement) and certificate leaf[subject.OU] = \"\""
        }
        return "\(baseRequirement) and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }

    /// 复用当前签名团队，供 Helper 通信和在线安装校验共同使用。
    static var currentTeamIdentifier: String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess,
              let code else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
              let information = signingInformation as? [String: Any],
              let teamIdentifier = information[kSecCodeInfoTeamIdentifier as String] as? String,
              !teamIdentifier.isEmpty else {
            return nil
        }
        return teamIdentifier
    }
}

struct AppWLocPACNetworkSetting: Codable {
    let service: String
    let url: String?
    let enabled: Bool

    /// 主程序和 Helper 共用校验，关闭 PAC 时允许没有 URL，有 URL 时必须是完整的 HTTP/HTTPS 地址。
    func validated() throws -> AppWLocPACNetworkSetting {
        guard !service.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: AppWLocPrivilegedHelperConstants.machServiceName, code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "无效的 PAC 网络服务"])
        }
        guard let url else {
            guard !enabled else {
                throw NSError(domain: AppWLocPrivilegedHelperConstants.machServiceName, code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "\(service)：启用 PAC 时缺少 URL"])
            }
            return self
        }

        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty,
              let parsedURL = URL(string: trimmedURL),
              let scheme = parsedURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = parsedURL.host, !host.isEmpty else {
            throw NSError(domain: AppWLocPrivilegedHelperConstants.machServiceName, code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "\(service)：无效的 PAC URL，需要完整的 HTTP/HTTPS 地址"])
        }
        return AppWLocPACNetworkSetting(service: service, url: trimmedURL, enabled: enabled)
    }
}

@objc protocol AppWLocPrivilegedHelperProtocol {
    func ping(withReply reply: @escaping (String?) -> Void)
    func applyPACSettings(_ data: Data, withReply reply: @escaping (String?) -> Void)
    func systemLocationStatus(withReply reply: @escaping (Bool, String?) -> Void)
    func lockSystemLocation(latitude: Double, longitude: Double, altitude: NSNumber?, horizontalAccuracy: Double,
                            verticalAccuracy: NSNumber?, withReply reply: @escaping (Bool, String?) -> Void)
    func restoreSystemLocation(withReply reply: @escaping (Bool, String?) -> Void)
}
