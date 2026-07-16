//
//  LiquidGlassSwitch.swift
//  LiquidGlass
//
//  Created by Alexey Demin on 2025-12-10.
//

#if canImport(UIKit)
import UIKit
import MetalKit

/// A custom switch control that replicates the iOS 26 Liquid Glass sliding style.
/// Fully compatible with UISwitch interface for drop-in replacement.
open class LiquidGlassSwitch: UIControl {

    // MARK: - Public Properties (UISwitch Interface)
    
    /// A Boolean value that determines the off/on state of the switch.
    open var isOn: Bool = false {
        didSet {
            guard oldValue != isOn else { return }
            
            // Skip visual updates when set programmatically (setOn handles them)
            // or when dragging (drag handling manages position manually)
            if !isUpdatingStateProgrammatically && !isDragging {
                updateTrackColor(animated: false)
                updateThumbPosition(animated: false)
            }
        }
    }
    
    /// The color used to tint the appearance of the switch when it's in the on position.
    open var onTintColor: UIColor? {
        didSet { updateTrackColor(animated: false) }
    }
    
    /// The color used to tint the appearance of the thumb.
    open var thumbTintColor: UIColor? {
        didSet { updateThumbAppearance() }
    }
    
    /// The image displayed when the switch is in the on position (not used in iOS 26 style, kept for compatibility).
    open var onImage: UIImage? {
        didSet { /* No-op for iOS 26 style */ }
    }
    
    /// The image displayed when the switch is in the off position (not used in iOS 26 style, kept for compatibility).
    open var offImage: UIImage? {
        didSet { /* No-op for iOS 26 style */ }
    }

    @available(iOS 14.0, *)
    open var style: UISwitch.Style {
        .sliding
    }

    @available(iOS 14.0, *)
    open var preferredStyle: UISwitch.Style {
        get { .sliding }
        set { }
    }

    // MARK: - Private Views
    
    private let trackView = UIView()
    
    /// The contracted thumb - solid filled pill shown in resting state.
    private let contractedThumbView = UIView()
    
    /// The expanded thumb - transparent pill with border shown during interaction.
    private let expandedThumbView = LiquidGlassView(.thumb(magnification: 0.75))

    // MARK: - Haptic Feedback
    
    private var feedbackGenerator: UIImpactFeedbackGenerator?

    // MARK: - Interaction State
    
    /// Whether the user is currently dragging the thumb.
    private var isDragging = false
    
    /// Time threshold (in seconds) to distinguish between tap and drag.
    private let tapTimeThreshold: TimeInterval = 0.15

    /// Whether the thumb is in expanded state (during interaction).
    private var isThumbExpanded = false
    
    /// The touch location when drag started.
    private var dragStartLocation: CGFloat = 0
    
    /// The thumb center X position when drag started.
    private var dragStartThumbCenterX: CGFloat = 0
    
    /// The time when touch began.
    private var touchBeganTime: TimeInterval = 0
    
    /// Whether a toggle occurred during the current drag gesture.
    private var didToggleDuringDrag = false
    
    /// Whether a toggle was in the on state when drag started.
    private var wasOnWhenDragStarted = false

    /// Flag to prevent redundant visual updates when setOn is handling them.
    private var isUpdatingStateProgrammatically = false

    // MARK: - Layout Constants
    
    private let switchWidth: CGFloat = 63
    private let switchHeight: CGFloat = 28

    private let contractedThumbWidth: CGFloat = 37
    private let contractedThumbHeight: CGFloat = 24

    private let expandedThumbWidth: CGFloat = 58
    private let expandedThumbHeight: CGFloat = 38.333

    private let expandedThumbBorderWidth: CGFloat = 1.5
    private let expandedThumbBorderColor: UIColor = .gray
    
    private let thumbPadding: CGFloat = 2  // (switchHeight - contractedThumbHeight) / 2
    
    // MARK: - Computed Layout Properties
    
    /// The on tint color, defaulting to system green.
    private var resolvedOnTintColor: UIColor {
        onTintColor ?? .systemGreen
    }
    
    /// The off tint color.
    private var resolvedOffTintColor: UIColor {
        UIColor(white: 0.72, alpha: 0.35)
    }
    
    /// The contracted thumb color, defaulting to white.
    private var resolvedContractedThumbColor: UIColor {
        thumbTintColor ?? .white
    }
    
    /// The expanded thumb border color, using thumbTintColor if set.
    private var resolvedExpandedThumbBorderColor: UIColor {
        thumbTintColor ?? expandedThumbBorderColor
    }
    
    /// Minimum X position for thumb center (off position).
    private var minThumbCenterX: CGFloat {
        thumbPadding + contractedThumbWidth / 2
    }
    
