import CoreLocation
import Foundation
import NetworkExtension

enum WLocVPNManagerError: Error, LocalizedError {
    case managerUnavailable
    case protocolUnavailable
    case startFailed

    var errorDescription: String? {
        switch self {
        case .managerUnavailable:
            return "无法读取增强定位 VPN 配置"
        case .protocolUnavailable:
            return "增强定位 VPN 协议配置不可用"
        case .startFailed:
            return "增强定位启动失败，请确认已允许 VPN 配置"
        }
    }
}

final class WLocVPNManager {
    private let providerBundleIdentifier: String
    private let localizedDescription: String

    init(providerBundleIdentifier: String, localizedDescription: String = "WLoc 增强定位") {
        self.providerBundleIdentifier = providerBundleIdentifier
        self.localizedDescription = localizedDescription
    }

    func lock(to place: WLocPlace, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            try AppWLocStateStore.shared.enable(
                latitude: place.latitude,
                longitude: place.longitude
            )
        } catch {
            completion(.failure(error))
            return
        }
        start(completion: completion)
    }

    func disable(completion: ((Error?) -> Void)? = nil) {
        AppWLocStateStore.shared.setEnhancedModeEnabled(false)
        loadOrCreateManager { result in
            switch result {
            case .success(let manager):
                manager.connection.stopVPNTunnel()
                completion?(nil)
            case .failure(let error):
                completion?(error)
            }
        }
    }

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        loadOrCreateManager { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let manager):
                manager.loadFromPreferences { loadError in
                    if let loadError {
                        completion(.failure(loadError))
                        return
                    }
                    do {
                        if manager.connection.status == .connected || manager.connection.status == .connecting {
                            manager.connection.stopVPNTunnel()
                        }
                        try manager.connection.startVPNTunnel(options: [
                            "TunnelDeviceIP": "10.8.0.1" as NSString,
                            "TunnelFakeIP": "10.8.0.2" as NSString
                        ])
                        completion(.success(()))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    func loadStatus(completion: @escaping (NEVPNStatus) -> Void) {
        loadOrCreateManager { result in
            switch result {
            case .success(let manager):
                completion(manager.connection.status)
            case .failure:
                completion(.invalid)
            }
        }
    }

    private func loadOrCreateManager(completion: @escaping (Result<NETunnelProviderManager, Error>) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error {
                completion(.failure(error))
                return
            }

            let manager = managers?.first(where: { existing in
                (existing.protocolConfiguration as? NETunnelProviderProtocol)?
                    .providerBundleIdentifier == self.providerBundleIdentifier
            }) ?? NETunnelProviderManager()

            let tunnelProtocol = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
            tunnelProtocol.providerBundleIdentifier = self.providerBundleIdentifier
            tunnelProtocol.serverAddress = "\(AppWLocConfig.displayName) Local Tunnel"
            tunnelProtocol.disconnectOnSleep = false

            manager.localizedDescription = self.localizedDescription
            manager.protocolConfiguration = tunnelProtocol
            manager.isEnabled = true
            manager.isOnDemandEnabled = false
            manager.saveToPreferences { saveError in
                if let saveError {
                    completion(.failure(saveError))
                    return
                }
                completion(.success(manager))
            }
        }
    }
}
