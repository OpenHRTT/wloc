import Darwin
import Foundation
import IOKit

private struct AppWLocSystemLocationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 修改 macOS 本机定位服务的模拟偏好，重启定位服务后由系统发布坐标。
final class AppWLocSystemLocation {
    private typealias Preferences = [String: Any]

    private struct PreferenceFile {
        let url: URL
        let owner: uid_t
        let group: gid_t
        let permissions: mode_t
    }

    private struct Original: Codable {
        let existed: Bool
        let values: Data
        let keys: [String]?
    }

    private static let basicKeys = ["LocationServicesEnabled", "AllowSimulatedLocations", "SimulatedLocationLatitude",
                                    "SimulatedLocationLongitude", "SimulatedLocationAccuracy", "SimulatedLocationType"]
    private static let keys = basicKeys + ["SimulatedLocationAltitude", "SimulatedLocationAltitudeAccuracy"]
    private let backupDirectory = URL(fileURLWithPath: "/private/var/db/com.hrtt.applocmac.system-location", isDirectory: true)
    private var backupURL: URL { backupDirectory.appendingPathComponent("original.plist") }

    /// 检查是否存在需要还原的系统模拟配置。
    func hasBackup() throws -> Bool {
        try loadBackup() != nil
    }

    /// 首次锁定时记录原值，更新坐标时保留这份备份。写入或刷新失败时回到操作前的设置。
    func lock(latitude: Double, longitude: Double, altitude: Double? = nil, horizontalAccuracy: Double = 5, verticalAccuracy: Double? = nil) throws {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw AppWLocSystemLocationError(message: "无效的模拟定位坐标。")
        }
        guard horizontalAccuracy.isFinite, horizontalAccuracy >= 0, altitude?.isFinite ?? true,
              verticalAccuracy.map({ $0.isFinite && $0 >= 0 }) ?? true else {
            throw AppWLocSystemLocationError(message: "无效的虚拟定位参数。")
        }
        let files = try preferenceFiles()
        let previous = try files.map(snapshot)
        let original = try loadBackup()
        try prepareBackup(original, current: previous)
        var values: Preferences = [
            "LocationServicesEnabled": true,
            "AllowSimulatedLocations": true,
            "SimulatedLocationLatitude": latitude,
            "SimulatedLocationLongitude": longitude,
            "SimulatedLocationAccuracy": horizontalAccuracy,
            "SimulatedLocationType": 1
        ]
        values["SimulatedLocationAltitude"] = altitude
        values["SimulatedLocationAltitudeAccuracy"] = verticalAccuracy
        do {
            for file in files { try write(values, keys: Self.keys, to: file) }
            try refreshLocationService(owner: files[0].owner)
        } catch {
            do {
                try restore(previous, files: files)
                if original == nil { try FileManager.default.removeItem(at: backupURL) }
            } catch let rollbackError {
                throw AppWLocSystemLocationError(message: "修改失败，定位备份已保留，请重试还原。\n\(rollbackError.localizedDescription)")
            }
            throw error
        }
    }

    /// 在两个偏好文件里精确恢复本次使用的键，其他系统偏好继续保留。
    func restore() throws {
        guard let backup = try loadBackup() else { return }
        let files = try preferenceFiles()
        try restore(backup, files: files)
        try FileManager.default.removeItem(at: backupURL)
    }

    /// 从本机 UUID 选中唯一的 ByHost 文件，避免写入其他主机残留的偏好。
    private func preferenceFiles() throws -> [PreferenceFile] {
        let platform = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard platform != 0 else { throw AppWLocSystemLocationError(message: "无法识别本机的定位配置。") }
        defer { IOObjectRelease(platform) }
        guard let value = IORegistryEntryCreateCFProperty(platform, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0),
              let uuid = value.takeRetainedValue() as? String, let host = UUID(uuidString: uuid),
              let account = getpwnam("_locationd") else {
            throw AppWLocSystemLocationError(message: "无法识别本机的定位配置。")
        }
        let owner = account.pointee.pw_uid
        let group = account.pointee.pw_gid
        let byHost = URL(fileURLWithPath: "/private/var/db/locationd/Library/Preferences/ByHost", isDirectory: true)
        let settingsName = "com.apple.locationd.\(host.uuidString).plist"
        let entries = try FileManager.default.contentsOfDirectory(at: byHost, includingPropertiesForKeys: nil)
        let hostURL = entries.first { $0.lastPathComponent.caseInsensitiveCompare(settingsName) == .orderedSame }
            ?? byHost.appendingPathComponent(settingsName)
        let managed = URL(fileURLWithPath: "/Library/Managed Preferences", isDirectory: true)
        if mkdir(managed.path, 0o755) != 0, errno != EEXIST { throw posixError() }
        try verifyDirectory(managed, owner: 0)
        return [
            PreferenceFile(url: hostURL, owner: owner, group: group, permissions: 0o600),
            PreferenceFile(url: managed.appendingPathComponent("com.apple.locationd.plist"), owner: 0, group: 0, permissions: 0o644)
        ]
    }

    /// 只读取系统账号拥有的常规文件，用属性列表保留各个原始值的类型。
    private func snapshot(_ file: PreferenceFile) throws -> Original {
        let current = try read(file)
        let values = current.values.filter { Self.keys.contains($0.key) }
        return try makeSnapshot(existed: current.info != nil, values: values)
    }

    /// 保存受本功能管理的偏好键和原值，区分原来不存在的键与备份时尚未管理的键。
    private func makeSnapshot(existed: Bool, values: Preferences) throws -> Original {
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        return Original(existed: existed, values: data, keys: Self.keys)
    }

    /// 已有定位锁定时只补存新增加的键，原有备份仍保留首次锁定前的配置。
    private func prepareBackup(_ original: [Original]?, current: [Original]) throws {
        guard let original else {
            try saveBackup(current)
            return
        }
        guard original.count == current.count else { throw AppWLocSystemLocationError(message: "定位备份不完整。") }
        guard original.contains(where: { $0.keys != Self.keys }) else { return }
        let expanded = try zip(original, current).map { old, now in
            var values = try snapshotValues(old)
            let captured = old.keys ?? Self.basicKeys
            for (key, value) in try snapshotValues(now) where !captured.contains(key) { values[key] = value }
            return try makeSnapshot(existed: old.existed, values: values)
        }
        try saveBackup(expanded)
    }

    /// 读取备份里的属性列表，损坏时保留备份供排查。
    private func snapshotValues(_ original: Original) throws -> Preferences {
        guard let values = try PropertyListSerialization.propertyList(from: original.values, options: [], format: nil) as? Preferences else {
            throw AppWLocSystemLocationError(message: "定位备份不可读。")
        }
        return values
    }

    /// 读取现有设置，拒绝符号链接和用户拥有的文件。
    private func read(_ file: PreferenceFile) throws -> (info: stat?, values: Preferences) {
        var info = stat()
        if lstat(file.url.path, &info) != 0 {
            if errno == ENOENT { return (nil, [:]) }
            throw posixError()
        }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == 0 || info.st_uid == file.owner,
              let values = try PropertyListSerialization.propertyList(from: Data(contentsOf: file.url), options: [], format: nil) as? Preferences else {
            throw AppWLocSystemLocationError(message: "定位偏好文件不可用：\(file.url.lastPathComponent)")
        }
        return (info, values)
    }

    /// 合并本功能使用的键并回读。原本没有的空文件在还原时删除。
    private func write(_ values: Preferences, keys: [String], to file: PreferenceFile, removeIfEmpty: Bool = false) throws {
        let current = try read(file)
        if file.owner != 0 {
            try updateHostPreferences(values, keys: keys, previous: current.values, owner: file.owner)
        } else {
            var merged = current.values.filter { !keys.contains($0.key) }
            merged.merge(values) { _, new in new }
            if removeIfEmpty, merged.isEmpty {
                if current.info != nil { try FileManager.default.removeItem(at: file.url) }
            } else {
                try PropertyListSerialization.data(fromPropertyList: merged, format: .binary, options: 0)
                    .write(to: file.url, options: .atomic)
                let group = current.info?.st_gid ?? file.group
                let permissions = current.info.map { $0.st_mode & 0o777 } ?? file.permissions
                guard chown(file.url.path, 0, group) == 0, chmod(file.url.path, permissions) == 0 else {
                    throw posixError()
                }
            }
        }
        let readback = try read(file).values
        guard keys.allSatisfy({ key in
            let expected = values[key] as? NSObject
            let actual = readback[key] as? NSObject
            if expected == actual { return true }
            guard let expected = expected as? NSNumber, let actual = actual as? NSNumber,
                  ["f", "d"].contains(String(cString: expected.objCType)) else { return false }
            return abs(expected.doubleValue - actual.doubleValue) <= 0.00001
        }) else { throw AppWLocSystemLocationError(message: "定位偏好写入未通过回读校验。") }
    }

    /// 通过系统偏好工具在 `_locationd` 的主机域写入，使用该账号自身的偏好缓存和访问权限。
    private func updateHostPreferences(_ values: Preferences, keys: [String], previous: Preferences, owner: uid_t) throws {
        let arguments = try keys.compactMap { key -> [String]? in
            let domain = "com.apple.locationd"
            guard let value = values[key] else {
                return previous[key] == nil ? nil : ["delete", domain, key]
            }
            if let number = value as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    return ["write", domain, key, "-bool", number.boolValue ? "true" : "false"]
                }
                let type = ["f", "d"].contains(String(cString: number.objCType)) ? "-float" : "-int"
                return ["write", domain, key, type, number.stringValue]
            }
            if let string = value as? String { return ["write", domain, key, "-string", string] }
            throw AppWLocSystemLocationError(message: "定位偏好包含无法还原的类型。")
        }
        for change in arguments {
            let command = ["asuser", String(owner), "/usr/bin/sudo", "-n", "-H", "-u", "_locationd",
                           "/usr/bin/defaults", "-currentHost"] + change
            let process = Process()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = command
            process.standardError = errors
            try process.run()
            let details = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw AppWLocSystemLocationError(message: "系统账号写入定位失败。\n\(String(decoding: details, as: UTF8.self))")
            }
        }
    }

    /// 还原磁盘值后刷新服务，确保运行中的定位服务也重新读回原值。
    private func restore(_ originals: [Original], files: [PreferenceFile]) throws {
        guard originals.count == files.count else { throw AppWLocSystemLocationError(message: "定位备份不完整。") }
        for (original, file) in zip(originals, files) {
            let keys = (original.keys ?? Self.basicKeys).filter { Self.keys.contains($0) }
            let values = try snapshotValues(original).filter { keys.contains($0.key) }
            try write(values, keys: keys, to: file, removeIfEmpty: !original.existed)
        }
        try refreshLocationService(owner: files[0].owner)
    }

    /// 首次修改前保存原始位置字段，普通用户无法读写备份目录。
    private func saveBackup(_ originals: [Original]) throws {
        if mkdir(backupDirectory.path, 0o700) != 0, errno != EEXIST { throw posixError() }
        try verifyDirectory(backupDirectory, owner: 0, permissions: 0o700)
        try PropertyListEncoder().encode(originals).write(to: backupURL, options: .atomic)
    }

    /// 仅在确实没有备份时返回空状态，损坏的备份保留给后续还原。
    private func loadBackup() throws -> [Original]? {
        var info = stat()
        if lstat(backupURL.path, &info) != 0 {
            if errno == ENOENT { return nil }
            throw posixError()
        }
        try verifyDirectory(backupDirectory, owner: 0, permissions: 0o700)
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == 0 else {
            throw AppWLocSystemLocationError(message: "定位备份文件权限异常。")
        }
        return try PropertyListDecoder().decode([Original].self, from: Data(contentsOf: backupURL))
    }

    /// 校验写入目录的属主和类型，避免 root 沿符号链接写到其他路径。
    private func verifyDirectory(_ url: URL, owner: uid_t, permissions: mode_t? = nil) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == owner, permissions.map({ info.st_mode & 0o777 == $0 }) ?? true else {
            throw AppWLocSystemLocationError(message: "定位偏好目录权限异常：\(url.path)")
        }
    }

    /// 刷新托管偏好和定位账号的缓存，再让系统重启 locationd 并等待新进程。
    private func refreshLocationService(owner: uid_t) throws {
        let cache = try processIDs(named: "cfprefsd", owner: 0) + processIDs(named: "cfprefsd", owner: owner)
        for pid in cache where processPath(pid) == "/usr/sbin/cfprefsd" {
            if kill(pid, SIGTERM) == -1, errno != ESRCH { throw posixError() }
        }
        guard let previous = try locationPID(owner: owner) else {
            throw AppWLocSystemLocationError(message: "系统定位服务当前未运行。")
        }
        guard kill(previous, SIGTERM) == 0 else { throw posixError() }
        for _ in 0..<40 {
            Thread.sleep(forTimeInterval: 0.125)
            if let next = try locationPID(owner: owner), next != previous { return }
        }
        throw AppWLocSystemLocationError(message: "定位服务未在预期时间内重新启动。")
    }

    /// 用固定进程名和归属账号查询 PID，并核对 Apple 定位服务的路径。
    private func locationPID(owner: uid_t) throws -> pid_t? {
        try processIDs(named: "locationd", owner: owner).first { processPath($0) == "/usr/libexec/locationd" }
    }

    /// 退出码 1 仅表示当前没有该账号下的同名进程。
    private func processIDs(named name: String, owner: uid_t) throws -> [pid_t] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-U", String(owner), "-x", name]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus <= 1 else {
            throw AppWLocSystemLocationError(message: "无法查询系统定位进程。")
        }
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isWhitespace).compactMap { pid_t($0) }
    }

    /// 在发送信号前核对真实执行文件，避免误操作同名程序。
    private func processPath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard pid > 1, proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// 保留系统错误号，方便区分 SIP 拒绝和文件读写失败。
    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
