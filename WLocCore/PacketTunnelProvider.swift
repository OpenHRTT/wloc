import Foundation
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var tunnelDeviceIP = "10.8.0.1"
    private var tunnelFakeIP = "10.8.0.2"
    private let tunnelSubnetMask = "255.255.255.0"
    private var deviceIPValue: UInt32 = 0
    private var fakeIPValue: UInt32 = 0
    private var wlocService: AppWLocTunnelService?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        if let value = options?["TunnelDeviceIP"] as? String {
            tunnelDeviceIP = value
        }
        if let value = options?["TunnelFakeIP"] as? String {
            tunnelFakeIP = value
        }

        deviceIPValue = ipToUInt32(tunnelDeviceIP)
        fakeIPValue = ipToUInt32(tunnelFakeIP)

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: tunnelDeviceIP)
        let ipv4 = NEIPv4Settings(addresses: [tunnelDeviceIP], subnetMasks: [tunnelSubnetMask])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: tunnelDeviceIP, subnetMask: tunnelSubnetMask)]
        ipv4.excludedRoutes = [.default()]
        settings.ipv4Settings = ipv4

        let shouldStartProxy = AppWLocStateStore.shared.load()?.enabled == true
        if shouldStartProxy {
            AppWLocTunnelService.applyProxySettings(to: settings)
        }

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else { return }
            if let error {
                completionHandler(error)
                return
            }

            if shouldStartProxy {
                do {
                    let service = AppWLocTunnelService()
                    try service.start()
                    self.wlocService = service
                } catch {
                    completionHandler(error)
                    return
                }
            }

            self.relayPackets()
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        wlocService?.stop()
        wlocService = nil
        completionHandler()
    }

    private func relayPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self else { return }
            var modified = packets
            for index in modified.indices where protocols[index].int32Value == AF_INET && modified[index].count >= 20 {
                modified[index].withUnsafeMutableBytes { bytes in
                    guard let pointer = bytes.baseAddress?.assumingMemoryBound(to: UInt32.self) else { return }
                    let source = UInt32(bigEndian: pointer[3])
                    let destination = UInt32(bigEndian: pointer[4])
                    if source == self.deviceIPValue {
                        pointer[3] = self.fakeIPValue.bigEndian
                    }
                    if destination == self.fakeIPValue {
                        pointer[4] = self.deviceIPValue.bigEndian
                    }
                }
            }
            self.packetFlow.writePackets(modified, withProtocols: protocols)
            self.relayPackets()
        }
    }

    private func ipToUInt32(_ ipString: String) -> UInt32 {
        let parts = ipString.split(separator: ".")
        guard parts.count == 4,
              let b1 = UInt32(parts[0]),
              let b2 = UInt32(parts[1]),
              let b3 = UInt32(parts[2]),
              let b4 = UInt32(parts[3]) else {
            return 0
        }
        return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4
    }
}
