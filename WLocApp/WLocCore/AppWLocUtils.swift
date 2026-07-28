//
//  AppWLocUtils.swift
//  WLocApp-iOS
//
//  Copyright (c) 2026 WLoc8.com contributors.
//  Licensed under the MIT License. See LICENSE in the project root.
//

import Foundation

class AppWLocUtils {
    private static let debugLogQueue = DispatchQueue(label: "com.wloc8.debug-log")
    
    static func mainThread(_ block:(()-> Void)?){
        if Thread.isMainThread {
            block?()
            return
        }
        
        DispatchQueue.main.async(execute: {
            block?()
        })
    }
    
    static func mainThreadAfter(_ after:TimeInterval, _ block:(()-> Void)?){
        if Thread.isMainThread {
            if after > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(after * 1000)), execute: {
                    block?()
                })
            } else {
                block?()
            }
            return
        }
        
        if after > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(after * 1000)), execute: {
                block?()
            })
        } else {
            DispatchQueue.main.async(execute: {
                block?()
            })
        }
    }

    static func debugLog(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        NSLog("%@", message)

        debugLogQueue.async {
            appendDebugLogLine(line)
        }
    }

    static func readDebugLog(completion: @escaping (String) -> Void) {
        debugLogQueue.async {
            let content: String
            if let url = debugLogURL,
               let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8),
               !text.isEmpty {
                content = text
            } else {
                content = "暂无日志。"
            }
            DispatchQueue.main.async {
                completion(content)
            }
        }
    }

    static func clearDebugLog(completion: (() -> Void)? = nil) {
        debugLogQueue.async {
            guard let url = debugLogURL else {
                DispatchQueue.main.async {
                    completion?()
                }
                return
            }

            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data().write(to: url, options: .atomic)
                appendDebugLogLine("[\(Date())] 调试日志已清空，开始重新记录。\n")
            } catch {
                NSLog("%@ debug log clear failed: %@", AppWLocConfig.displayName, error.localizedDescription)
            }

            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    private static func appendDebugLogLine(_ line: String) {
        guard let url = debugLogURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard let data = line.data(using: .utf8) else { return }
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            handle.write(data)
        } catch {
            NSLog("%@ debug log write failed: %@", AppWLocConfig.displayName, error.localizedDescription)
        }
    }

    static var debugLogURL: URL? {
        #if os(iOS)
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppWLocConfig.appGroupIdentifier
        ) {
            return container
                .appendingPathComponent("AppWLoc", isDirectory: true)
                .appendingPathComponent("wloc-debug.log", isDirectory: false)
        }
        #endif

        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AppWLoc", isDirectory: true)
            .appendingPathComponent("wloc-debug.log", isDirectory: false)
    }
    
}