    /// Maximum X position for thumb center (on position).
    private var maxThumbCenterX: CGFloat {
        switchWidth - minThumbCenterX
    }
    
    /// Target thumb center X based on current isOn state.
    private var targetThumbCenterX: CGFloat {
        isOn ? maxThumbCenterX : minThumbCenterX
    }
    
    /// Scale transform to morph contracted thumb to expanded size.
    private var contractedToExpandedTransform: CGAffineTransform {
        CGAffineTransform(
            scaleX: expandedThumbWidth / contractedThumbWidth,
            y: expandedThumbHeight / contractedThumbHeight
        )
    }
    
    /// Scale transform to morph expanded thumb to contracted size.
    private var expandedToContractedTransform: CGAffineTransform {
        CGAffineTransform(
            scaleX: contractedThumbWidth / expandedThumbWidth,
            y: contractedThumbHeight / expandedThumbHeight
        )
    }
    
    /// The currently active thumb view.
    private var activeThumbView: UIView {
        isThumbExpanded ? expandedThumbView : contractedThumbView
    }
    
    /// Current thumb center X from active thumb view.
    private var currentThumbCenterX: CGFloat {
        get { activeThumbView.center.x }
        set { activeThumbView.center.x = newValue }
    }
    
    // MARK: - Initialization
    
