//
//  AppWLocUtils.swift
//  WLocApp-iOS
//
//  Copyright (c) 2026 OpenHRTT WLoc contributors.
//  Licensed under the MIT License. See LICENSE in the project root.
//

import Foundation

class AppWLocUtils {
    private static let debugLogQueue = DispatchQueue(label: "com.openhrtt.wloc.debug-log")
    
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

        #if DEBUG
        debugLogQueue.async {
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
        #endif
    }

    static var debugLogURL: URL? {
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppWLocConfig.appGroupIdentifier
        ) {
            return container
                .appendingPathComponent("AppWLoc", isDirectory: true)
                .appendingPathComponent("wloc-debug.log", isDirectory: false)
        }

        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AppWLoc", isDirectory: true)
            .appendingPathComponent("wloc-debug.log", isDirectory: false)
    }
    
}
