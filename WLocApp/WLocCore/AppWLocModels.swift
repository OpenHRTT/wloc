import CoreLocation
import Foundation
import MapKit

struct AppWLocPlace: Codable, Equatable {
    var id: UUID
    var name: String
    var detail: String
    var latitude: Double
    var longitude: Double
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        detail: String = "",
        latitude: Double,
        longitude: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var coordinateText: String {
        String(format: "%.6f, %.6f", latitude, longitude)
    }

    init(mapItem: MKMapItem) {
        let placemark = mapItem.placemark
        self.init(
            name: mapItem.name ?? placemark.name ?? "未命名地点",
            detail: [placemark.locality, placemark.administrativeArea, placemark.country]
                .compactMap { $0 }
                .joined(separator: " "),
            latitude: placemark.coordinate.latitude,
            longitude: placemark.coordinate.longitude
        )
    }
}

final class AppWLocFavoriteStore {
    static let shared = AppWLocFavoriteStore()

    private let key = "WLocApp.favorites.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: AppWLocConfig.defaultsSuiteName)) {
        self.defaults = defaults ?? .standard
    }

    func all() -> [AppWLocPlace] {
        guard let data = defaults.data(forKey: key),
              let places = try? JSONDecoder().decode([AppWLocPlace].self, from: data) else {
            return []
        }
        return places.sorted { $0.createdAt > $1.createdAt }
    }

    func contains(_ place: AppWLocPlace) -> Bool {
        all().contains { existing in
            abs(existing.latitude - place.latitude) < 0.000001 &&
                abs(existing.longitude - place.longitude) < 0.000001
        }
    }

    func add(_ place: AppWLocPlace) {
        var places = all()
        guard !contains(place) else { return }
        places.insert(place, at: 0)
        save(places)
    }

    func remove(id: UUID) {
        save(all().filter { $0.id != id })
    }

    private func save(_ places: [AppWLocPlace]) {
        guard let data = try? JSONEncoder().encode(places) else { return }
        defaults.set(data, forKey: key)
        defaults.synchronize()
    }
}
