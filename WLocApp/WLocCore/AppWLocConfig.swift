import Foundation

enum AppWLocConfig {
    static var displayName: String {
//        let keys = ["CFBundleDisplayName", "CFBundleName"]
//        for key in keys {
//            if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
//               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
//                return value
//            }
//        }
        return "WLoc8.com"
    }

    static var rootCertificateDownloadFileName: String {
        return "WLoc8.com-RootCA.cer"
//        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
//        let slugScalars = displayName.unicodeScalars.map { scalar -> String in
//            allowed.contains(scalar) ? String(scalar) : "-"
//        }
//        let slug = slugScalars.joined()
//            .split(separator: "-", omittingEmptySubsequences: true)
//            .joined(separator: "-")
//        return "\((slug.isEmpty ? "WLoc8" : slug))-RootCA.cer"
    }

    static let appGroupIdentifier = "group.com.wlocapp.shared"

    static let defaultsSuiteName = appGroupIdentifier
    static var tunnelProviderBundleIdentifier: String {
        if let bundleIdentifier = Bundle.main.bundleIdentifier,
           !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(bundleIdentifier).tunnel"
        }
        #if os(macOS)
        return "com.wlocapp.mac.tunnel"
        #else
        return "com.hrtt.apploc.tunnel"
        #endif
    }

    static let localProxyHost = "127.0.0.1"
    static let localProxyPort: UInt16 = 19090
    static let certificateServerPort: UInt = 18088

    static let iOSWLocHosts: Set<String> = [
        "gs-loc.apple.com",
        "gs-loc-cn.apple.com"
    ]
    static let iOSWLocPath = "/clls/wloc"

    static let macOSWLocHosts: Set<String> = [
        "gs-loc.apple.com",
        "gs-loc-cn.apple.com"
    ]
    static let macOSWLocPath = "/clls/wloc"

    #if os(macOS)
    static let appWLocHosts = macOSWLocHosts
    static let wlocPath = macOSWLocPath
    #else
    static let appWLocHosts = iOSWLocHosts
    static let wlocPath = iOSWLocPath
    #endif
    static let proxyIdentityResourceName = "AppWLocProxy"
    static let rootCertificateResourceName = "AppWLocRootCA"
    static let proxyIdentityPassword = "1"
}
