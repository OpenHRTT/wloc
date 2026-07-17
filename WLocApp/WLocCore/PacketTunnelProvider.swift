import Foundation
import NetworkExtension
#if os(macOS)
import Darwin
#endif

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let localTunnelAddress = "10.10.0.1"
    private let localTunnelSubnetMask = "255.255.255.0"
    private var wlocService: AppWLocTunnelService?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: localTunnelAddress)
        let ipv4 = NEIPv4Settings(addresses: [localTunnelAddress], subnetMasks: [localTunnelSubnetMask])
        var includedRoutes = [NEIPv4Route(destinationAddress: localTunnelAddress, subnetMask: localTunnelSubnetMask)]
        #if os(macOS)
        let wlocRoutes = Self.wlocHostRoutes()
        includedRoutes.append(contentsOf: wlocRoutes)
        AppWLocUtils.debugLog(
            "\(AppWLocConfig.displayName) macOS WLoc included routes=\(wlocRoutes.map { $0.destinationAddress }.joined(separator: ","))"
        )
        #endif
        ipv4.includedRoutes = includedRoutes
        #if !os(macOS)
        ipv4.excludedRoutes = [.default()]
        #endif
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

#if os(macOS)
private extension PacketTunnelProvider {
    static func wlocHostRoutes() -> [NEIPv4Route] {
        let addresses = AppWLocConfig.appWLocHosts
            .flatMap { resolvedIPv4Addresses(for: $0) }
            .sorted()

        return Array(Set(addresses)).map { address in
            NEIPv4Route(destinationAddress: address, subnetMask: "255.255.255.255")
        }
    }

    static func resolvedIPv4Addresses(for host: String) -> [String] {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_INET,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, "443", &hints, &result)
        guard status == 0 else {
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 解析 \(host) 失败：\(String(cString: gai_strerror(status)))")
            return []
        }
        defer { freeaddrinfo(result) }

        var addresses: [String] = []
        var pointer = result
        while let info = pointer {
            defer { pointer = info.pointee.ai_next }
            guard info.pointee.ai_family == AF_INET,
                  let sockaddr = info.pointee.ai_addr else {
                continue
            }

            let sockaddrIn = sockaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var address = sockaddrIn.sin_addr
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                continue
            }
            addresses.append(String(cString: buffer))
        }

        AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 解析 \(host) -> \(addresses.joined(separator: ","))")
        return addresses
    }
}
#endif
