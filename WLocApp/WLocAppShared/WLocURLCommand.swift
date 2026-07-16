import CoreLocation
import Foundation

enum WLocURLCommand {
    case location(AppWLocPlace)
}

enum WLocURLCommandError: Error, LocalizedError {
    case unsupportedScheme
    case emptyPayload
    case invalidJSON
    case unsupportedType(String)
    case missingLocationData
    case invalidCoordinate

    var errorDescription: String? {
        switch self {
        case .unsupportedScheme:
            return "链接协议不是 wlocapp"
        case .emptyPayload:
            return "链接内容为空"
        case .invalidJSON:
            return "链接内容不是有效 JSON"
        case .unsupportedType(let type):
            return "暂不支持的链接类型：\(type)"
        case .missingLocationData:
            return "链接中缺少经纬度"
        case .invalidCoordinate:
            return "链接中的经纬度无效"
        }
    }
}

enum WLocURLCommandParser {
    static func parse(_ url: URL) throws -> WLocURLCommand {
        guard url.scheme?.lowercased() == "wlocapp" else {
            throw WLocURLCommandError.unsupportedScheme
        }

        let payload = try payloadString(from: url)
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            throw WLocURLCommandError.invalidJSON
        }

        let type = (dictionary["type"] as? String)?.lowercased() ?? ""
        guard type == "location" else {
            throw WLocURLCommandError.unsupportedType(type.isEmpty ? "未知" : type)
        }

        guard let locationData = dictionary["data"] as? [String: Any] else {
            throw WLocURLCommandError.missingLocationData
        }

        let sourceCoordinate = try coordinate(from: locationData)
        let system = coordinateSystem(from: locationData)
        let appleCoordinate = AppWLocCoordinateTool.appleMapCoordinate(
            from: sourceCoordinate,
            sourceSystem: system
        )
        guard CLLocationCoordinate2DIsValid(appleCoordinate) else {
            throw WLocURLCommandError.invalidCoordinate
        }

        let name = stringValue(from: locationData, keys: ["name", "title"]) ?? "外部导入位置"
        let detail = stringValue(from: locationData, keys: ["detail", "address"]) ?? "来自 wlocapp 链接"
        return .location(AppWLocPlace(
            name: name,
            detail: detail,
            latitude: appleCoordinate.latitude,
            longitude: appleCoordinate.longitude
        ))
    }

    private static func payloadString(from url: URL) throws -> String {
        let absolute = url.absoluteString
        let schemePrefix = "wlocapp://"
        guard absolute.lowercased().hasPrefix(schemePrefix) else {
            throw WLocURLCommandError.unsupportedScheme
        }

        var rawPayload = String(absolute.dropFirst(schemePrefix.count))
        if rawPayload.hasPrefix("?"),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryPayload = components.queryItems?.first(where: { $0.name == "payload" })?.value {
            rawPayload = queryPayload
        }

        while rawPayload.hasPrefix("/") {
            rawPayload.removeFirst()
        }

        guard let decoded = rawPayload.removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !decoded.isEmpty else {
            throw WLocURLCommandError.emptyPayload
        }
        return decoded
    }

    private static func coordinate(from data: [String: Any]) throws -> CLLocationCoordinate2D {
        guard let latitude = doubleValue(from: data, keys: ["latitude", "lat"]),
              let longitude = doubleValue(from: data, keys: ["longitude", "lng", "lon"]) else {
            throw WLocURLCommandError.missingLocationData
        }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            throw WLocURLCommandError.invalidCoordinate
        }
        return coordinate
    }

    private static func coordinateSystem(from data: [String: Any]) -> AppWLocCoordinateSystem {
        let value = stringValue(from: data, keys: ["coordinateSystem", "coordSystem", "coordType", "datum"])?
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")

        switch value {
        case "gcj02", "gcj":
            return .gcj02
        case "bd09", "bd":
            return .bd09
        case "apple", "mapkit":
            return .apple
        default:
            return .wgs84
        }
    }

    private static func doubleValue(from data: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let number = data[key] as? NSNumber {
                return number.doubleValue
            }
            if let string = data[key] as? String,
               let value = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return value
            }
        }
        return nil
    }

    private static func stringValue(from data: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let string = data[key] as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }
}
