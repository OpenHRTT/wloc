import CoreLocation
import Foundation

enum AppWLocCoordinateSystem {
    case wgs84
    case gcj02
    case bd09
    case apple
}

enum AppWLocCoordinateTool {
    static func isInMainlandChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude
        guard longitude >= 72.004,
              longitude <= 137.8347,
              latitude >= 0.8293,
              latitude <= 55.8271 else {
            return false
        }

        let isHongKong = latitude >= 22.13 && latitude <= 22.57 && longitude >= 113.81 && longitude <= 114.52
        let isMacau = latitude >= 22.06 && latitude <= 22.24 && longitude >= 113.52 && longitude <= 113.65
        let isTaiwan = latitude >= 21.7 && latitude <= 25.6 && longitude >= 119.9 && longitude <= 122.2
        return !(isHongKong || isMacau || isTaiwan)
    }

    static func appleMapCoordinate(from coordinate: CLLocationCoordinate2D, sourceSystem: AppWLocCoordinateSystem) -> CLLocationCoordinate2D {
        switch sourceSystem {
        case .apple:
            return coordinate
        case .gcj02:
            return coordinate
        case .bd09:
            return bd09ToGCJ02(coordinate)
        case .wgs84:
            guard isInMainlandChina(coordinate) else {
                return coordinate
            }
            return wgs84ToGCJ02(coordinate)
        }
    }

    static func wlocResponseCoordinate(fromAppleMapCoordinate coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isInMainlandChina(coordinate) else {
            return coordinate
        }
        return gcj02ToWGS84(coordinate)
    }

    static func wgs84ToGCJ02(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isInMainlandChina(coordinate) else {
            return coordinate
        }

        let latitude = coordinate.latitude
        let longitude = coordinate.longitude
        var deltaLatitude = transformLatitude(longitude - 105.0, latitude - 35.0)
        var deltaLongitude = transformLongitude(longitude - 105.0, latitude - 35.0)
        let radLatitude = latitude / 180.0 * .pi
        var magic = sin(radLatitude)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        deltaLatitude = (deltaLatitude * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
        deltaLongitude = (deltaLongitude * 180.0) / (a / sqrtMagic * cos(radLatitude) * .pi)
        return CLLocationCoordinate2D(latitude: latitude + deltaLatitude, longitude: longitude + deltaLongitude)
    }

    static func gcj02ToWGS84(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isInMainlandChina(coordinate) else {
            return coordinate
        }

        var guess = coordinate
        for _ in 0..<4 {
            let converted = wgs84ToGCJ02(guess)
            guess.latitude -= converted.latitude - coordinate.latitude
            guess.longitude -= converted.longitude - coordinate.longitude
        }
        return guess
    }

    static func bd09ToGCJ02(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let x = coordinate.longitude - 0.0065
        let y = coordinate.latitude - 0.006
        let z = sqrt(x * x + y * y) - 0.00002 * sin(y * xPi)
        let theta = atan2(y, x) - 0.000003 * cos(x * xPi)
        return CLLocationCoordinate2D(latitude: z * sin(theta), longitude: z * cos(theta))
    }

    private static func transformLatitude(_ x: Double, _ y: Double) -> Double {
        var result = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        result += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        result += (160.0 * sin(y / 12.0 * .pi) + 320 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return result
    }

    private static func transformLongitude(_ x: Double, _ y: Double) -> Double {
        var result = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        result += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        result += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return result
    }

    private static let a = 6378245.0
    private static let ee = 0.00669342162296594323
    private static let xPi = .pi * 3000.0 / 180.0
}
