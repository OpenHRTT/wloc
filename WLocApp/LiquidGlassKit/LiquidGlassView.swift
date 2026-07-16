//
//  LiquidGlassView.swift
//  LiquidGlass
//
//  Created by Alexey Demin on 2025-12-05.
//

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import simd
import MetalKit
import MetalPerformanceShaders

#if canImport(UIKit)
typealias LiquidGlassPlatformColor = UIColor
typealias LiquidGlassPlatformView = UIView
#elseif canImport(AppKit)
typealias LiquidGlassPlatformColor = NSColor
typealias LiquidGlassPlatformView = NSView
#endif

struct LiquidGlass {

    /// Maximum number of rectangles supported in the shader.
    static let maxRectangles = 16

    /// Mirror the Metal 'ShaderUniforms' exactly for buffer binding.
    struct ShaderUniforms {
        var resolution: SIMD2<Float> = .zero        // Frame size in pixels.
        var contentsScale: Float = .zero            // Scale factor. 2 for Retina; 3 for Super Retina.
        var touchPoint: SIMD2<Float> = .zero        // Touch position in points (upper-left origin).
        var shapeMergeSmoothness: Float = .zero     // Specifies the distance between elements at which they begin to merge (spacing).
        var cornerRadius: Float = .zero             // Base rounding (e.g., 24 for subtle chamfer). Circle if half the side.
        var cornerRoundnessExponent: Float = 2      // 1 = diamond; 2 = circle; 4 = squircle.
        var materialTint: SIMD4<Float> = .zero      // RGBA; e.g., subtle cyan (0.2, 0.8, 1.0, 1.0)
        var glassThickness: Float                   // Fake parallax depth (e.g., 8-16 px)
        var refractiveIndex: Float                  // 1.45-1.52 for borosilicate glass feel
        var dispersionStrength: Float               // 0.0-0.02; prismatic color split on edges
        var fresnelDistanceRange: Float             // px falloff from silhouette (e.g., 32)
        var fresnelIntensity: Float                 // 0.0-1.0; rim lighting boost
        var fresnelEdgeSharpness: Float             // Power 1.0=linear, 8.0=crisp
        var glareDistanceRange: Float               // Similar to fresnel, but for specular streaks
        var glareAngleConvergence: Float            // 0.0-π; focuses rays toward light dir
        var glareOppositeSideBias: Float            // >1.0 amplifies back-side highlights
        var glareIntensity: Float                   // 1.0-4.0; bloom-like edge fire
        var glareEdgeSharpness: Float               // Matches fresnel for consistency
        var glareDirectionOffset: Float             // Radians; tilts streak asymmetry
        var rectangleCount: Int32 = .zero           // Number of active rectangles
        var rectangles: (                           // Array of rectangles (x, y, width, height) in points, upper-left origin.
            SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
            SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
            SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
            SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>
        ) = (.zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
             .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero)
    }

    let shaderUniforms: ShaderUniforms
    let backgroundTextureSizeCoefficient: Double
    let backgroundTextureScaleCoefficient: Double
    let backgroundTextureBlurRadius: Double
    var tintColor: LiquidGlassPlatformColor?
    var shadowOverlay: Bool = false

    static func thumb(magnification: Double = 1) -> Self {
        .init(
            shaderUniforms: .init(
                materialTint: .init(x: 0.9, y: 0.95, z: 1.0, w: 0.15), // Near-clear with cool bias.
                glassThickness: 10,
                refractiveIndex: 1.11,
                dispersionStrength: 5,
                fresnelDistanceRange: 70,
                fresnelIntensity: 0,
                fresnelEdgeSharpness: 0,
                glareDistanceRange: 30,
                glareAngleConvergence: 0,
                glareOppositeSideBias: 0,
                glareIntensity: 0.01,
                glareEdgeSharpness: -0.2,
                glareDirectionOffset: .pi * 0.9,
            ),
            backgroundTextureSizeCoefficient: 1 / magnification,
            backgroundTextureScaleCoefficient: magnification,
            backgroundTextureBlurRadius: 0,
            shadowOverlay: true,
        )
    }

