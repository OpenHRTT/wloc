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
            return "无法读取 \(AppWLocConfig.displayName) VPN 配置"
        case .protocolUnavailable:
            return "\(AppWLocConfig.displayName) VPN 协议配置不可用"
        case .startFailed:
            return "\(AppWLocConfig.displayName) 启动失败，请确认已允许 VPN 配置"
        }
    }
}

final class WLocVPNManager {
    private let providerBundleIdentifier: String
    private let localizedDescription: String
    private var cachedManager: NETunnelProviderManager?

    init(providerBundleIdentifier: String, localizedDescription: String? = nil) {
        self.providerBundleIdentifier = providerBundleIdentifier
        self.localizedDescription = localizedDescription ?? "WLoc8.com"
    }

    func lock(to place: WLocPlace, completion: @escaping (Result<Void, Error>) -> Void) {
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

                    let saveAndStart = {
                        do {
                            try AppWLocStateStore.shared.lock(
                                latitude: place.latitude,
                                longitude: place.longitude
                            )
                        } catch {
                            completion(.failure(error))
                            return
                        }
                        self.startLoadedManager(manager, completion: completion)
                    }

                    switch manager.connection.status {
                    case .connected, .connecting, .reasserting, .disconnecting:
                        manager.connection.stopVPNTunnel()
                        AppWLocUtils.mainThreadAfter(0.8) {
                            saveAndStart()
                        }
                    default:
                        saveAndStart()
                    }
                }
            }
        }
    }

    func disable(completion: ((Error?) -> Void)? = nil) {
        AppWLocStateStore.shared.clear()
        if let cachedManager {
            cachedManager.connection.stopVPNTunnel()
            completion?(nil)
            return
        }
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
                    self.startLoadedManager(manager, completion: completion)
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
                self.cachedManager = manager
                completion(.success(manager))
            }
        }
    }

    private func startLoadedManager(
        _ manager: NETunnelProviderManager,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        do {
            switch manager.connection.status {
            case .connected, .connecting, .reasserting:
                completion(.success(()))
                return
            default:
                break
            }
            try manager.connection.startVPNTunnel()
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }
}
