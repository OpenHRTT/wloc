import Foundation

/// WLoc 使用的锁定点状态。
struct AppWLocLockState: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var horizontalAccuracy: Int64
    var verticalAccuracy: Int64
    var updatedAt: Date

    init(
        latitude: Double,
        longitude: Double,
        altitude: Double = 480,
        horizontalAccuracy: Int64 = 39,
        verticalAccuracy: Int64 = 1000,
        updatedAt: Date = Date()
    ) {
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
    private let defaults: UserDefaults

    init() {
        let defaults = UserDefaults(suiteName: AppWLocConfig.defaultsSuiteName)
        self.defaults = defaults ?? .standard
    }

    func save(_ state: AppWLocLockState) throws {
        guard (-90...90).contains(state.latitude),
              (-180...180).contains(state.longitude) else {
            throw AppWLocStateStoreError.invalidCoordinate
        }
        guard let data = try? JSONEncoder().encode(state) else {
            throw AppWLocStateStoreError.encodeFailed
        }
        defaults.set(data, forKey: key)
        defaults.synchronize()

        AppWLocUtils.debugLog("锁定位置 lat：\(state.latitude)，lng：\(state.longitude)， alt：\(state.altitude)")
    }

    func lock(
        latitude: Double,
        longitude: Double,
        altitude: Double = 480,
        horizontalAccuracy: Int64 = 39,
        verticalAccuracy: Int64 = 1000
    ) throws {
        try save(AppWLocLockState(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy
        ))
    }

    func clear() {
        defaults.removeObject(forKey: key)
        defaults.synchronize()
    }

    func load() -> AppWLocLockState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AppWLocLockState.self, from: data)
    }
}
