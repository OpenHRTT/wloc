import Foundation
import SwiftProtobuf

// `BSSIDApp.proto` 对应的 SwiftProtobuf 模型。
//
// 当前环境没有 `protoc-gen-swift`，所以这里按 SwiftProtobuf 生成代码的结构手写
// 了 WLoc 改包需要的消息类型。unknownFields 会被保留，避免丢掉当前 proto
// 尚未覆盖的 App 私有字段。

struct AppWLocWifiDevice {
    var bssid: String = ""
    var location: AppWLocLocation? = nil
    var unknownFields = UnknownStorage()

    init() {}
}

struct AppWLocModel {
    var wifiDevices: [AppWLocWifiDevice] = []
    var numCellResults: Int32? = nil
    var numWifiResults: Int32? = nil
    var appBundleID: String? = nil
    var cellTowerResponse: [AppWLocCellTower] = []
    var cellTowerRequest: AppWLocCellTower? = nil
    var deviceType: AppWLocDeviceType? = nil
    var unknownFields = UnknownStorage()

    init() {}
}

struct AppWLocCellTower {
    var mcc: UInt32 = 0
    var mnc: UInt32 = 0
    var cellID: UInt32 = 0
    var tacID: UInt32 = 0
    var location: AppWLocLocation? = nil
    var uarfcn: UInt32? = nil
    var pid: UInt32? = nil
    var unknownFields = UnknownStorage()

    init() {}
}

struct AppWLocDeviceType {
    var operatingSystem: String = ""
    var model: String = ""
    var unknownFields = UnknownStorage()

    init() {}
}

struct AppWLocLocation {
    var latitude: Int64? = nil
    var longitude: Int64? = nil
    var horizontalAccuracy: Int64? = nil
    var unknownValue4: Int64? = nil
    var altitude: Int64? = nil
    var verticalAccuracy: Int64? = nil
    var speed: Int64? = nil
    var course: Int64? = nil
    var timestamp: Int64? = nil
    var unknownContext: Int64? = nil
    var motionActivityType: Int64? = nil
    var motionActivityConfidence: Int64? = nil
    var provider: Int64? = nil
    var floor: Int64? = nil
    var unknown15: Int64? = nil
    var motionVehicleConnectedStateChanged: Int64? = nil
    var motionVehicleConnected: Int64? = nil
    var rawMotionActivity: Int64? = nil
    var motionActivity: Int64? = nil
    var dominantMotionActivity: Int64? = nil
    var courseAccuracy: Int64? = nil
    var speedAccuracy: Int64? = nil
    var modeIndicator: Int64? = nil
    var horzUncSemiMaj: Int64? = nil
    var horzUncSemiMin: Int64? = nil
    var horzUncSemiMajAz: Int64? = nil
    var satelliteReport: Int64? = nil
    var isFromLocationController: Int64? = nil
    var pipelineDiagnosticReport: Int64? = nil
    var baroCalibrationIndication: Int64? = nil
    var processingMetadata: Int64? = nil
    var unknownFields = UnknownStorage()

    init() {}
}

extension AppWLocWifiDevice: Message, _MessageImplementationBase, _ProtoNameProviding {
    static let protoMessageName = "WifiDevice"
    static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
        1: .same(proto: "bssid"),
        2: .same(proto: "location")
    ]

    mutating func decodeMessage<D: Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularStringField(value: &bssid)
            case 2: try decoder.decodeSingularMessageField(value: &location)
            default: break
            }
        }
    }

    func traverse<V: Visitor>(visitor: inout V) throws {
        if !bssid.isEmpty {
            try visitor.visitSingularStringField(value: bssid, fieldNumber: 1)
        }
        if let location {
            try visitor.visitSingularMessageField(value: location, fieldNumber: 2)
        }
        try unknownFields.traverse(visitor: &visitor)
    }

    static func == (lhs: AppWLocWifiDevice, rhs: AppWLocWifiDevice) -> Bool {
        lhs.bssid == rhs.bssid &&
        lhs.location == rhs.location &&
        lhs.unknownFields == rhs.unknownFields
    }
}

