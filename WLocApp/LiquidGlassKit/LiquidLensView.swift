//
//  LiquidLensView.swift
//  LiquidGlass
//
//  Created by Alexey Demin on 2025-12-19.
//

import UIKit
import MetalKit

/// A custom implementation of the private _UILiquidLensView used in UITabBar.
/// Provides a resting state with a semi-transparent white pill that morphs
/// into a LiquidGlassView when lifted.
public final class LiquidLensView: UIView, AnyLiquidLensView {

    // MARK: - Acceleration Constants
    
    /// Time window for calculating average acceleration (in seconds).
    private let accelerationWindowDuration: TimeInterval = 0.3

    /// Coefficient to convert acceleration to scale transform.
    private let accelerationScaleCoefficient: CGFloat = 0.00005
    
    /// Maximum scale deviation from 1.0 (clamped for visual stability).
    private let maxScaleDeviation: CGFloat = 0.3
    
    // MARK: - Position Tracking
    
    private var positionHistory: [(position: CGPoint, timestamp: TimeInterval)] = []
    private var displayLink: CADisplayLink?
    
    // MARK: - Private Stored Views (weak references)
    
    private weak var liftedContainerView: UIView?
    private weak var liftedContentView: UIView?
    private weak var overridePunchoutView: UIView?
    
    // MARK: - Private Properties
    
    /// Whether the view is currently in lifted state.
    private var isLifted = false
    
    /// The liquid glass content mode.
    private var liftedContentMode: Int = 0
    
    /// The liquid glass style.
    private var style: Int = 0
    
    /// Whether the view warps content below it.
    private var warpsContentBelow: Bool = false
    
    // MARK: - Private Views
    
    /// The resting background view - semi-transparent white pill shown in resting state.
    private let restingPillView = UIView()
    
    /// The liquid glass view shown when lifted.
    private let liquidGlassView = LiquidGlassView(.lens)
    
    // MARK: - Protocol Properties
    
    public var restingBackgroundColor: UIColor? {
        get { restingPillView.backgroundColor }
        set { restingPillView.backgroundColor = newValue }
    }
    
    // MARK: - Initialization
    
    convenience public init() {
        self.init(restingBackground: nil)
    }
    
    public init(restingBackground backgroundView: UIView?) {
        super.init(frame: .zero)
        commonInit()
        if let backgroundView = backgroundView {
            restingPillView.addSubview(backgroundView)
        }
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        clipsToBounds = false
        
        // Setup resting pill view - semi-transparent white
        restingPillView.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        restingPillView.isUserInteractionEnabled = false
        addSubview(restingPillView)
        
        // Setup liquid glass view - initially hidden
        liquidGlassView.alpha = 0
        liquidGlassView.isUserInteractionEnabled = false
        // Not added to view hierarchy initially - only shown when lifted
    }
    
    // MARK: - Layout
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        // Update resting pill to fill bounds with pill shape
        restingPillView.frame = bounds
        restingPillView.layer.cornerRadius = min(bounds.width, bounds.height) / 2
        
        // Update liquid glass view to same bounds
//        liquidGlassView.frame = bounds
//        liquidGlassView.layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }
    
    // MARK: - Protocol Methods
    
    public func setLiftedContainerView(_ containerView: UIView?) {
        liftedContainerView = containerView
    }
    
    public func setLiftedContentView(_ contentView: UIView?) {
        liftedContentView = contentView
    }
    
    public func setOverridePunchoutView(_ punchoutView: UIView?) {
        overridePunchoutView = punchoutView
    }
    
    public func setLifted(_ lifted: Bool, animated: Bool, alongsideAnimations: (() -> Void)?, completion: ((Bool) -> Void)?) {
        guard isLifted != lifted else {
            completion?(true)
            return
        }
        
        isLifted = lifted
        
        if lifted {
            liftUp(animated: animated, alongsideAnimations: alongsideAnimations, completion: completion)
        } else {
            liftDown(animated: animated, alongsideAnimations: alongsideAnimations, completion: completion)
        }
    }
    
    public func setLiftedContentMode(_ contentMode: Int) {
        self.liftedContentMode = contentMode
    }
    
    public func setStyle(_ style: Int) {
        self.style = style
    }
    
    public func setWarpsContentBelow(_ warpsContentBelow: Bool) {
        self.warpsContentBelow = warpsContentBelow
    }
    
    // MARK: - Private Lift Animation
    
    /// Morphs from resting pill to liquid glass view.
    private func liftUp(animated: Bool, alongsideAnimations: (() -> Void)?, completion: ((Bool) -> Void)?) {
        // Prepare liquid glass view at same position
        liquidGlassView.frame = bounds
        liquidGlassView.layer.cornerRadius = restingPillView.layer.cornerRadius
        liquidGlassView.alpha = 0
        addSubview(liquidGlassView)
        
        // Start position tracking for acceleration-based squash/stretch
        startPositionTracking()
        
        let animations = {
            // Fade out resting pill
            self.restingPillView.alpha = 0

            // Fade in liquid glass
            self.liquidGlassView.alpha = 1
            
            alongsideAnimations?()
        }
        
        let animationCompletion: (Bool) -> Void = { finished in
            // Clean up resting pill state
            completion?(finished)
        }
        
        if animated {
            UIView.animate(
                withDuration: 0.4,
                delay: 0,
                usingSpringWithDamping: 0.7,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: animations,
                completion: animationCompletion
            )
        } else {
            animations()
            animationCompletion(true)
        }
    }
    