    public override init(frame: CGRect) {
        super.init(frame: .init(origin: frame.origin, size: .init(width: switchWidth, height: switchHeight)))
        commonInit()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    public convenience init() {
        self.init(frame: .zero)
    }
    
    private func commonInit() {
        clipsToBounds = false
        setupViews()
        setupHaptics()
        setupAccessibility()
        updateTrackColor(animated: false)
        updateThumbPosition(animated: false)
    }
    
    // MARK: - Setup
    
    private func setupViews() {
        // Track view
        trackView.frame = CGRect(x: 0, y: 0, width: switchWidth, height: switchHeight)
        trackView.layer.cornerRadius = switchHeight / 2
        trackView.isUserInteractionEnabled = false
        addSubview(trackView)
        
        // Contracted thumb - solid filled, initially visible
        contractedThumbView.frame = CGRect(x: 0, y: 0, width: contractedThumbWidth, height: contractedThumbHeight)
        contractedThumbView.layer.cornerRadius = contractedThumbHeight / 2
        contractedThumbView.backgroundColor = resolvedContractedThumbColor
        contractedThumbView.isUserInteractionEnabled = false
        addSubview(contractedThumbView)
        
        // Expanded thumb - transparent with border, not in hierarchy initially
        expandedThumbView.frame = CGRect(x: 0, y: 0, width: expandedThumbWidth, height: expandedThumbHeight)
        expandedThumbView.layer.cornerRadius = expandedThumbHeight / 2
//        expandedThumbView.backgroundColor = .clear
//        expandedThumbView.layer.borderWidth = expandedThumbBorderWidth
//        expandedThumbView.layer.borderColor = resolvedExpandedThumbBorderColor.cgColor
        expandedThumbView.isUserInteractionEnabled = false
        // Not added to view hierarchy - only shown during expansion
    }
    
    private func setupHaptics() {
        // Prepare haptic feedback generator
        feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    }
    
    private func setupAccessibility() {
        // Set only default accessibility traits, allowing user customization
        isAccessibilityElement = true
        accessibilityTraits = [.button]
    }
    
    // MARK: - Layout
    
    open override var intrinsicContentSize: CGSize {
        .init(width: switchWidth, height: switchHeight)
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        intrinsicContentSize
    }

    open override var frame: CGRect {
        get { super.frame }
        set { super.frame = .init(origin: newValue.origin, size: intrinsicContentSize) }
    }

    // MARK: - Public Methods (UISwitch Interface)
    
    /// Set the state of the switch to On or Off, optionally animating the transition.
    /// Note: Programmatic changes do not expand the thumb, only user interactions do.
    open func setOn(_ on: Bool, animated: Bool) {
        guard isOn != on else { return }
        
        isUpdatingStateProgrammatically = true
        isOn = on
        isUpdatingStateProgrammatically = false
        
        // Programmatic toggle: just animate position and color, no thumb expansion
        updateTrackColor(animated: animated)
        updateThumbPosition(animated: animated)
    }
    
    // MARK: - Track Appearance
    
    /// Updates the track background color based on current state.
    private func updateTrackColor(animated: Bool) {
        let targetColor = isOn ? resolvedOnTintColor : resolvedOffTintColor
        
        if animated {
            UIView.animate(withDuration: 0.25) {
                self.trackView.backgroundColor = targetColor
            }
        } else {
            trackView.backgroundColor = targetColor
        }
    }
    
    // MARK: - Thumb Position
    
    /// Updates thumb position to match current isOn state.
    private func updateThumbPosition(animated: Bool) {
        let targetCenter = CGPoint(x: targetThumbCenterX, y: switchHeight / 2)
        let thumbView = activeThumbView
        
        if animated {
            UIView.animate(
                withDuration: 0.5,
                delay: 0,
                usingSpringWithDamping: 1,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                thumbView.center = targetCenter
            }
        } else {
            thumbView.center = targetCenter
        }
    }
    
    // MARK: - Thumb State (Contracted/Expanded Morphing)
    
    /// Morphs thumb from contracted to expanded state with animation.
    private func expandThumb(animated: Bool) {
        guard !isThumbExpanded else { return }
        isThumbExpanded = true
        
        // Position expanded thumb at same center, scaled down initially
        expandedThumbView.center = contractedThumbView.center
        expandedThumbView.transform = expandedToContractedTransform
        expandedThumbView.alpha = 0
        addSubview(expandedThumbView)
        
        // Prepare contracted thumb for scale-up animation
        let targetContractedTransform = contractedToExpandedTransform
        
        if animated {
            UIView.animate(
                withDuration: 0.4,
                delay: 0,
                usingSpringWithDamping: 0.6,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                // Contracted scales up and fades out
                self.contractedThumbView.transform = targetContractedTransform
                self.contractedThumbView.alpha = 0
                // Expanded scales to normal and fades in
                self.expandedThumbView.transform = .identity
                self.expandedThumbView.alpha = 1
            } completion: { finished in
                // Only clean up if animation completed and state is still expanded
                guard finished, self.isThumbExpanded else { return }
                self.contractedThumbView.removeFromSuperview()
                self.contractedThumbView.transform = .identity
                self.contractedThumbView.alpha = 1
            }
        } else {
            contractedThumbView.removeFromSuperview()
            contractedThumbView.transform = .identity
            contractedThumbView.alpha = 1
            expandedThumbView.transform = .identity
            expandedThumbView.alpha = 1
        }
    }
    
    /// Morphs thumb from expanded to contracted state with animation.
    private func contractThumb(animated: Bool) {
        guard isThumbExpanded else { return }
        isThumbExpanded = false
        
        // Position contracted thumb at same center, scaled up initially
        contractedThumbView.center = expandedThumbView.center
        contractedThumbView.transform = contractedToExpandedTransform
        contractedThumbView.alpha = 0
        addSubview(contractedThumbView)
        
        // Prepare expanded thumb for scale-down animation
        let targetExpandedTransform = expandedToContractedTransform
        
        if animated {
            UIView.animate(
                withDuration: 0.6,
                delay: 0,
                usingSpringWithDamping: 0.7,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                // Expanded scales down and fades out
                self.expandedThumbView.transform = targetExpandedTransform
                self.expandedThumbView.alpha = 0
                // Contracted scales to normal and fades in
                self.contractedThumbView.transform = .identity
                self.contractedThumbView.alpha = 1
            } completion: { finished in
                // Only clean up if animation completed and state is still contracted
                guard finished, !self.isThumbExpanded else { return }
                self.expandedThumbView.removeFromSuperview()
                self.expandedThumbView.transform = .identity
                self.expandedThumbView.alpha = 1
            }
        } else {
            expandedThumbView.removeFromSuperview()
            expandedThumbView.transform = .identity
            expandedThumbView.alpha = 1
            contractedThumbView.transform = .identity
            contractedThumbView.alpha = 1
        }
    }
    
    /// Updates thumb appearance when thumbTintColor changes.
    private func updateThumbAppearance() {
        contractedThumbView.backgroundColor = resolvedContractedThumbColor
//        expandedThumbView.layer.borderColor = resolvedExpandedThumbBorderColor.cgColor
    }
    
    // MARK: - Toggle Animation
    
    /// Performs the full toggle animation: expand, move, then contract.
    private func performToggleAnimation() {
        // Expand thumb
        expandThumb(animated: true)
        
        // Update track color and position
        updateTrackColor(animated: true)
        updateThumbPosition(animated: true)
        
        // Schedule contraction after expansion completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            // Don't contract if user started dragging
            guard !self.isDragging else { return }
            
            self.contractThumb(animated: true)
        }
    }
    
    // MARK: - Touch Handling
    
    open override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard isEnabled, let touch = touches.first else { return }
        
        // Begin interaction (not a drag yet; will distinguish tap vs drag by time)
        isDragging = false
        wasOnWhenDragStarted = isOn
        didToggleDuringDrag = false
        touchBeganTime = CACurrentMediaTime()
        dragStartLocation = touch.location(in: self).x
        dragStartThumbCenterX = currentThumbCenterX
        
        // Expand thumb immediately
        expandThumb(animated: true)
        