    static let lens = Self.init(
        shaderUniforms: .init(
            glassThickness: 6,
            refractiveIndex: 1.1,
            dispersionStrength: 15,
            fresnelDistanceRange: 70,
            fresnelIntensity: 0,
            fresnelEdgeSharpness: 0,
            glareDistanceRange: 30,
            glareAngleConvergence: 0.1,
            glareOppositeSideBias: 1,
            glareIntensity: 0.1,
            glareEdgeSharpness: -0.1,
            glareDirectionOffset: -.pi / 4,
        ),
        backgroundTextureSizeCoefficient: 1.1,
        backgroundTextureScaleCoefficient: 0.8,
        backgroundTextureBlurRadius: 0,
        shadowOverlay: true,
    )

    static let regular = Self.init(
        shaderUniforms: .init(
            glassThickness: 10,
            refractiveIndex: 1.5,
            dispersionStrength: 5,
            fresnelDistanceRange: 70,
            fresnelIntensity: 0,
            fresnelEdgeSharpness: 0,
            glareDistanceRange: 30,
            glareAngleConvergence: 0.1,
            glareOppositeSideBias: 1,
            glareIntensity: 0.1,
            glareEdgeSharpness: -0.15,
            glareDirectionOffset: -.pi / 4,
        ),
        backgroundTextureSizeCoefficient: 1,
        backgroundTextureScaleCoefficient: 0.2,
        backgroundTextureBlurRadius: 0.3,
        tintColor: LiquidGlassPlatformColor(red: 0.9023525731, green: 0.9509486998, blue: 1, alpha: 0.8002892298),
    )
}

#if canImport(UIKit)
final class BackdropView: UIView {

    override class var layerClass: AnyClass {
        // CABackdropLayer is a private API that captures content behind the layer
        NSClassFromString("CABackdropLayer") ?? CALayer.self
    }

    init() {
        super.init(frame: .zero)

        // Configure backdrop view
        isUserInteractionEnabled = false
        layer.setValue(false, forKey: "layerUsesCoreImageFilters")

        // Configure backdrop layer properties (private API)
        layer.setValue(true, forKey: "windowServerAware")
        layer.setValue(UUID().uuidString, forKey: "groupName")
//        layer.setValue(1.0, forKey: "scale")  // Full resolution for capture
//        layer.setValue(0.0, forKey: "bleedAmount")
//        layer.setValue(false, forKey: "allowsHitTesting")
//        layer.setValue(true, forKey: "captureOnly")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#elseif canImport(AppKit)
final class BackdropView: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        let backdropLayer = (NSClassFromString("CABackdropLayer") as? CALayer.Type)?.init() ?? CALayer()
        layer = backdropLayer
        layer?.setValue(false, forKey: "layerUsesCoreImageFilters")
        layer?.setValue(true, forKey: "windowServerAware")
        layer?.setValue(UUID().uuidString, forKey: "groupName")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif

final class ShadowView: LiquidGlassPlatformView {

    #if canImport(UIKit)
    init() {
        super.init(frame: .zero)

        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.compositingFilter = "multiplyBlendMode"
    }
    #elseif canImport(AppKit)
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.compositingFilter = "multiplyBlendMode"
    }
    
    convenience init() {
        self.init(frame: .zero)
    }
    #endif
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    #if canImport(UIKit)
    override func layoutSubviews() {
        super.layoutSubviews()
        updateShadowPath()
    }
    #elseif canImport(AppKit)
    override func layout() {
        super.layout()
        updateShadowPath()
    }
    #endif

    private func updateShadowPath() {
        let shadowRadius = 3.5
        let path = CGPath(
            roundedRect: bounds.insetBy(dx: -1, dy: -shadowRadius / 2),
            cornerWidth: bounds.height / 2,
            cornerHeight: bounds.height / 2,
            transform: nil
        )
        #if canImport(UIKit)
        layer.shadowPath = path
        layer.shadowRadius = shadowRadius
        layer.shadowOpacity = 0.2
        layer.shadowOffset = .init(width: 0, height: shadowRadius + 2)
        #elseif canImport(AppKit)
        layer?.shadowPath = path
        layer?.shadowRadius = shadowRadius
        layer?.shadowOpacity = 0.2
        layer?.shadowOffset = .init(width: 0, height: shadowRadius + 2)
        #endif
    }
}

final class LiquidGlassRenderer {
    static let shared = LiquidGlassRenderer()

