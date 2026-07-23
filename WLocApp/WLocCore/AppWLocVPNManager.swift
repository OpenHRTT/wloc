import CoreLocation
import Foundation
import NetworkExtension

enum AppWLocVPNManagerError: Error, LocalizedError {
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

final class AppWLocVPNManager {
    private let providerBundleIdentifier: String
    private let localizedDescription: String
    private var cachedManager: NETunnelProviderManager?

    init(providerBundleIdentifier: String, localizedDescription: String? = nil) {
        self.providerBundleIdentifier = providerBundleIdentifier
        self.localizedDescription = "\(localizedDescription ?? AppWLocConfig.displayName)-App VPN"
    }

    func lock(to place: AppWLocPlace, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            let responseCoordinate = AppWLocCoordinateTool.wlocResponseCoordinate(fromAppleMapCoordinate: place.coordinate)
            AppWLocUtils.debugLog(
                "\(AppWLocConfig.displayName) 准备锁定位置 apple=(\(place.latitude), \(place.longitude)) response=(\(responseCoordinate.latitude), \(responseCoordinate.longitude))"
            )
            try AppWLocStateStore.shared.lock(
                latitude: responseCoordinate.latitude,
                longitude: responseCoordinate.longitude
            )
        } catch {
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) 锁定坐标保存失败：\(error.localizedDescription)")
            completion(.failure(error))
            return
        }

        stop(clearState: false) { _ in
            AppWLocUtils.mainThreadAfter(1.0) {
                self.start(completion: completion)
            }
        }
    }

    func stop(clearState: Bool = false, completion: ((Error?) -> Void)? = nil) {
        AppWLocUtils.debugLog("\(AppWLocConfig.displayName) VPN stop clearState=\(clearState)")
        if clearState {
            AppWLocStateStore.shared.clear()
        }
        if let cachedManager {
            cachedManager.isEnabled = false
            cachedManager.connection.stopVPNTunnel()
            completion?(nil)
            return
        }

        loadExistingManager { result in
            switch result {
            case .success(let manager):
                self.cachedManager = manager
                manager.isEnabled = false
                manager.connection.stopVPNTunnel()
                completion?(nil)
            case .failure(let error):
                if case AppWLocVPNManagerError.managerUnavailable = error {
                    completion?(nil)
                } else {
                    completion?(error)
                }
            }
        }
    }

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        AppWLocUtils.debugLog(
            "\(AppWLocConfig.displayName) VPN start provider=\(providerBundleIdentifier)，log=\(AppWLocUtils.debugLogURL?.path ?? "unavailable")"
        )

        startVPNConfiguration(completion: completion)
    }

    private func startVPNConfiguration(completion: @escaping (Result<Void, Error>) -> Void) {
        loadOrCreateManager { result in
            switch result {
            case .failure(let error):
                AppWLocUtils.debugLog("\(AppWLocConfig.displayName) VPN load/create failed：\(error.localizedDescription)")
                completion(.failure(error))
            case .success(let manager):
                self.startLoadedManager(manager, completion: completion)
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

    private func loadExistingManager(completion: @escaping (Result<NETunnelProviderManager, Error>) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let manager = managers?.first(where: { existing in
                (existing.protocolConfiguration as? NETunnelProviderProtocol)?
                    .providerBundleIdentifier == self.providerBundleIdentifier
            }) else {
                completion(.failure(AppWLocVPNManagerError.managerUnavailable))
                return
            }

            completion(.success(manager))
        }
    }

    private func loadOrCreateManager(completion: @escaping (Result<NETunnelProviderManager, Error>) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error {
                AppWLocUtils.debugLog("\(AppWLocConfig.displayName) VPN load preferences failed：\(error.localizedDescription)")
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
                    AppWLocUtils.debugLog("\(AppWLocConfig.displayName) VPN save preferences failed：\(saveError.localizedDescription)")
                    completion(.failure(saveError))
                    return
                }
                manager.loadFromPreferences { loadError in
                    if let loadError {
                        AppWLocUtils.debugLog("\(AppWLocConfig.displayName) VPN reload preferences failed：\(loadError.localizedDescription)")
                        completion(.failure(loadError))
                        return
                    }
                    manager.isEnabled = true
                    manager.isOnDemandEnabled = false
                    self.cachedManager = manager
                    completion(.success(manager))
                }
            }
        }
    }

    private func startLoadedManager(
        _ manager: NETunnelProviderManager,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        manager.isEnabled = true
        manager.isOnDemandEnabled = false
        manager.saveToPreferences { saveError in
            if let saveError {
                AppWLocUtils.debugLog("\(AppWLocConfig.displayName) VPN save before start failed：\(saveError.localizedDescription)")
                completion(.failure(saveError))
                return
            }

            manager.loadFromPreferences { loadError in
                if let loadError {
                    AppWLocUtils.debugLog("\(AppWLocConfig.displayName) VPN reload before start failed：\(loadError.localizedDescription)")
                    completion(.failure(loadError))
                    return
                }

                self.startLoadedPreparedManager(manager, completion: completion)
            }
        }
    }

    private func startLoadedPreparedManager(
        _ manager: NETunnelProviderManager,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        do {
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) VPN current status before start=\(manager.connection.status.rawValue)")
            switch manager.connection.status {
            case .connected, .connecting, .reasserting:
                AppWLocUtils.debugLog("\(AppWLocConfig.displayName) VPN already active status=\(manager.connection.status.rawValue)")
                completion(.success(()))
                return
            default:
                break
            }
            try manager.connection.startVPNTunnel()
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) VPN startVPNTunnel called")
            completion(.success(()))
        } catch {
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) VPN startVPNTunnel failed：\(error.localizedDescription)")
            completion(.failure(error))
        }
    }

}