extension AppWLocModel: Message, _MessageImplementationBase, _ProtoNameProviding {
    static let protoMessageName = "AppleWLoc"
    static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
        2: .standard(proto: "wifi_devices"),
        3: .standard(proto: "num_cell_results"),
        4: .standard(proto: "num_wifi_results"),
        5: .standard(proto: "app_bundle_id"),
        22: .standard(proto: "cell_tower_response"),
        25: .standard(proto: "cell_tower_request"),
        33: .standard(proto: "device_type")
    ]

    mutating func decodeMessage<D: Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 2: try decoder.decodeRepeatedMessageField(value: &wifiDevices)
            case 3: try decoder.decodeSingularSInt32Field(value: &numCellResults)
            case 4: try decoder.decodeSingularSInt32Field(value: &numWifiResults)
            case 5: try decoder.decodeSingularStringField(value: &appBundleID)
            case 22: try decoder.decodeRepeatedMessageField(value: &cellTowerResponse)
            case 25: try decoder.decodeSingularMessageField(value: &cellTowerRequest)
            case 33: try decoder.decodeSingularMessageField(value: &deviceType)
            default: break
            }
        }
    }

    func traverse<V: Visitor>(visitor: inout V) throws {
        if !wifiDevices.isEmpty {
            try visitor.visitRepeatedMessageField(value: wifiDevices, fieldNumber: 2)
        }
        if let numCellResults {
            try visitor.visitSingularSInt32Field(value: numCellResults, fieldNumber: 3)
        }
        if let numWifiResults {
            try visitor.visitSingularSInt32Field(value: numWifiResults, fieldNumber: 4)
        }
        if let appBundleID {
            try visitor.visitSingularStringField(value: appBundleID, fieldNumber: 5)
        }
        if !cellTowerResponse.isEmpty {
            try visitor.visitRepeatedMessageField(value: cellTowerResponse, fieldNumber: 22)
        }
        if let cellTowerRequest {
            try visitor.visitSingularMessageField(value: cellTowerRequest, fieldNumber: 25)
        }
        if let deviceType {
            try visitor.visitSingularMessageField(value: deviceType, fieldNumber: 33)
        }
        try unknownFields.traverse(visitor: &visitor)
    }

    static func == (lhs: AppWLocModel, rhs: AppWLocModel) -> Bool {
        lhs.wifiDevices == rhs.wifiDevices &&
        lhs.numCellResults == rhs.numCellResults &&
        lhs.numWifiResults == rhs.numWifiResults &&
        lhs.appBundleID == rhs.appBundleID &&
        lhs.cellTowerResponse == rhs.cellTowerResponse &&
        lhs.cellTowerRequest == rhs.cellTowerRequest &&
        lhs.deviceType == rhs.deviceType &&
        lhs.unknownFields == rhs.unknownFields
    }
}

extension AppWLocCellTower: Message, _MessageImplementationBase, _ProtoNameProviding {
    static let protoMessageName = "CellTower"
    static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
        1: .same(proto: "mcc"),
        2: .same(proto: "mnc"),
        3: .standard(proto: "cell_id"),
        4: .standard(proto: "tac_id"),
        5: .same(proto: "location"),
        6: .same(proto: "uarfcn"),
        7: .same(proto: "pid")
    ]

    mutating func decodeMessage<D: Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularUInt32Field(value: &mcc)
            case 2: try decoder.decodeSingularUInt32Field(value: &mnc)
            case 3: try decoder.decodeSingularUInt32Field(value: &cellID)
            case 4: try decoder.decodeSingularUInt32Field(value: &tacID)
            case 5: try decoder.decodeSingularMessageField(value: &location)
            case 6: try decoder.decodeSingularUInt32Field(value: &uarfcn)
            case 7: try decoder.decodeSingularUInt32Field(value: &pid)
            default: break
            }
        }
    }

    func traverse<V: Visitor>(visitor: inout V) throws {
        if mcc != 0 { try visitor.visitSingularUInt32Field(value: mcc, fieldNumber: 1) }
        if mnc != 0 { try visitor.visitSingularUInt32Field(value: mnc, fieldNumber: 2) }
        if cellID != 0 { try visitor.visitSingularUInt32Field(value: cellID, fieldNumber: 3) }
        if tacID != 0 { try visitor.visitSingularUInt32Field(value: tacID, fieldNumber: 4) }
        if let location { try visitor.visitSingularMessageField(value: location, fieldNumber: 5) }
        if let uarfcn { try visitor.visitSingularUInt32Field(value: uarfcn, fieldNumber: 6) }
        if let pid { try visitor.visitSingularUInt32Field(value: pid, fieldNumber: 7) }
        try unknownFields.traverse(visitor: &visitor)
    }

    static func == (lhs: AppWLocCellTower, rhs: AppWLocCellTower) -> Bool {
        lhs.mcc == rhs.mcc &&
        lhs.mnc == rhs.mnc &&
        lhs.cellID == rhs.cellID &&
        lhs.tacID == rhs.tacID &&
        lhs.location == rhs.location &&
        lhs.uarfcn == rhs.uarfcn &&
        lhs.pid == rhs.pid &&
        lhs.unknownFields == rhs.unknownFields
    }
}

