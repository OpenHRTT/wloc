import Foundation

enum AppWLocARPCError: Error, LocalizedError {
    case truncated
    case invalidLength
    case invalidString
    case invalidVersion

    var errorDescription: String? {
        switch self {
        case .truncated:
            return "ARPC 数据不完整"
        case .invalidLength:
            return "ARPC 长度字段无效"
        case .invalidString:
            return "ARPC 字符串字段无效"
        case .invalidVersion:
            return "ARPC 版本字段无效"
        }
    }
}

/// App WLoc 请求使用的 ARPC 外层封包。
///
/// 这是 Go 版本 `lib/arpc.go` 的 Swift 迁移，用来在需要时解析客户端原始 WLoc
/// 查询。当前响应改写主链路不强依赖它，但保留该能力便于后续做请求侧校验。
struct AppWLocARPC {
    var version: String
    var locale: String
    var appIdentifier: String
    var osVersion: String
    var functionID: UInt32
    var payload: Data

    init(
        version: String,
        locale: String,
        appIdentifier: String,
        osVersion: String,
        functionID: UInt32,
        payload: Data
    ) {
        self.version = version
        self.locale = locale
        self.appIdentifier = appIdentifier
        self.osVersion = osVersion
        self.functionID = functionID
        self.payload = payload
    }

    init(data: Data) throws {
        var reader = AppWLocDataReader(data: data)
        let version = try reader.readUInt16()
        let locale = try reader.readPascalString()
        let appIdentifier = try reader.readPascalString()
        let osVersion = try reader.readPascalString()
        let functionID = try reader.readUInt32()
        let payloadLength = Int(try reader.readUInt32())
        guard payloadLength <= reader.remainingCount else {
            throw AppWLocARPCError.invalidLength
        }
        let payload = try reader.readData(count: payloadLength)

        self.version = String(version)
        self.locale = locale
        self.appIdentifier = appIdentifier
        self.osVersion = osVersion
        self.functionID = functionID
        self.payload = payload
    }

    func serialize() throws -> Data {
        guard let versionNumber = UInt16(version) else {
            throw AppWLocARPCError.invalidVersion
        }
        var data = Data()
        data.appendUInt16BE(versionNumber)
        try data.appendPascalString(locale)
        try data.appendPascalString(appIdentifier)
        try data.appendPascalString(osVersion)
        data.appendUInt32BE(functionID)
        data.appendUInt32BE(UInt32(payload.count))
        data.append(payload)
        return data
    }
}

private struct AppWLocDataReader {
    let data: Data
    var offset: Int = 0

    var remainingCount: Int {
        data.count - offset
    }

    mutating func readUInt16() throws -> UInt16 {
        let bytes = try readBytes(count: 2)
        return (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try readBytes(count: 4)
        return (UInt32(bytes[0]) << 24) |
            (UInt32(bytes[1]) << 16) |
            (UInt32(bytes[2]) << 8) |
            UInt32(bytes[3])
    }

    mutating func readPascalString() throws -> String {
        let length = Int(try readUInt16())
        let bytes = try readData(count: length)
        guard let value = String(data: bytes, encoding: .utf8) else {
            throw AppWLocARPCError.invalidString
        }
        return value
    }

    mutating func readData(count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else {
            throw AppWLocARPCError.truncated
        }
        let range = offset..<(offset + count)
        offset += count
        return data.subdata(in: range)
    }

    private mutating func readBytes(count: Int) throws -> [UInt8] {
        Array(try readData(count: count))
    }
}

private extension Data {
    mutating func appendUInt16BE(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    mutating func appendPascalString(_ value: String) throws {
        let bytes = Data(value.utf8)
        guard bytes.count <= Int(UInt16.max) else {
            throw AppWLocARPCError.invalidLength
        }
        appendUInt16BE(UInt16(bytes.count))
        append(bytes)
    }
}
