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

    private static var currentTeamIdentifier: String? {
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
}

@objc protocol AppWLocPrivilegedHelperProtocol {
    func ping(withReply reply: @escaping (String?) -> Void)
    func applyPACSettings(_ data: Data, withReply reply: @escaping (String?) -> Void)
}
