//
//  ZeroCopyBridge.swift
//  LiquidGlass
//
//  Created by Alexey Demin on 2025-12-22.
//

import CoreVideo

class ZeroCopyBridge {
    let device: MTLDevice
    var textureCache: CVMetalTextureCache?
    var pixelBuffer: CVPixelBuffer?
    var cvTexture: CVMetalTexture?

    init(device: MTLDevice) {
        self.device = device
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        if status != kCVReturnSuccess {
            print("Failed to create texture cache: \(status)")
        }
    }

    func setupBuffer(width: Int, height: Int) {
        let attrs = [
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] // Enables zero-copy via IOSurface
        ] as CFDictionary

        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs, &pixelBuffer)
        if status != kCVReturnSuccess {
            print("Failed to create pixel buffer: \(status)")
        }

        guard let buffer = pixelBuffer, let cache = textureCache else { return }

        // Create the Metal Texture wrapper for the CVPixelBuffer
        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, buffer, nil, .bgra8Unorm, width, height, 0, &cvTexture)

        self.cvTexture = cvTexture
    }

    func render(actions: (CGContext) -> Void) -> MTLTexture? {
        guard let buffer = pixelBuffer, let cache = textureCache else { return nil }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)

        // Lock for CPU writing
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        defer {
            // Unlock and flush to propagate changes to GPU
            CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
            CVMetalTextureCacheFlush(cache, 0)
        }
        
        let data = CVPixelBufferGetBaseAddress(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        // Create CGContext from shared memory
        guard let context = CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        actions(context)

        // Get MTLTexture from the retained CVMetalTexture
        return cvTexture.flatMap { CVMetalTextureGetTexture($0) }
    }
}