    let device: MTLDevice
    let pipelineState: MTLRenderPipelineState

    private init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal not supported")
        }
        self.device = device

        guard let library = device.makeDefaultLibrary() else {
            fatalError("LiquidGlassKit Metal library not found")
        }

        let vertexFunction = library.makeFunction(name: "fullscreenQuad")!
        let fragmentFunction = library.makeFunction(name: "liquidGlassEffect")!

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm  // Match MTKView

        self.pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
}

final class LiquidGlassView: MTKView {

    let liquidGlass: LiquidGlass

    var commandQueue: MTLCommandQueue!
    var uniformsBuffer: MTLBuffer!
    var zeroCopyBridge: ZeroCopyBridge!

    // Background texture for the shader
    private var backgroundTexture: MTLTexture?

    /// Whether to automatically capture superview on each frame. 
    /// Set to false for manual control via `captureBackground()`.
    var autoCapture: Bool = true

    var touchPoint: CGPoint? = nil

    var frames: [CGRect] = []

    // Shadow overlay subview
    private weak var shadowView: ShadowView?

    // Backdrop capture view (stays in superview, contains only CABackdropLayer)
    private let backdropView = BackdropView()

    init(_ liquidGlass: LiquidGlass) {
        self.liquidGlass = liquidGlass

        super.init(frame: .zero, device: LiquidGlassRenderer.shared.device)
        
        if liquidGlass.shadowOverlay {
            let shadowView = ShadowView()
            addSubview(shadowView)
            self.shadowView = shadowView
        }
        setupMetal()
//        layer.shouldRasterize = true
//        preferredFramesPerSecond = 30
//        clipsToBounds = true
//        autoResizeDrawable = false
//        contentMode = .center
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private var backingLayer: CALayer? {
        #if canImport(UIKit)
        layer
        #elseif canImport(AppKit)
        layer
        #endif
    }

    private var backingScale: CGFloat {
        #if canImport(UIKit)
        layer.contentsScale
        #elseif canImport(AppKit)
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        #endif
    }

    func setupMetal() {
        guard let device else { return }

        commandQueue = device.makeCommandQueue()!

        // Uniforms buffer (update per frame)
        uniformsBuffer = device.makeBuffer(length: MemoryLayout<LiquidGlass.ShaderUniforms>.stride, options: [])!

        zeroCopyBridge = .init(device: device)

        // Make view transparent so we can see the effect
        #if canImport(UIKit)
        isOpaque = false
        layer.isOpaque = false
        #elseif canImport(AppKit)
        wantsLayer = true
        layer?.isOpaque = false
        #endif

        isPaused = false // Enable to manually control drawing via `draw(_:)`
//        enableSetNeedsDisplay = true  // Allow setNeedsDisplay() to trigger draws
    }

    // MARK: - Background Capture

    func captureBackground() {
        #if canImport(UIKit)
        captureBackdrop()
        #elseif canImport(AppKit)
        captureRootView()
        #endif
    }

    /// Captures the background content via root View using (presentation) Layer render.
    /// High CPU usage.
    func captureRootView() {
        guard let rootView = findRootView(),
              let currentLayer = backingLayer?.presentation() ?? backingLayer else { return }

        let sizeCoefficient = liquidGlass.backgroundTextureSizeCoefficient
        let scaleCoefficient = backingScale * liquidGlass.backgroundTextureScaleCoefficient

        // Determine our on-screen rect in the root view coordinate space.
        // IMPORTANT: During `UIView.animate`, the view's *model* layer jumps to the final frame
        // immediately; the in-flight position lives in the *presentation* layer. Using the
        // presentation layer makes the captured background track the view while it animates.
        #if canImport(UIKit)
        let rootLayer = rootView.layer
        #elseif canImport(AppKit)
        guard let rootLayer = rootView.layer else { return }
        #endif
        let frameInRoot = currentLayer.convert(currentLayer.bounds, to: rootLayer)

        // Expand capture area around the MTKView center (in root view coordinates)
        let captureSize = CGSize(width: frameInRoot.width * sizeCoefficient,
                                 height: frameInRoot.height * sizeCoefficient)
        let captureRectInRoot = CGRect(x: frameInRoot.midX - captureSize.width / 2,
                                       y: frameInRoot.midY - captureSize.height / 2,
                                       width: captureSize.width,
                                       height: captureSize.height)

        backgroundTexture = zeroCopyBridge.render { context in
            // Hide self temporarily for clean background capture
            let wasHidden = isHidden
            isHidden = true
            defer { isHidden = wasHidden }

            // Transform to render the portion of root view under our capture rect:
            context.scaleBy(x: scaleCoefficient, y: scaleCoefficient)
            context.translateBy(x: -captureRectInRoot.origin.x, y: -captureRectInRoot.origin.y)
//            context.interpolationQuality = .none

            let rootViewLayer = rootLayer.presentation() ?? rootLayer
            rootViewLayer.render(in: context)
        }

        blurTexture()
    }

    /// Captures the background content via CABackdropLayer using drawHierarchy.
    /// Noticeable rendering delay.
    func captureBackdrop() {
        #if canImport(UIKit)
        guard let superview else { return }
        
        let sizeCoefficient = liquidGlass.backgroundTextureSizeCoefficient
        let scaleCoefficient = backingScale * liquidGlass.backgroundTextureScaleCoefficient

        // Calculate frame using presentation layer for smooth animation tracking
        guard let currentLayer = backingLayer?.presentation() ?? backingLayer else { return }
        let superviewLayer = superview.layer
        let frameInSuperview = currentLayer.convert(currentLayer.bounds, to: superviewLayer)
        let captureSize = CGSize(width: frameInSuperview.width * sizeCoefficient,
                                 height: frameInSuperview.height * sizeCoefficient)
        let captureOrigin = CGPoint(x: frameInSuperview.midX - captureSize.width / 2,
                                    y: frameInSuperview.midY - captureSize.height / 2)
        
        // Position backdrop view and layer
        backdropView.frame = CGRect(origin: captureOrigin, size: captureSize)

        // Ensure backdrop view is in superview (below us)
        if backdropView.superview !== superview {
            superview.insertSubview(backdropView, belowSubview: self)
        }
        
        // Capture using drawHierarchy (gets windowserver-composited content)
        backgroundTexture = zeroCopyBridge.render { context in
            context.scaleBy(x: scaleCoefficient, y: scaleCoefficient)

            UIGraphicsPushContext(context)
            backdropView.drawHierarchy(in: backdropView.bounds, afterScreenUpdates: false)
            UIGraphicsPopContext()
        }

        blurTexture()
        #elseif canImport(AppKit)
        captureRootView()
        #endif
    }

    func blurTexture() {
        guard liquidGlass.backgroundTextureBlurRadius > 0,
              let device,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              var backgroundTexture else { return }
        guard #available(iOS 9.0, macOS 10.13, *) else { return }

        // Apply GPU-accelerated Gaussian blur via MPS
        // Scale blur radius to pixels
        let sigma = Float(liquidGlass.backgroundTextureBlurRadius * backingScale)
        let blur = MPSImageGaussianBlur(device: device, sigma: sigma)
        blur.edgeMode = MPSImageEdgeMode.clamp

        let fallbackCopyAllocator: MPSCopyAllocator? = nil
        blur.encode(commandBuffer: commandBuffer, inPlaceTexture: &backgroundTexture, fallbackCopyAllocator: fallbackCopyAllocator)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    func updateUniforms() {
        var uniforms = liquidGlass.shaderUniforms
        let scaleFactor = backingScale

        uniforms.resolution = .init(x: Float(bounds.width * scaleFactor),
                                    y: Float(bounds.height * scaleFactor))
        uniforms.contentsScale = Float(scaleFactor)

        uniforms.shapeMergeSmoothness = 0.2

        // Assign rectangles from frames array, or use bounds if empty
        let effectiveFrames = frames.isEmpty ? [bounds] : frames
        uniforms.rectangleCount = Int32(min(effectiveFrames.count, LiquidGlass.maxRectangles))

        // Convert CGRect frames to SIMD4<Float> (x, y, width, height)
        var rects: [SIMD4<Float>] = []
        for i in 0..<LiquidGlass.maxRectangles {
            if i < effectiveFrames.count {
                let frame = effectiveFrames[i]
                rects.append(SIMD4<Float>(
                    Float(frame.origin.x),
                    Float(frame.origin.y),
                    Float(frame.width),
                    Float(frame.height)
                ))
            } else {
                rects.append(.zero)
            }
        }
        uniforms.rectangles = (
            rects[0], rects[1], rects[2], rects[3],
            rects[4], rects[5], rects[6], rects[7],
            rects[8], rects[9], rects[10], rects[11],
            rects[12], rects[13], rects[14], rects[15]
        )

        if let touchPoint = touchPoint {
            uniforms.touchPoint = .init(x: Float(touchPoint.x), y: Float(touchPoint.y))
        }

//        uniforms.cornerRoundnessExponent = (layer.cornerCurve == .continuous) ? 4 : 2
        uniforms.cornerRadius = Float(backingLayer?.cornerRadius ?? 0)

        if let tintColor = liquidGlass.tintColor {
            uniforms.materialTint = tintColor.toSimdFloat4()
        }

        uniformsBuffer.contents().assumingMemoryBound(to: LiquidGlass.ShaderUniforms.self).pointee = uniforms

//        setNeedsDisplay()
//        draw(bounds)
    }

    #if canImport(UIKit)
    override func layoutSubviews() {
        super.layoutSubviews()
        layoutLiquidGlass()
    }
    #elseif canImport(AppKit)
    override func layout() {
        super.layout()
        layoutLiquidGlass()
    }
    #endif

    private func layoutLiquidGlass() {
        updateUniforms()

        let scale = backingScale * liquidGlass.backgroundTextureSizeCoefficient * liquidGlass.backgroundTextureScaleCoefficient
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        zeroCopyBridge.setupBuffer(width: width, height: height)

        shadowView?.frame = bounds
    }

    override func draw(_ rect: CGRect) {
        // Auto-capture background from superview if enabled
        if autoCapture {
            captureBackground()
        }
        
        guard let drawable = currentDrawable,
              let renderPassDesc = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else { return }

        encoder.setRenderPipelineState(LiquidGlassRenderer.shared.pipelineState)
        encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        
        if let texture = backgroundTexture {
            encoder.setFragmentTexture(texture, index: 0)
        }

        // Draw fullscreen quad (vertices generated in vertex shader)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

#if canImport(UIKit)
extension UIColor {
    func toSimdFloat4() -> SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return .init(x: Float(r), y: Float(g), z: Float(b), w: Float(a))
    }
}
#elseif canImport(AppKit)
extension NSColor {
    func toSimdFloat4() -> SIMD4<Float> {
        let color = usingColorSpace(.deviceRGB) ?? self
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return .init(x: Float(r), y: Float(g), z: Float(b), w: Float(a))
    }
}
#endif

// Helpers: Lerp for damping, UIColor to Half4
//private func lerp(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ t: Float) -> SIMD2<Float> {
//    return a * (1 - t) + b * t
//}

#if canImport(UIKit)
extension UIView {
    /// Finds the root view in the view hierarchy.
    func findRootView() -> UIView? {
        var current: UIView? = superview
        while let parent = current?.superview {
            current = parent
        }
        return current
    }
}
#elseif canImport(AppKit)
extension NSView {
    /// Finds the root view in the view hierarchy.
    func findRootView() -> NSView? {
        var current: NSView? = superview
        while let parent = current?.superview {
            current = parent
        }
        return current
    }
}
#endif
