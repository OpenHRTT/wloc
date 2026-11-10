import Foundation
import GCDWebServer

final class CertificateDownloadServer {
    static let shared = CertificateDownloadServer()

    private let server = GCDWebServer()
    private(set) var urlString: String?

    var isRunning: Bool {
        server.isRunning
    }

    /// 证书下载继续沿用本机服务，和 DNS 文件共用同一个端口。
    func start() throws -> String {
        guard let data = rootCertificateData() else {
            throw AppWLocCertificateError.rootCertificateNotFound
        }
        return try start(data: data, fileName: AppWLocConfig.rootCertificateDownloadFileName,
                         contentType: "application/x-x509-ca-cert")
    }

    /// 按资源文件名下载当前平台内置的 DNS 描述文件。
    func startDNSProfile() throws -> String {
        guard let url = Bundle.main.url(forResource: AppWLocConfig.dnsProfileResourceName,
                                        withExtension: "mobileconfig") else {
            throw NSError(domain: "WLocDNSProfile", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "未找到 DNS 描述文件，请重新安装完整的 App。"])
        }
        return try start(data: Data(contentsOf: url),
                         fileName: url.lastPathComponent,
                         contentType: "application/x-apple-aspen-config")
    }

    /// 浏览器访问本机地址即可下载；切换文件时替换原来的下载路由。
    private func start(data: Data, fileName: String, contentType: String) throws -> String {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(AppWLocConfig.certificateServerPort)
        components.path = "/\(fileName)"
        guard let url = components.url else { throw URLError(.badURL) }

        let encodedFileName = String(components.percentEncodedPath.dropFirst())
        let disposition = fileName == encodedFileName
            ? "attachment; filename=\"\(fileName)\""
            : "attachment; filename*=UTF-8''\(encodedFileName)"

        stop()
        server.removeAllHandlers()
        server.addHandler(
            forMethod: "GET",
            path: components.path,
            request: GCDWebServerRequest.self
        ) { _ in
            let response = GCDWebServerDataResponse(data: data, contentType: contentType)
            response.setValue(disposition, forAdditionalHeader: "Content-Disposition")
            return response
        }

        var options: [String: Any] = [
            GCDWebServerOption_Port: AppWLocConfig.certificateServerPort,
            GCDWebServerOption_BindToLocalhost: true
        ]
        #if os(iOS)
        options[GCDWebServerOption_AutomaticallySuspendInBackground] = false
        #endif
        try server.start(options: options)

        urlString = url.absoluteString
        return url.absoluteString
    }

    func stop() {
        if isRunning {
            server.stop()
        }
        urlString = nil
    }

    private func rootCertificateData() -> Data? {
        if let url = Bundle.main.url(
            forResource: AppWLocConfig.rootCertificateResourceName,
            withExtension: "cer"
        ) {
            return try? Data(contentsOf: url)
        }
        return try? AppWLocCertificateStore.shared.loadRootCertificateData()
    }

    private static func bestLocalIPAddress() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            return nil
        }
        defer { freeifaddrs(interfaces) }

        var fallback: String?
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            let flags = Int32(item.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            guard isUp, !isLoopback,
                  let address = item.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let name = String(cString: item.pointee.ifa_name)
            let ip = String(cString: host)
            if name == "en0" {
                return ip
            }
            fallback = fallback ?? ip
        }
        return fallback
    }
}