    /// Morphs from liquid glass view back to resting pill.
    private func liftDown(animated: Bool, alongsideAnimations: (() -> Void)?, completion: ((Bool) -> Void)?) {
        // Stop position tracking
        stopPositionTracking()
        
        // Prepare resting pill for fade in
        restingPillView.alpha = 0
        
        let animations = {
            // Fade in resting pill
            self.restingPillView.alpha = 1
            
            // Fade out liquid glass
            self.liquidGlassView.alpha = 0
            
            alongsideAnimations?()
        }
        
        let animationCompletion: (Bool) -> Void = { finished in
            guard finished else {
                completion?(finished)
                return
            }
            // Clean up liquid glass view
            self.liquidGlassView.removeFromSuperview()
            self.liquidGlassView.alpha = 1
            completion?(finished)
        }
        
        if animated {
            UIView.animate(
                withDuration: 0.5,
                delay: 0,
                usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: animations,
                completion: animationCompletion
            )
        } else {
            animations()
            animationCompletion(true)
        }
    }
    
    // MARK: - Position Tracking & Acceleration
    
    private func startPositionTracking() {
        positionHistory.removeAll()
        displayLink = CADisplayLink(target: self, selector: #selector(updatePositionTracking))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private func stopPositionTracking() {
        displayLink?.invalidate()
        displayLink = nil
        positionHistory.removeAll()
        // Reset liquidGlassView to original bounds
        liquidGlassView.frame = bounds
    }
    
    @objc private func updatePositionTracking() {
        let currentTime = CACurrentMediaTime()
        let currentPosition = layer.position
        
        // Add current position to history
        positionHistory.append((position: currentPosition, timestamp: currentTime))
        
        // Remove old entries outside the time window
        let cutoffTime = currentTime - accelerationWindowDuration
        positionHistory.removeAll { $0.timestamp < cutoffTime }
        
        // Calculate average acceleration and apply size change
        let acceleration = calculateAverageAcceleration()
//        print(acceleration)
        applyAccelerationSize(acceleration)
    }
    
    /// Calculates the average acceleration over the position history.
    /// Returns a combined value where positive = accelerating right/up, negative = accelerating left/down.
    private func calculateAverageAcceleration() -> CGFloat {
        guard positionHistory.count >= 3 else { return 0 }
        
        // Calculate velocities between consecutive position samples
        var velocities: [(velocity: CGPoint, timestamp: TimeInterval)] = []
        for i in 1..<positionHistory.count {
            let prev = positionHistory[i - 1]
            let curr = positionHistory[i]
            let dt = curr.timestamp - prev.timestamp
            guard dt > 0 else { continue }
            
            let velocity = CGPoint(
                x: (curr.position.x - prev.position.x) / dt,
                y: (curr.position.y - prev.position.y) / dt
            )
            let midTime = (prev.timestamp + curr.timestamp) / 2
            velocities.append((velocity: velocity, timestamp: midTime))
        }
        
        guard velocities.count >= 2 else { return 0 }
        
        // Calculate accelerations between consecutive velocity samples
        var totalAccelerationX: CGFloat = 0
        var totalAccelerationY: CGFloat = 0
        var count: CGFloat = 0
        
        for i in 1..<velocities.count {
            let prev = velocities[i - 1]
            let curr = velocities[i]
            let dt = curr.timestamp - prev.timestamp
            guard dt > 0 else { continue }
            
            totalAccelerationX += (curr.velocity.x - prev.velocity.x) / dt
            totalAccelerationY += (curr.velocity.y - prev.velocity.y) / dt
            count += 1
        }
        
        guard count > 0 else { return 0 }
        
        let avgAccelerationX = totalAccelerationX / count
        let avgAccelerationY = totalAccelerationY / count
        
        // Combine accelerations:
        // - Positive X acceleration (right) or negative Y acceleration (up in UIKit coords) → stretch X
        // - Negative X acceleration (left) or positive Y acceleration (down) → squash X
        // In UIKit, Y increases downward, so upward movement = negative Y velocity,
        // and accelerating upward = negative Y acceleration.
        // We want upward acceleration to have the same effect as rightward acceleration,
        // so we subtract Y acceleration from X acceleration.
        return avgAccelerationX - avgAccelerationY
    }
    
    /// Applies squash/stretch size change to liquidGlassView based on acceleration.
    private func applyAccelerationSize(_ acceleration: CGFloat) {
        let scaleFactor = acceleration * accelerationScaleCoefficient
        
        // Clamp to reasonable range for visual stability
        let clampedScale = max(-maxScaleDeviation, min(maxScaleDeviation, scaleFactor))
        
        // Apply opposite scale to width and height to create squash/stretch effect
        // Positive acceleration → stretch width, squash height
        // Negative acceleration → squash width, stretch height
        let scaleX = 1 + clampedScale
        let scaleY = 1 - clampedScale
        
        let newWidth = bounds.width * scaleX
        let newHeight = bounds.height * scaleY
        
        // Center the new frame within bounds
        liquidGlassView.frame = CGRect(
            x: (bounds.width - newWidth) / 2,
            y: (bounds.height - newHeight) / 2,
            width: newWidth,
            height: newHeight
        )
    }
}

@objc public protocol AnyLiquidLensView {
    init()
    init(restingBackground backgroundView: UIView?)
    var restingBackgroundColor: UIColor? { get set }
    func setLiftedContainerView(_ containerView: UIView?)
    func setLiftedContentView(_ contentView: UIView?)
    func setOverridePunchoutView(_ punchoutView: UIView?)
    func setLifted(_ lifted: Bool, animated: Bool, alongsideAnimations: (() -> Void)?, completion: ((Bool) -> Void)?)
    func setLiftedContentMode(_ contentMode: Int)
    func setStyle(_ style: Int)
    func setWarpsContentBelow(_ warpsContentBelow: Bool)
}

public typealias UILiquidLensView = UIView & AnyLiquidLensView
