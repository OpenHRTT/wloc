import Foundation
import SwiftProtobuf

enum AppWLocMutatorError: Error, LocalizedError {
    case emptyBody
    case unsupportedResponseEnvelope
    case invalidProtobufLength
    case noWifiDevices
    case invalidCoordinate

    var errorDescription: String? {
        switch self {
        case .emptyBody:
            return "\(AppWLocConfig.displayName) 响应为空"
        case .unsupportedResponseEnvelope:
            return "\(AppWLocConfig.displayName) 响应头格式无法识别"
        case .invalidProtobufLength:
            return "\(AppWLocConfig.displayName) protobuf 长度无效"
        case .noWifiDevices:
            return "\(AppWLocConfig.displayName) 响应中没有 WiFi 设备"
        case .invalidCoordinate:
            return "目标定位坐标无效"
        }
    }
}

/// 定位响应改写器。
///
/// 逻辑对齐原 Go 服务里的 `buildWLocResponse`：从客户端 WLoc 请求的 ARPC
/// payload 里取 WiFi 设备列表，把每个设备的 location 改成用户锁定坐标，
/// 再包成 Apple WLoc 响应。这样返回体只包含本次请求需要的设备，不会把上游
/// 扫描结果整包带回客户端。
struct AppWLocMutator {
    private static let responsePrefix = Data([0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00])

    static func buildResponseBody(fromRequestBody raw: Data, using state: AppWLocLockState) throws -> Data {
        guard !raw.isEmpty else {
            throw AppWLocMutatorError.emptyBody
        }

        let arpc = try AppWLocARPC(data: raw)
        var message = try AppWLocModel(serializedData: arpc.payload)
        applyLockedLocation(to: &message, using: state)

        let protobuf = try message.serializedData()
        return wrapResponse(protobuf: protobuf)
    }

    static func mutateResponseBody(_ body: Data, using state: AppWLocLockState) throws -> Data {
        guard !body.isEmpty else {
            throw AppWLocMutatorError.emptyBody
        }
        let envelope = try parseResponseEnvelope(body)
        var message = try AppWLocModel(serializedData: envelope.protobuf)
        guard !message.wifiDevices.isEmpty else {
            throw AppWLocMutatorError.noWifiDevices
        }

        applyLockedLocation(to: &message, using: state)

        let protobuf = try message.serializedData()
        return envelope.wrap(protobuf: protobuf)
    }

    static func mutateRequestARPC(_ raw: Data, using state: AppWLocLockState) throws -> Data {
        var arpc = try AppWLocARPC(data: raw)
        var message = try AppWLocModel(serializedData: arpc.payload)
        applyLockedLocation(to: &message, using: state)
        arpc.payload = try message.serializedData()
        return try arpc.serialize()
    }

    private static func applyLockedLocation(to message: inout AppWLocModel, using state: AppWLocLockState) {
        let location = configuredLocation(from: state)
        for index in message.wifiDevices.indices {
            message.wifiDevices[index].location = location
        }

        // 对齐 Go 版本：清掉请求侧/统计侧字段，让响应只保留被改写后的 WiFi 结果。
        message.numCellResults = nil
        message.numWifiResults = nil
        message.deviceType = nil
    }

    private static func configuredLocation(from state: AppWLocLockState) -> AppWLocLocation {
        var location = AppWLocLocation()
        let horizontalAccuracy = state.horizontalAccuracy
        location.latitude = coordinateInt(state.latitude)
        location.longitude = coordinateInt(state.longitude)
        location.horizontalAccuracy = horizontalAccuracy
        location.verticalAccuracy = state.verticalAccuracy
        location.altitude = Int64(state.altitude.rounded())
        location.unknownValue4 = 3
        location.motionActivityType = 63
        location.motionActivityConfidence = 467
        return location
    }

    private static func coordinateInt(_ value: Double) -> Int64 {
        Int64((value * 100_000_000).rounded())
    }

    private static func wrapResponse(protobuf: Data) -> Data {
        var data = Data(responsePrefix)
        data.append(UInt8((protobuf.count >> 8) & 0xff))
        data.append(UInt8(protobuf.count & 0xff))
        data.append(protobuf)
        return data
    }

    private static func parseResponseEnvelope(_ body: Data) throws -> ResponseEnvelope {
        if body.count >= 10, body.prefix(responsePrefix.count) == responsePrefix {
            let lengthOffset = responsePrefix.count
            let declaredLength = (Int(body[lengthOffset]) << 8) | Int(body[lengthOffset + 1])
            let protobufStart = lengthOffset + 2
            guard protobufStart + declaredLength <= body.count else {
                throw AppWLocMutatorError.invalidProtobufLength
            }
            let protobuf = body.subdata(in: protobufStart..<(protobufStart + declaredLength))
            return .prefixed(prefix: responsePrefix, protobuf: protobuf)
        }

        // 便于离线验证：抓包工具有时只保存 protobuf 裸数据，这里也允许直接解析。
        return .rawProtobuf(body)
    }
}

private enum ResponseEnvelope {
    case prefixed(prefix: Data, protobuf: Data)
    case rawProtobuf(Data)

    var protobuf: Data {
        switch self {
        case .prefixed(_, let protobuf):
            return protobuf
        case .rawProtobuf(let protobuf):
            return protobuf
        }
    }

    func wrap(protobuf: Data) -> Data {
        switch self {
        case .prefixed(let prefix, _):
            var data = Data(prefix)
            data.append(UInt8((protobuf.count >> 8) & 0xff))
            data.append(UInt8(protobuf.count & 0xff))
            data.append(protobuf)
            return data
        case .rawProtobuf:
            return protobuf
        }
    }
}
