import CoreLocation
import Foundation
#if os(macOS)
import CoreGraphics
#endif

enum AppWLocCoordinateSystem: CaseIterable {
    case wgs84
    case gcj02
    case bd09
    case apple

    var inputTitle: String {
        switch self {
        case .wgs84:
            return "Google / GPS（WGS-84）"
        case .gcj02:
            return "高德 / 腾讯（GCJ-02）"
        case .bd09:
            return "百度（BD-09）"
        case .apple:
            return "Apple 地图"
        }
    }
}

enum AppWLocCoordinateInputError: Error, LocalizedError {
    case missingLatitude
    case missingLongitude
    case invalidLatitude
    case invalidLongitude
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .missingLatitude:
            return "请输入纬度"
        case .missingLongitude:
            return "请输入经度"
        case .invalidLatitude:
            return "纬度必须是 -90 到 90 之间的数字"
        case .invalidLongitude:
            return "经度必须是 -180 到 180 之间的数字"
        case .conversionFailed:
            return "转换后的 Apple 地图坐标无效"
        }
    }
}

enum AppWLocCoordinateTool {
    /// 校验用户输入的经纬度，并统一转换为当前 Apple 地图可直接使用的坐标。
    static func appleMapCoordinate(
        latitudeText: String,
        longitudeText: String,
        sourceSystem: AppWLocCoordinateSystem
    ) throws -> CLLocationCoordinate2D {
        let latitudeText = latitudeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let longitudeText = longitudeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latitudeText.isEmpty else {
            throw AppWLocCoordinateInputError.missingLatitude
        }
        guard !longitudeText.isEmpty else {
            throw AppWLocCoordinateInputError.missingLongitude
        }
        guard let latitude = Double(latitudeText), latitude.isFinite, (-90...90).contains(latitude) else {
            throw AppWLocCoordinateInputError.invalidLatitude
        }
        guard let longitude = Double(longitudeText), longitude.isFinite, (-180...180).contains(longitude) else {
            throw AppWLocCoordinateInputError.invalidLongitude
        }

        let sourceCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let coordinate = appleMapCoordinate(from: sourceCoordinate, sourceSystem: sourceSystem)
        guard coordinate.latitude.isFinite,
              coordinate.longitude.isFinite,
              CLLocationCoordinate2DIsValid(coordinate) else {
            throw AppWLocCoordinateInputError.conversionFailed
        }
        return coordinate
    }

    /// 判断地图坐标是否需要使用大陆坐标系。
    static func isInMainlandChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        #if os(macOS)
        return mainlandChinaBoundary.contains(
            CGPoint(x: coordinate.longitude, y: coordinate.latitude),
            using: .evenOdd
        )
        #else
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
        #endif
    }

    #if os(macOS)
    /// 加载 Natural Earth 1:10m v5.1.1 的 CHN 边界。香港、澳门、台湾在原始数据中是独立图形。
    private static let mainlandChinaBoundary: CGPath = {
        let path = CGMutablePath()
        guard let url = Bundle.main.url(forResource: "mainland-china-boundary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rings = try? JSONDecoder().decode([[[Double]]].self, from: data) else {
            return path
        }

        for ring in rings {
            path.addLines(between: ring.map { CGPoint(x: $0[0], y: $0[1]) })
            path.closeSubpath()
        }
        return path
    }()
    #endif

    static func appleMapCoordinate(from coordinate: CLLocationCoordinate2D, sourceSystem: AppWLocCoordinateSystem) -> CLLocationCoordinate2D {
        switch sourceSystem {
        case .apple:
            return coordinate
        case .gcj02:
            return coordinate
        case .bd09:
            return bd09ToGCJ02(coordinate)
        case .wgs84:
            return wgs84ToGCJ02(coordinate)
        }
    }

    /// 将 Apple 地图选点转换为系统定位使用的 WGS-84 坐标。
    static func wlocResponseCoordinate(fromAppleMapCoordinate coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        return gcj02ToWGS84(coordinate)
    }

    /// 仅转换大陆范围内的 WGS-84 坐标。
    static func wgs84ToGCJ02(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isInMainlandChina(coordinate) else {
            return coordinate
        }
        return applyGCJ02Offset(coordinate)
    }

    /// 计算偏移。反解时中间坐标可能跨过边界，仍需要继续计算。
    private static func applyGCJ02Offset(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
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

    /// 先判定地图点所在范围，再反解大陆点的 GCJ-02 偏移。
    static func gcj02ToWGS84(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isInMainlandChina(coordinate) else {
            return coordinate
        }

        var guess = coordinate
        for _ in 0..<4 {
            let converted = applyGCJ02Offset(guess)
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
