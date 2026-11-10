import Foundation

enum AppWLocConfig {
    static let displayName = "WLoc8.com"
    #if os(iOS)
    static let rootCertificateDownloadFileName = "WLoc8.com-iOS-App-RootCA.cer"
    static let dnsProfileName = "Apple定位屏蔽增强-TG：wloc88"
    static let dnsProfileResourceName = "wloc-dns-ios"
    #else
    static let rootCertificateDownloadFileName = "WLoc8.com-RootCA.cer"
    static let dnsProfileName = "Apple定位屏蔽增强-TG：wloc88（macOS）"
    static let dnsProfileResourceName = "wloc-dns-mac"
    #endif

    #if os(iOS)
    private static let builtInAppGroupIdentifier = "group.com.wlocapp.shared"
    private static let provisioningProfileEntitlements: [String: Any]? = {
        guard let profileURL = Bundle.main.url(
            forResource: "embedded",
            withExtension: "mobileprovision"
        ),
        let profileData = try? Data(contentsOf: profileURL),
        let plistStart = profileData.range(of: Data("<?xml".utf8)),
        let plistEnd = profileData.range(
            of: Data("</plist>".utf8),
            options: .backwards
        ) else {
            return nil
        }

        let plistData = profileData.subdata(in: plistStart.lowerBound..<plistEnd.upperBound)
        guard let profile = try? PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ) as? [String: Any] else {
            return nil
        }
        return profile["Entitlements"] as? [String: Any]
    }()
    static let provisionedAppGroupIdentifiers: [String] = {
        guard let value = provisioningProfileEntitlements?[
            "com.apple.security.application-groups"
        ] as? [String] else {
            return []
        }
        return value
    }()
    static let appGroupIdentifier: String = {
        var candidates = provisionedAppGroupIdentifiers
        if let builtInIndex = candidates.firstIndex(of: builtInAppGroupIdentifier) {
            candidates.remove(at: builtInIndex)
            candidates.insert(builtInAppGroupIdentifier, at: 0)
        }
        if !candidates.contains(builtInAppGroupIdentifier) {
            candidates.append(builtInAppGroupIdentifier)
        }
        return candidates.first(where: {
            FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: $0
            ) != nil
        }) ?? candidates.first ?? builtInAppGroupIdentifier
    }()
    static let defaultsSuiteName: String? = appGroupIdentifier
    static var tunnelProviderBundleIdentifier: String {
        if let plugInsURL = Bundle.main.builtInPlugInsURL,
           let plugInURLs = try? FileManager.default.contentsOfDirectory(
            at: plugInsURL,
            includingPropertiesForKeys: nil
           ),
           let packetTunnelIdentifier = plugInURLs.lazy.compactMap({ Bundle(url: $0) }).first(where: {
               guard let extensionInfo = $0.object(forInfoDictionaryKey: "NSExtension") as? [String: Any] else {
                   return false
               }
               return extensionInfo["NSExtensionPointIdentifier"] as? String
                   == "com.apple.networkextension.packet-tunnel"
           })?.bundleIdentifier {
            return packetTunnelIdentifier
        }
        if let bundleIdentifier = Bundle.main.bundleIdentifier,
           !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(bundleIdentifier).tunnel"
        }
        return "com.hrtt.apploc.tunnel"
    }
    static var signingDiagnostics: String {
        let groups = provisionedAppGroupIdentifiers.isEmpty
            ? "<未读取到>"
            : provisionedAppGroupIdentifiers.joined(separator: ",")
        let applicationIdentifier = provisioningProfileEntitlements?[
            "application-identifier"
        ] as? String ?? "<未读取到>"
        let containerAvailable = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) != nil
        return "bundle=\(Bundle.main.bundleIdentifier ?? "<nil>")"
            + " provider=\(tunnelProviderBundleIdentifier)"
            + " profileAppIdentifier=\(applicationIdentifier)"
            + " profileAppGroups=\(groups)"
            + " selectedAppGroup=\(appGroupIdentifier)"
            + " sharedContainer=\(containerAvailable ? "available" : "unavailable")"
    }
    #else
    static let defaultsSuiteName: String? = nil
    #endif

    static let localProxyHost = "127.0.0.1"
    static let localProxyPort: UInt16 = 19090
    static let certificateServerPort: UInt = 18088
    #if os(macOS)
    static let pacServerPort: UInt = 18089
    static let pacPath = "/wloc.pac"
    #endif

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

    static let githubRepository = "OpenHRTT/wloc"
    static let githubRepositoryURL = URL(string: "https://github.com/OpenHRTT/wloc")!

    static var currentVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? version! : "1.0"
    }
}

enum AppWLocReleasePlatform {
    case macOS
    case iOS
}

struct AppWLocAvailableUpdate {
    let version: String
    let releasePageURL: URL
    let downloadURL: URL
    let assetName: String?
    let assetSize: Int64?
    let assetDigest: String?
}

enum AppWLocUpdateCheckResult {
    case updateAvailable(AppWLocAvailableUpdate)
    case upToDate(latestVersion: String)
    case failure(Error)
}

