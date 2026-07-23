import Foundation

enum AppWLocPrivilegedHelperConstants {
    static let machServiceName = "com.hrtt.applocmac.helper"
    static let launchDaemonPlistName = "\(machServiceName).plist"
    static let clientCodeSigningRequirement = "anchor apple generic and identifier \"com.hrtt.applocmac\" and certificate leaf[subject.OU] = \"CDAW7B5WR4\""
    static let helperCodeSigningRequirement = "anchor apple generic and identifier \"com.hrtt.applocmac.helper\" and certificate leaf[subject.OU] = \"CDAW7B5WR4\""
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
