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

/// \(AppWLocConfig.displayName) 响应改写器。
///
/// 逻辑对齐原 Go 服务里的 `buildWLocResponse`：把响应中每个 WiFi 设备的
/// location 改成用户锁定坐标，同时保留未知 protobuf 字段，降低破坏上游
/// 私有字段的风险。该类型只处理二进制数据，不依赖旧定位流程。
struct AppWLocMutator {
    private static let responsePrefix = Data([0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00])

    static func mutateResponseBody(_ body: Data, using state: AppWLocLockState) throws -> Data {
        guard !body.isEmpty else {
            throw AppWLocMutatorError.emptyBody
        }
        let envelope = try parseResponseEnvelope(body)
        var message = try App_AppWLoc(serializedData: envelope.protobuf)
        guard !message.wifiDevices.isEmpty else {
            throw AppWLocMutatorError.noWifiDevices
        }

        let location = configuredLocation(from: state)
        for index in message.wifiDevices.indices {
            message.wifiDevices[index].location = location
        }

        // 对齐 Go 版本：清掉请求侧/统计侧字段，让响应只保留被改写后的 WiFi 结果。
        message.numCellResults = nil
        message.numWifiResults = nil
        message.deviceType = nil

        let protobuf = try message.serializedData()
        return envelope.wrap(protobuf: protobuf)
    }

    static func mutateRequestARPC(_ raw: Data, using state: AppWLocLockState) throws -> Data {
        guard state.enabled else {
            throw AppWLocMutatorError.invalidCoordinate
        }
        var arpc = try AppWLocARPC(data: raw)
        var message = try App_AppWLoc(serializedData: arpc.payload)
        let location = configuredLocation(from: state)
        for index in message.wifiDevices.indices {
            message.wifiDevices[index].location = location
        }
        message.numCellResults = nil
        message.numWifiResults = nil
        message.deviceType = nil
        arpc.payload = try message.serializedData()
        return try arpc.serialize()
    }

    private static func configuredLocation(from state: AppWLocLockState) -> App_Location {
        var location = App_Location()
        let horizontalAccuracy = state.horizontalAccuracy
        location.latitude = coordinateInt(state.latitude)
        location.longitude = coordinateInt(state.longitude)
        location.horizontalAccuracy = horizontalAccuracy
        location.verticalAccuracy = state.verticalAccuracy
        location.altitude = Int64(state.altitude.rounded())
        location.unknownValue4 = 3
        location.motionActivityType = 63
        location.motionActivityConfidence = 467
//        // 主动填满可选定位字段，减少上游对缺失字段的异常判断。
//        location.speed = 0
//        location.course = 0
//        location.timestamp = currentUnixTimestamp()
//        location.unknownContext = 0
//        location.provider = 0
//        location.floor = 0
//        location.unknown15 = 0
//        location.motionVehicleConnectedStateChanged = 0
//        location.motionVehicleConnected = 0
//        location.rawMotionActivity = 0
//        location.motionActivity = 0
//        location.dominantMotionActivity = 0
//        location.courseAccuracy = 0
//        location.speedAccuracy = 0
//        location.modeIndicator = 0
//        location.horzUncSemiMaj = horizontalAccuracy
//        location.horzUncSemiMin = horizontalAccuracy
//        location.horzUncSemiMajAz = 0
//        location.satelliteReport = 0
//        location.isFromLocationController = 1
//        location.pipelineDiagnosticReport = 0
//        location.baroCalibrationIndication = 0
//        location.processingMetadata = 0
        return location
    }

    private static func coordinateInt(_ value: Double) -> Int64 {
        Int64((value * 100_000_000).rounded())
    }

    private static func currentUnixTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970.rounded())
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