extension AppWLocDeviceType: Message, _MessageImplementationBase, _ProtoNameProviding {
    static let protoMessageName = "DeviceType"
    static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
        1: .standard(proto: "operating_system"),
        2: .same(proto: "model")
    ]

    mutating func decodeMessage<D: Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularStringField(value: &operatingSystem)
            case 2: try decoder.decodeSingularStringField(value: &model)
            default: break
            }
        }
    }

    func traverse<V: Visitor>(visitor: inout V) throws {
        if !operatingSystem.isEmpty {
            try visitor.visitSingularStringField(value: operatingSystem, fieldNumber: 1)
        }
        if !model.isEmpty {
            try visitor.visitSingularStringField(value: model, fieldNumber: 2)
        }
        try unknownFields.traverse(visitor: &visitor)
    }

    static func == (lhs: AppWLocDeviceType, rhs: AppWLocDeviceType) -> Bool {
        lhs.operatingSystem == rhs.operatingSystem &&
        lhs.model == rhs.model &&
        lhs.unknownFields == rhs.unknownFields
    }
}

extension AppWLocLocation: Message, _MessageImplementationBase, _ProtoNameProviding {
    static let protoMessageName = "Location"
    static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
        1: .same(proto: "latitude"),
        2: .same(proto: "longitude"),
        3: .standard(proto: "horizontal_accuracy"),
        4: .standard(proto: "unknown_value4"),
        5: .same(proto: "altitude"),
        6: .standard(proto: "vertical_accuracy"),
        7: .same(proto: "speed"),
        8: .same(proto: "course"),
        9: .same(proto: "timestamp"),
        10: .standard(proto: "unknown_context"),
        11: .standard(proto: "motion_activity_type"),
        12: .standard(proto: "motion_activity_confidence"),
        13: .same(proto: "provider"),
        14: .same(proto: "floor"),
        15: .same(proto: "unknown15"),
        16: .standard(proto: "motion_vehicle_connected_state_changed"),
        17: .standard(proto: "motion_vehicle_connected"),
        18: .standard(proto: "raw_motion_activity"),
        19: .standard(proto: "motion_activity"),
        20: .standard(proto: "dominant_motion_activity"),
        21: .standard(proto: "course_accuracy"),
        22: .standard(proto: "speed_accuracy"),
        23: .standard(proto: "mode_indicator"),
        24: .standard(proto: "horzUncSemiMaj"),
        25: .standard(proto: "horzUncSemiMin"),
        26: .standard(proto: "horzUncSemiMajAz"),
        27: .standard(proto: "satellite_report"),
        28: .standard(proto: "is_from_location_controller"),
        29: .standard(proto: "pipeline_diagnostic_report"),
        30: .standard(proto: "baro_calibration_indication"),
        31: .standard(proto: "processing_metadata")
    ]

    mutating func decodeMessage<D: Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularInt64Field(value: &latitude)
            case 2: try decoder.decodeSingularInt64Field(value: &longitude)
            case 3: try decoder.decodeSingularInt64Field(value: &horizontalAccuracy)
            case 4: try decoder.decodeSingularInt64Field(value: &unknownValue4)
            case 5: try decoder.decodeSingularInt64Field(value: &altitude)
            case 6: try decoder.decodeSingularInt64Field(value: &verticalAccuracy)
            case 7: try decoder.decodeSingularInt64Field(value: &speed)
            case 8: try decoder.decodeSingularInt64Field(value: &course)
            case 9: try decoder.decodeSingularInt64Field(value: &timestamp)
            case 10: try decoder.decodeSingularInt64Field(value: &unknownContext)
            case 11: try decoder.decodeSingularInt64Field(value: &motionActivityType)
            case 12: try decoder.decodeSingularInt64Field(value: &motionActivityConfidence)
            case 13: try decoder.decodeSingularInt64Field(value: &provider)
            case 14: try decoder.decodeSingularInt64Field(value: &floor)
            case 15: try decoder.decodeSingularInt64Field(value: &unknown15)
            case 16: try decoder.decodeSingularInt64Field(value: &motionVehicleConnectedStateChanged)
            case 17: try decoder.decodeSingularInt64Field(value: &motionVehicleConnected)
            case 18: try decoder.decodeSingularInt64Field(value: &rawMotionActivity)
            case 19: try decoder.decodeSingularInt64Field(value: &motionActivity)
            case 20: try decoder.decodeSingularInt64Field(value: &dominantMotionActivity)
            case 21: try decoder.decodeSingularInt64Field(value: &courseAccuracy)
            case 22: try decoder.decodeSingularInt64Field(value: &speedAccuracy)
            case 23: try decoder.decodeSingularInt64Field(value: &modeIndicator)
            case 24: try decoder.decodeSingularInt64Field(value: &horzUncSemiMaj)
            case 25: try decoder.decodeSingularInt64Field(value: &horzUncSemiMin)
            case 26: try decoder.decodeSingularInt64Field(value: &horzUncSemiMajAz)
            case 27: try decoder.decodeSingularInt64Field(value: &satelliteReport)
            case 28: try decoder.decodeSingularInt64Field(value: &isFromLocationController)
            case 29: try decoder.decodeSingularInt64Field(value: &pipelineDiagnosticReport)
            case 30: try decoder.decodeSingularInt64Field(value: &baroCalibrationIndication)
            case 31: try decoder.decodeSingularInt64Field(value: &processingMetadata)
            default: break
            }
        }
    }

    func traverse<V: Visitor>(visitor: inout V) throws {
        try visit(latitude, &visitor, 1)
        try visit(longitude, &visitor, 2)
        try visit(horizontalAccuracy, &visitor, 3)
        try visit(unknownValue4, &visitor, 4)
        try visit(altitude, &visitor, 5)
        try visit(verticalAccuracy, &visitor, 6)
        try visit(speed, &visitor, 7)
        try visit(course, &visitor, 8)
        try visit(timestamp, &visitor, 9)
        try visit(unknownContext, &visitor, 10)
        try visit(motionActivityType, &visitor, 11)
        try visit(motionActivityConfidence, &visitor, 12)
        try visit(provider, &visitor, 13)
        try visit(floor, &visitor, 14)
        try visit(unknown15, &visitor, 15)
        try visit(motionVehicleConnectedStateChanged, &visitor, 16)
        try visit(motionVehicleConnected, &visitor, 17)
        try visit(rawMotionActivity, &visitor, 18)
        try visit(motionActivity, &visitor, 19)
        try visit(dominantMotionActivity, &visitor, 20)
        try visit(courseAccuracy, &visitor, 21)
        try visit(speedAccuracy, &visitor, 22)
        try visit(modeIndicator, &visitor, 23)
        try visit(horzUncSemiMaj, &visitor, 24)
        try visit(horzUncSemiMin, &visitor, 25)
        try visit(horzUncSemiMajAz, &visitor, 26)
        try visit(satelliteReport, &visitor, 27)
        try visit(isFromLocationController, &visitor, 28)
        try visit(pipelineDiagnosticReport, &visitor, 29)
        try visit(baroCalibrationIndication, &visitor, 30)
        try visit(processingMetadata, &visitor, 31)
        try unknownFields.traverse(visitor: &visitor)
    }

    static func == (lhs: AppWLocLocation, rhs: AppWLocLocation) -> Bool {
        lhs.latitude == rhs.latitude &&
        lhs.longitude == rhs.longitude &&
        lhs.horizontalAccuracy == rhs.horizontalAccuracy &&
        lhs.unknownValue4 == rhs.unknownValue4 &&
        lhs.altitude == rhs.altitude &&
        lhs.verticalAccuracy == rhs.verticalAccuracy &&
        lhs.motionActivityType == rhs.motionActivityType &&
        lhs.motionActivityConfidence == rhs.motionActivityConfidence &&
        lhs.unknownFields == rhs.unknownFields
    }

    private func visit<V: Visitor>(_ value: Int64?, _ visitor: inout V, _ fieldNumber: Int) throws {
        if let value {
            try visitor.visitSingularInt64Field(value: value, fieldNumber: fieldNumber)
        }
    }
}
