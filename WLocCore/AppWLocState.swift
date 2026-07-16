import Foundation

/// WLoc 增强定位使用的锁定点状态。
///
/// 这里不读写 `DXMapUserSelectLocation`、`DXMapUtils` 或旧定位服务的状态。
/// 主 App 显式保存后，Packet Tunnel 扩展通过 App Group 读取同一份数据。
struct AppWLocLockState: Codable, Equatable {
    var enabled: Bool
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var horizontalAccuracy: Int64
    var verticalAccuracy: Int64
    var updatedAt: Date

    init(
        enabled: Bool,
        latitude: Double,
        longitude: Double,
        altitude: Double = 480,
        horizontalAccuracy: Int64 = 39,
        verticalAccuracy: Int64 = 1000,
        updatedAt: Date = Date()
    ) {
        self.enabled = enabled
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.updatedAt = updatedAt
    }
}

enum AppWLocStateStoreError: Error, LocalizedError {
    case invalidCoordinate
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .invalidCoordinate:
            return "\(AppWLocConfig.displayName) 锁定坐标无效"
        case .encodeFailed:
            return "\(AppWLocConfig.displayName) 状态保存失败"
        }
    }
}

final class AppWLocStateStore {
    static let shared = AppWLocStateStore()

    private let key = "AppWLoc.lockState.v1"
    private let enhancedModeKey = "AppWLoc.enhancedModeEnabled.v1"
    private let defaults: UserDefaults

    init() {
        let defaults = UserDefaults(suiteName: AppWLocConfig.defaultsSuiteName)
        self.defaults = defaults ?? .standard
    }

    func setEnhancedModeEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: enhancedModeKey)
        defaults.synchronize()
        if !enabled {
            disable()
        }
    }

    func isEnhancedModeEnabled() -> Bool {
        defaults.bool(forKey: enhancedModeKey)
    }

    func save(_ state: AppWLocLockState) throws {
        guard let data = try? JSONEncoder().encode(state) else {
            throw AppWLocStateStoreError.encodeFailed
        }
        defaults.set(data, forKey: key)
        defaults.synchronize()
        
        print("锁定位置 lat：\(state.latitude)，lng：\(state.longitude)， alt：\(state.altitude)")
    }

    func enable(
        latitude: Double,
        longitude: Double,
        altitude: Double = 480,
        horizontalAccuracy: Int64 = 39,
        verticalAccuracy: Int64 = 1000
    ) throws {
        defaults.set(true, forKey: enhancedModeKey)
        try save(AppWLocLockState(
            enabled: true,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy
        ))
    }

    func disable() {
        if var state = load() {
            state.enabled = false
            try? save(state)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func load() -> AppWLocLockState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AppWLocLockState.self, from: data)
    }
}
