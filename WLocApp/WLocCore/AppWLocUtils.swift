//
//  AppWLocUtils.swift
//  WLocApp-iOS
//
//  Copyright (c) 2026 OpenHRTT WLoc contributors.
//  Licensed under the MIT License. See LICENSE in the project root.
//

import Foundation

class AppWLocUtils {
    
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
    
}
