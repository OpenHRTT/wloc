import Foundation
import NetworkExtension

/// WLoc 在扩展侧的代理入口。
///
/// VPN 网络参数由 `PacketTunnelProvider` 统一设置，这里只负责本地 HTTPS
/// 代理的生命周期，并提供只匹配 WLoc 域名的代理配置。
final class AppWLocTunnelService {
    private var isRunning = false
    private let proxyServer = AppWLocHTTPProxyServer(port: AppWLocConfig.localProxyPort)

    func start() throws {
        guard !isRunning else {
            return
        }

        do {
            try proxyServer.start()
            isRunning = true
        } catch {
            proxyServer.stop()
            throw error
        }
    }

    func stop() {
        isRunning = false
        proxyServer.stop()
    }

    static func applyProxySettings(to settings: NEPacketTunnelNetworkSettings) {
        let dns = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        dns.matchDomains = Array(AppWLocConfig.appWLocHosts)
        settings.dnsSettings = dns

        let proxy = NEProxySettings()
        proxy.httpsEnabled = true
        proxy.httpsServer = NEProxyServer(
            address: AppWLocConfig.localProxyHost,
            port: Int(AppWLocConfig.localProxyPort)
        )
        proxy.matchDomains = Array(AppWLocConfig.appWLocHosts)
        proxy.excludeSimpleHostnames = true
        settings.proxySettings = proxy
    }

    func mutateCapturedWLocResponse(_ body: Data) throws -> Data {
        guard let state = AppWLocStateStore.shared.load() else {
            throw AppWLocMutatorError.invalidCoordinate
        }
        return try AppWLocMutator.mutateResponseBody(body, using: state)
    }
}
