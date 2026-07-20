import Foundation
import Security

enum AppWLocCertificateError: Error, LocalizedError {
    case containerUnavailable
    case identityNotFound
    case rootCertificateNotFound
    case importFailed(OSStatus)
    case invalidPKCS12
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .containerUnavailable:
            return "\(AppWLocConfig.displayName) 共享容器不可用"
        case .identityNotFound:
            return "\(AppWLocConfig.displayName) 代理证书未配置"
        case .rootCertificateNotFound:
            return "\(AppWLocConfig.displayName) 根证书未找到"
        case .importFailed(let status):
            return "\(AppWLocConfig.displayName) 代理证书导入失败：\(status)"
        case .invalidPKCS12:
            return "\(AppWLocConfig.displayName) 代理证书格式无效"
        case .writeFailed:
            return "\(AppWLocConfig.displayName) 代理证书保存失败"
        }
    }
}

/// 保存主 App 与扩展共用的代理身份证书。
///
/// p12 内需要包含服务端证书和私钥，证书的域名应覆盖
/// `gs-loc.apple.com` 与 `gs-loc-cn.apple.com`，并由用户已经在系统设置中
/// 信任的根证书签发。iOS 不允许 App 直接替用户完成根证书信任，所以这里只负责
/// 保存和读取代理握手需要的 SecIdentity。
final class AppWLocCertificateStore {
    static let shared = AppWLocCertificateStore()

    private let bundledIdentityPassword = AppWLocConfig.proxyIdentityPassword
    private let passwordKey = "AppWLoc.proxyIdentityPassword.v1"
    private let fileName = "AppWLoc/proxy_identity.p12"
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: AppWLocConfig.defaultsSuiteName)) {
        self.defaults = defaults ?? .standard
    }

    func saveProxyIdentity(p12Data: Data, password: String) throws {
        _ = try importIdentity(from: p12Data, password: password)
        guard let url = identityFileURL else {
            throw AppWLocCertificateError.containerUnavailable
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            #if os(iOS)
            try p12Data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try p12Data.write(to: url, options: [.atomic])
            #endif
            defaults.set(password, forKey: passwordKey)
            defaults.synchronize()
        } catch {
            throw AppWLocCertificateError.writeFailed
        }
    }

    func hasProxyIdentity() -> Bool {
        let hasSavedIdentity: Bool
        if let url = identityFileURL {
            hasSavedIdentity = FileManager.default.fileExists(atPath: url.path) &&
                defaults.string(forKey: passwordKey) != nil
        } else {
            hasSavedIdentity = false
        }
        return hasSavedIdentity || bundledProxyIdentityData() != nil
    }

    func loadProxyIdentity() throws -> SecIdentity {
        if let url = identityFileURL,
           FileManager.default.fileExists(atPath: url.path),
           let password = defaults.string(forKey: passwordKey) {
            let data = try Data(contentsOf: url)
            return try importIdentity(from: data, password: password)
        }

        if let data = bundledProxyIdentityData() {
            return try importIdentity(from: data, password: bundledIdentityPassword)
        }

        throw AppWLocCertificateError.identityNotFound
    }

    #if os(macOS)
    func loadProxyTLSCertificateChain() throws -> [Any] {
        let items: [[String: Any]]
        if let url = identityFileURL,
           FileManager.default.fileExists(atPath: url.path),
           let password = defaults.string(forKey: passwordKey) {
            items = try importItems(from: Data(contentsOf: url), password: password)
        } else if let data = bundledProxyIdentityData() {
            items = try importItems(from: data, password: bundledIdentityPassword)
        } else {
            throw AppWLocCertificateError.identityNotFound
        }

        guard let firstItem = items.first,
              let rawIdentity = firstItem[kSecImportItemIdentity as String] else {
            throw AppWLocCertificateError.invalidPKCS12
        }

        let identity = rawIdentity as! SecIdentity
        var tlsCertificates: [Any] = [identity]
        if let certificateChain = firstItem[kSecImportItemCertChain as String] as? [SecCertificate] {
            var leafCertificate: SecCertificate?
            _ = SecIdentityCopyCertificate(identity, &leafCertificate)

            for certificate in certificateChain {
                // macOS 的 locationd 不会自行补齐代理返回的签发链；TLS 数组首项必须是
                // 带私钥的 identity，后面只追加其余证书，不能把叶子证书重复放进去。
                if let leafCertificate,
                   CFEqual(certificate, leafCertificate) {
                    continue
                }
                tlsCertificates.append(certificate)
            }
        }
        return tlsCertificates
    }
    #endif

    func loadRootCertificateData() throws -> Data {
        if let url = identityFileURL,
           FileManager.default.fileExists(atPath: url.path),
           let password = defaults.string(forKey: passwordKey) {
            let p12Data = try Data(contentsOf: url)
            return try extractRootCertificateData(from: p12Data, password: password)
        }

        if let data = bundledProxyIdentityData() {
            return try extractRootCertificateData(from: data, password: bundledIdentityPassword)
        }

        throw AppWLocCertificateError.identityNotFound
    }

    private func bundledProxyIdentityData() -> Data? {
        // 默认代理身份证书随扩展内置，用户只需要安装并信任对应的根证书。
        guard let url = Bundle.main.url(forResource: AppWLocConfig.proxyIdentityResourceName, withExtension: "p12") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private func extractRootCertificateData(from p12Data: Data, password: String) throws -> Data {
        let items = try importItems(from: p12Data, password: password)
        guard let firstItem = items.first else {
            throw AppWLocCertificateError.invalidPKCS12
        }

        if let chain = firstItem[kSecImportItemCertChain as String] as? [SecCertificate],
           let rootCertificate = chain.last {
            return SecCertificateCopyData(rootCertificate) as Data
        }

        if let identity = firstItem[kSecImportItemIdentity as String] {
            var certificate: SecCertificate?
            let status = SecIdentityCopyCertificate(identity as! SecIdentity, &certificate)
            if status == errSecSuccess, let certificate {
                return SecCertificateCopyData(certificate) as Data
            }
        }

        throw AppWLocCertificateError.rootCertificateNotFound
    }

    func removeProxyIdentity() {
        if let url = identityFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        defaults.removeObject(forKey: passwordKey)
        defaults.synchronize()
    }

    private var identityFileURL: URL? {
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppWLocConfig.appGroupIdentifier
        ) {
            return container.appendingPathComponent(fileName, isDirectory: false)
        }

        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private func importIdentity(from p12Data: Data, password: String) throws -> SecIdentity {
        let items = try importItems(from: p12Data, password: password)
        guard let firstItem = items.first,
              let rawIdentity = firstItem[kSecImportItemIdentity as String] else {
            throw AppWLocCertificateError.invalidPKCS12
        }
        return rawIdentity as! SecIdentity
    }

    private func importItems(from p12Data: Data, password: String) throws -> [[String: Any]] {
        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        var importedItems: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options, &importedItems)
        guard status == errSecSuccess else {
            throw AppWLocCertificateError.importFailed(status)
        }
        guard let items = importedItems as? [[String: Any]] else {
            throw AppWLocCertificateError.invalidPKCS12
        }
        return items
    }
}