        // Prepare haptic feedback for potential toggle
        feedbackGenerator?.prepare()
    }
    
    open override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard isEnabled, let touch = touches.first else { return }
        
        // Check if enough time has passed to promote to drag
        let touchDuration = CACurrentMediaTime() - touchBeganTime
        if !isDragging && touchDuration >= tapTimeThreshold {
            isDragging = true
        }

        // Process movement regardless of drag state
        let currentX = touch.location(in: self).x
        let translation = currentX - dragStartLocation
        let newCenterX = dragStartThumbCenterX + translation
        
        // Apply position with rubber-band damping at edges
        let clampedCenterX = clampWithRubberBand(newCenterX, min: minThumbCenterX, max: maxThumbCenterX)
        currentThumbCenterX = clampedCenterX
        
        // Check if thumb hit an edge to trigger toggle
        checkForEdgeToggle(at: clampedCenterX)
    }
    
    open override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        
        let touchDuration = CACurrentMediaTime() - touchBeganTime
        
        // Determine if this was a tap (short touch) or a drag (exceeded time threshold)
        if touchDuration < tapTimeThreshold {
            // This was a tap - toggle and animate
            feedbackGenerator?.impactOccurred()
            
            isUpdatingStateProgrammatically = true
            isOn.toggle()
            isUpdatingStateProgrammatically = false
            sendActions(for: .valueChanged)

            performToggleAnimation()
        } else {
            // Time threshold exceeded - finish as a drag (regardless of actual movement)
            finishDrag()
        }
    }
    
    open override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        if isDragging {
            finishDrag()
        } else if isThumbExpanded {
            // If the interaction is cancelled before a drag is recognized, return to resting state.
            contractThumb(animated: true)
        }
    }
    
    // MARK: - Drag Helpers
    
    /// Applies rubber-band effect when dragging past bounds.
    private func clampWithRubberBand(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        if value < minValue {
            return minValue - sqrt(minValue - value)
        } else if value > maxValue {
            return maxValue + sqrt(value - maxValue)
        }
        return value
    }
    
    /// Checks if thumb position should trigger a toggle.
    private func checkForEdgeToggle(at centerX: CGFloat) {
        let edgeThreshold: CGFloat = 5.0
        
        let hitLeftEdge = centerX <= minThumbCenterX + edgeThreshold && isOn
        let hitRightEdge = centerX >= maxThumbCenterX - edgeThreshold && !isOn
        
        if hitLeftEdge || hitRightEdge {
            let newState = hitRightEdge
            if newState != isOn {
                didToggleDuringDrag = true
                feedbackGenerator?.impactOccurred()
                
                // Update state without triggering position animation (we're dragging)
                isUpdatingStateProgrammatically = true
                isOn = newState
                isUpdatingStateProgrammatically = false
                
                updateTrackColor(animated: true)
            }
        }
    }
    
    /// Finishes the drag gesture, animating to final position.
    private func finishDrag() {
        // Toggle if no toggle occurred during drag
        if !didToggleDuringDrag {
            feedbackGenerator?.impactOccurred()
            
            isUpdatingStateProgrammatically = true
            isOn.toggle()
            isUpdatingStateProgrammatically = false
            sendActions(for: .valueChanged)

            updateTrackColor(animated: true)
        }

        // End drag state
        isDragging = false
        if isOn != wasOnWhenDragStarted {
            sendActions(for: .valueChanged)
        }

        // Animate thumb back to its final position first (so it's visibly sliding), then contract.
        self.contractThumb(animated: true)
        updateThumbPosition(animated: true)
    }

    // MARK: - State Handling
    
    open override var isEnabled: Bool {
        didSet {
            alpha = isEnabled ? 1.0 : 0.5
        }
    }
}
#endif

public protocol AnySwitch: UIControl {
    var onTintColor: UIColor? { get set }
    var thumbTintColor: UIColor? { get set }
    var onImage: UIImage? { get set }
    var offImage: UIImage? { get set }
    /// The switch's display style. This property always returns a concrete, resolved style (never UISwitchStyleAutomatic).
    @available(iOS 14.0, *)
    var style: UISwitch.Style { get }
    /// Request a style for the switch. If the style changed, then the switch may resize.
    @available(iOS 14.0, *)
    var preferredStyle: UISwitch.Style { get set }
    var isOn: Bool { get set }
    func setOn(_ on: Bool, animated: Bool)
}

extension UISwitch: AnySwitch { }

extension LiquidGlassSwitch: AnySwitch {
    public static func make(isNative: Bool = true) -> AnySwitch {
        if #available(iOS 26.0, *), isNative {
            UISwitch()
        } else {
            LiquidGlassSwitch()
        }
    }
}
