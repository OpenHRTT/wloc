import Foundation
import GCDWebServer

final class CertificateDownloadServer {
    static let shared = CertificateDownloadServer()

    private let server = GCDWebServer()
    private(set) var urlString: String?

    var isRunning: Bool {
        server.isRunning
    }

    func start() throws -> String {
        if let urlString, server.isRunning {
            return urlString
        }

        guard let data = rootCertificateData() else {
            throw AppWLocCertificateError.rootCertificateNotFound
        }

        let fileName = AppWLocConfig.rootCertificateDownloadFileName

        server.removeAllHandlers()
        server.addHandler(
            forMethod: "GET",
            path: "/\(fileName)",
            request: GCDWebServerRequest.self
        ) { _ in
            let response = GCDWebServerDataResponse(data: data, contentType: "application/x-x509-ca-cert")
            response.setValue("attachment; filename=\"\(fileName)\"", forAdditionalHeader: "Content-Disposition")
            return response
        }

        var options: [String: Any] = [
            GCDWebServerOption_Port: AppWLocConfig.certificateServerPort,
            GCDWebServerOption_BindToLocalhost: false
        ]
        #if os(iOS)
        options[GCDWebServerOption_AutomaticallySuspendInBackground] = false
        #endif
        try server.start(options: options)

        let host = Self.bestLocalIPAddress() ?? "127.0.0.1"
        let value = "http://\(host):\(AppWLocConfig.certificateServerPort)/\(fileName)"
        urlString = value
        return value
    }

    func stop() {
        server.stop()
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