final class AppWLocUpdateChecker {
    static let shared = AppWLocUpdateChecker()

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL
            let size: Int64?
            let digest: String?

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
                case size, digest
            }
        }

        let tagName: String
        let htmlURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    private enum CheckError: LocalizedError {
        case invalidResponse
        case serverStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "GitHub 返回了无法识别的响应。"
            case .serverStatus(let status):
                return "GitHub 更新服务暂时不可用（HTTP \(status)）。"
            }
        }
    }

    private init() {}

    /// 查询最新正式发布；Mac 遇到 API 限流时改读同一仓库的官方发布页。
    func check(platform: AppWLocReleasePlatform, completion: @escaping (AppWLocUpdateCheckResult) -> Void) {
        let endpoint = URL(string: "https://api.github.com/repos/\(AppWLocConfig.githubRepository)/releases/latest")!
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("WLoc8.com/\(AppWLocConfig.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: AppWLocUpdateCheckResult
            if let error = error {
                result = .failure(error)
            } else if let httpResponse = response as? HTTPURLResponse,
                      !(200...299).contains(httpResponse.statusCode) {
                if platform == .macOS, [403, 429].contains(httpResponse.statusCode) {
                    self.checkMacReleasePage(completion: completion)
                    return
                }
                result = .failure(CheckError.serverStatus(httpResponse.statusCode))
            } else if let data = data,
                      let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) {
                let latestVersion = Self.normalizedVersion(release.tagName)
                if Self.isVersion(latestVersion, newerThan: AppWLocConfig.currentVersion) {
                    // 优先直达当前平台的安装包；Release 未上传对应资产时回退到发布页，避免按钮失效。
                    let preferredExtension = platform == .macOS ? ".dmg" : ".ipa"
                    let asset = release.assets.first {
                        $0.name.lowercased().hasSuffix(preferredExtension)
                    }
                    result = .updateAvailable(
                        AppWLocAvailableUpdate(
                            version: latestVersion,
                            releasePageURL: release.htmlURL,
                            downloadURL: asset?.browserDownloadURL ?? release.htmlURL,
                            assetName: asset?.name,
                            assetSize: asset?.size,
                            assetDigest: asset?.digest
                        )
                    )
                } else {
                    result = .upToDate(latestVersion: latestVersion)
                }
            } else {
                result = .failure(CheckError.invalidResponse)
            }

            DispatchQueue.main.async {
                completion(result)
            }
        }.resume()
    }

    /// 从 GitHub 的 latest 跳转取得正式版本，再从对应下载列表读取 DMG 和 SHA-256。
    private func checkMacReleasePage(completion: @escaping (AppWLocUpdateCheckResult) -> Void) {
        let latestURL = AppWLocConfig.githubRepositoryURL.appendingPathComponent("releases/latest")
        var request = URLRequest(url: latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("WLoc8.com", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { _, response, error in
            let finish: (AppWLocUpdateCheckResult) -> Void = { result in DispatchQueue.main.async { completion(result) } }
            guard error == nil, let response = response as? HTTPURLResponse, response.statusCode == 200,
                  let pageURL = response.url, pageURL.host == "github.com",
                  pageURL.path.hasPrefix("/\(AppWLocConfig.githubRepository)/releases/tag/") else {
                finish(.failure(error ?? CheckError.invalidResponse))
                return
            }
            let version = Self.normalizedVersion(pageURL.lastPathComponent)
            guard Self.isVersion(version, newerThan: AppWLocConfig.currentVersion) else {
                finish(.upToDate(latestVersion: version))
                return
            }
            let assetsURL = AppWLocConfig.githubRepositoryURL.appendingPathComponent("releases/expanded_assets").appendingPathComponent(pageURL.lastPathComponent)
            URLSession.shared.dataTask(with: URLRequest(url: assetsURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)) { data, response, error in
                guard error == nil, let response = response as? HTTPURLResponse, response.statusCode == 200,
                      let data, let html = String(data: data, encoding: .utf8) else {
                    finish(.failure(error ?? CheckError.invalidResponse))
                    return
                }
                // 只解析下载资产所在的列表项，不依赖发布正文或页面上的其他链接。
                let items = html.components(separatedBy: "<li ")
                let linkPattern = #"href="([^"]+\.dmg)""#
                let digestPattern = #"sha256:([a-fA-F0-9]{64})"#
                var downloadURL = pageURL
                var digest: String?
                for item in items {
                    guard let path = Self.firstCapture(linkPattern, in: item),
                          path.hasPrefix("/\(AppWLocConfig.githubRepository)/releases/download/"),
                          let url = URL(string: path, relativeTo: AppWLocConfig.githubRepositoryURL)?.absoluteURL else { continue }
                    downloadURL = url
                    digest = Self.firstCapture(digestPattern, in: item).map { "sha256:\($0)" }
                    break
                }
                finish(.updateAvailable(AppWLocAvailableUpdate(
                    version: version, releasePageURL: pageURL, downloadURL: downloadURL,
                    assetName: downloadURL == pageURL ? nil : downloadURL.lastPathComponent,
                    assetSize: nil, assetDigest: digest
                )))
            }.resume()
        }.resume()
    }

    /// 读取固定格式中的单个字段，匹配不到时交给调用方处理。
    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// 去掉发布标签前的 v，供检查更新和安装包版本校验共用。
    static func normalizedVersion(_ version: String) -> String {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
    }

    /// 按数字段比较版本，同时容许 1.2 和 1.2.0 这种等价写法。
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        // 按数字段比较版本，避免系统的字符串比较把 1.10 误判为小于 1.9。
        let separators = CharacterSet.decimalDigits.inverted
        let candidateParts = normalizedVersion(candidate).components(separatedBy: separators).compactMap(Int.init)
        let currentParts = normalizedVersion(current).components(separatedBy: separators).compactMap(Int.init)
        let count = max(candidateParts.count, currentParts.count)

        for index in 0..<count {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let currentPart = index < currentParts.count ? currentParts[index] : 0
            if candidatePart != currentPart {
                return candidatePart > currentPart
            }
        }
        return false
    }
}
