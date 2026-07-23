import Foundation
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let localTunnelAddress = "10.10.0.1"
    private let localTunnelSubnetMask = "255.255.255.0"
    private var wlocService: AppWLocTunnelService?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: localTunnelAddress)
        let ipv4 = NEIPv4Settings(addresses: [localTunnelAddress], subnetMasks: [localTunnelSubnetMask])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: localTunnelAddress, subnetMask: localTunnelSubnetMask)]
        ipv4.excludedRoutes = [.default()]
        settings.ipv4Settings = ipv4
        AppWLocTunnelService.applyProxySettings(to: settings)

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else { return }
            if let error {
                AppWLocUtils.debugLog("\(AppWLocConfig.displayName) PacketTunnel settings failed: \(error.localizedDescription)")
                completionHandler(error)
                return
            }

            do {
                let service = AppWLocTunnelService()
                try service.start()
                self.wlocService = service
                AppWLocUtils.debugLog("\(AppWLocConfig.displayName) PacketTunnel proxy service started")
            } catch {
                AppWLocUtils.debugLog("\(AppWLocConfig.displayName) PacketTunnel proxy service failed: \(error.localizedDescription)")
                completionHandler(error)
                return
            }

            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        AppWLocUtils.debugLog("\(AppWLocConfig.displayName) PacketTunnel stopTunnel reason=\(reason.rawValue)")
        wlocService?.stop()
        wlocService = nil
        completionHandler()
    }
}
