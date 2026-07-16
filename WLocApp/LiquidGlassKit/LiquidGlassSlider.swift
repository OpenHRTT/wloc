//
//  LiquidGlassSlider.swift
//  LiquidGlass
//
//  Created by Alexey Demin on 2025-12-25.
//

#if canImport(UIKit)
import UIKit
import MetalKit

/// A custom slider control that replicates the iOS 26 Liquid Glass sliding style.
/// Fully compatible with UISlider interface for drop-in replacement.
open class LiquidGlassSlider: UIControl {

    // MARK: - Public Properties (UISlider Interface)
    
    /// The slider's current value.
    open var value: Float = 0 {
        didSet {
            let clampedValue = min(max(value, minimumValue), maximumValue)
            if value != clampedValue {
                value = clampedValue
                return
            }
            guard oldValue != value else { return }
            
            if !isUpdatingValueProgrammatically && !isDragging {
                updateThumbPosition(animated: false)
                updateTrackFill()
            }
            
            if isUpdatingValueProgrammatically, isContinuous || !isDragging {
                sendActions(for: .valueChanged)
            }
        }
    }
    
    /// The minimum value of the slider.
    open var minimumValue: Float = 0 {
        didSet {
            value = min(max(value, minimumValue), maximumValue)
            updateThumbPosition(animated: false)
            updateTrackFill()
        }
    }
    
    /// The maximum value of the slider.
    open var maximumValue: Float = 1 {
        didSet {
            value = min(max(value, minimumValue), maximumValue)
            updateThumbPosition(animated: false)
            updateTrackFill()
        }
    }
    
    /// The image to display at the minimum end of the slider.
    open var minimumValueImage: UIImage? {
        didSet { updateValueImages() }
    }
    
    /// The image to display at the maximum end of the slider.
    open var maximumValueImage: UIImage? {
        didSet { updateValueImages() }
    }
    
    /// A Boolean value indicating whether changes in the slider's value generate continuous update events.
    open var isContinuous: Bool = true
    
    /// The slider's visual style.
    @available(iOS 26.0, *)
    open var sliderStyle: UISlider.Style {
        get { isThumbless ? .thumbless : .default }
        set { isThumbless = (newValue == .thumbless) }
    }
    
    /// Internal storage for slider style (true = thumbless, false = continuous).
    private var isThumbless: Bool = false
    
    /// The color used to tint the portion of the track to the left of the thumb.
    open var minimumTrackTintColor: UIColor? {
        didSet { updateTrackFill() }
    }
    
    /// The color used to tint the portion of the track to the right of the thumb.
    open var maximumTrackTintColor: UIColor? {
        didSet { updateTrackAppearance() }
    }
    
    /// The color used to tint the thumb.
    open var thumbTintColor: UIColor? {
        didSet { updateThumbAppearance() }
    }
    
    // MARK: - Image Properties (kept for API compatibility)
    
    private var thumbImages: [UIControl.State.RawValue: UIImage?] = [:]
    private var minimumTrackImages: [UIControl.State.RawValue: UIImage?] = [:]
    private var maximumTrackImages: [UIControl.State.RawValue: UIImage?] = [:]
    
    // MARK: - Private Views
    
    private let trackView = UIView()
    private let trackFillView = UIView()
    private let minimumValueImageView = UIImageView()
    private let maximumValueImageView = UIImageView()
    
    /// The contracted thumb - solid filled circle shown in resting state.
    private let contractedThumbView = UIView()
    
    /// The expanded thumb - transparent pill with liquid glass effect shown during interaction.
    private let expandedThumbView = LiquidGlassView(.thumb())

    // MARK: - Haptic Feedback
    
    private var lightFeedbackGenerator: UIImpactFeedbackGenerator?
    private var mediumFeedbackGenerator: UIImpactFeedbackGenerator?

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
    
    /// Flag to prevent redundant visual updates when setValue is handling them.
    private var isUpdatingValueProgrammatically = false
    
    /// Whether haptic was triggered at the minimum edge during current drag.
    private var didTriggerMinHaptic = false
    
    /// Whether haptic was triggered at the maximum edge during current drag.
    private var didTriggerMaxHaptic = false
    
    /// Current rubber-band offset (negative = left overshoot, positive = right overshoot).
    private var rubberBandOffset: CGFloat = 0

    // MARK: - Layout Constants
    
    private let sliderHeight: CGFloat = 28
    private let trackHeight: CGFloat = 6
    private let trackVerticalPadding: CGFloat = 12  // (sliderHeight - trackHeight) / 2

    private let contractedThumbWidth: CGFloat = 37
    private let contractedThumbHeight: CGFloat = 24

    private let expandedThumbWidth: CGFloat = 58
    private let expandedThumbHeight: CGFloat = 38.333
    
    private let valueImageSize: CGFloat = 20
    private let valueImagePadding: CGFloat = 8
    
    // MARK: - Computed Layout Properties
    
    /// The minimum track tint color, defaulting to tintColor.
    private var resolvedMinimumTrackTintColor: UIColor {
        minimumTrackTintColor ?? tintColor
    }
    
    /// The maximum track tint color.
    private var resolvedMaximumTrackTintColor: UIColor {
        maximumTrackTintColor ?? UIColor(white: 0.72, alpha: 0.35)
    }
    
    /// The contracted thumb color, defaulting to white.
    private var resolvedContractedThumbColor: UIColor {
        thumbTintColor ?? .white
    }
    
    /// The left edge of the track.
    private var trackMinX: CGFloat {
        let imageOffset = minimumValueImage != nil ? (valueImageSize + valueImagePadding) : 0
        return imageOffset
    }
    
    /// The right edge of the track.
    private var trackMaxX: CGFloat {
        let imageOffset = maximumValueImage != nil ? (valueImageSize + valueImagePadding) : 0
        return bounds.width - imageOffset
    }
    
    /// The usable track width.
    private var trackWidth: CGFloat {
        trackMaxX - trackMinX
    }
    
    /// Minimum X position for thumb center.
    private var minThumbCenterX: CGFloat {
        trackMinX + contractedThumbWidth / 2
    }
    
    /// Maximum X position for thumb center.
    private var maxThumbCenterX: CGFloat {
        trackMaxX - contractedThumbWidth / 2
    }
    
    /// The range of thumb center positions.
    private var thumbCenterRange: CGFloat {
        maxThumbCenterX - minThumbCenterX
    }
    
    /// Current normalized value (0...1).
    private var normalizedValue: CGFloat {
        guard maximumValue > minimumValue else { return 0 }
        return CGFloat((value - minimumValue) / (maximumValue - minimumValue))
    }
    
    /// Target thumb center X based on current value.
    private var targetThumbCenterX: CGFloat {
        minThumbCenterX + thumbCenterRange * normalizedValue
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
        super.init(frame: frame)
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
        updateTrackAppearance()
        updateTrackFill()
        updateThumbPosition(animated: false)
    }
    
    // MARK: - Setup
    
    private func setupViews() {
        // Track view (background)
        trackView.layer.cornerRadius = trackHeight / 2
        trackView.isUserInteractionEnabled = false
        addSubview(trackView)
        
        // Minimum track fill view (colored portion on the left)
        trackFillView.layer.cornerRadius = trackHeight / 2
        trackFillView.isUserInteractionEnabled = false
        addSubview(trackFillView)
        
        // Value image views
        minimumValueImageView.contentMode = .scaleAspectFit
        minimumValueImageView.isUserInteractionEnabled = false
        minimumValueImageView.isHidden = true
        addSubview(minimumValueImageView)
        
        maximumValueImageView.contentMode = .scaleAspectFit
        maximumValueImageView.isUserInteractionEnabled = false
        maximumValueImageView.isHidden = true
        addSubview(maximumValueImageView)
        
        // Contracted thumb - solid filled pill, initially visible
        contractedThumbView.frame = CGRect(x: 0, y: 0, width: contractedThumbWidth, height: contractedThumbHeight)
        contractedThumbView.layer.cornerRadius = contractedThumbHeight / 2
        contractedThumbView.backgroundColor = resolvedContractedThumbColor
        contractedThumbView.layer.shadowOpacity = 0.15
        contractedThumbView.layer.shadowRadius = 5
        contractedThumbView.layer.shadowOffset = .zero
        contractedThumbView.isUserInteractionEnabled = false
        addSubview(contractedThumbView)
        
        // Expanded thumb - transparent with liquid glass effect, not in hierarchy initially
        expandedThumbView.frame = CGRect(x: 0, y: 0, width: expandedThumbWidth, height: expandedThumbHeight)
        expandedThumbView.layer.cornerRadius = expandedThumbHeight / 2
        expandedThumbView.isUserInteractionEnabled = false
        // Not added to view hierarchy - only shown during expansion
    }
    
    private func setupHaptics() {
        lightFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
        mediumFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    }
    
    private func setupAccessibility() {
        isAccessibilityElement = true
        accessibilityTraits = [.adjustable]
    }
    
    // MARK: - Layout
    
    open override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: sliderHeight)
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: sliderHeight)
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        
        // Layout value images
        let centerY = bounds.height / 2
        
        if minimumValueImage != nil {
            minimumValueImageView.frame = CGRect(
                x: 0,
                y: centerY - valueImageSize / 2,
                width: valueImageSize,
                height: valueImageSize
            )
        }
        
        if maximumValueImage != nil {
            maximumValueImageView.frame = CGRect(
                x: bounds.width - valueImageSize,
                y: centerY - valueImageSize / 2,
                width: valueImageSize,
                height: valueImageSize
            )
        }

        if !isDragging {
            // Layout thumb and track
            updateThumbPosition(animated: false)
            updateTrackLayout()
            updateTrackFill()
        }
    }

    private func updateTrackLayout() {
        let centerY = bounds.height / 2
        
        // Apply rubber-band effect: move track horizontally with thumb and shrink vertically
        let trackHorizontalOffset = rubberBandOffset / 4 * 3 - abs(rubberBandOffset) / 4
        let rubberBandTrackHeightShrink = abs(rubberBandOffset) / 3
        let effectiveTrackHeight = max(2, trackHeight - rubberBandTrackHeightShrink)
        
        trackView.frame = CGRect(
            x: trackMinX + trackHorizontalOffset,
            y: centerY - effectiveTrackHeight / 2,
            width: trackWidth + abs(rubberBandOffset) / 2,
            height: effectiveTrackHeight
        )
        trackView.layer.cornerRadius = effectiveTrackHeight / 2
    }
    
    // MARK: - Public Methods (UISlider Interface)
    
    /// Sets the slider's current value, allowing you to animate the change visually.
    open func setValue(_ value: Float, animated: Bool) {
        let clampedValue = min(max(value, minimumValue), maximumValue)
        guard self.value != clampedValue else { return }
        
        isUpdatingValueProgrammatically = true
        self.value = clampedValue
        isUpdatingValueProgrammatically = false
        
        updateThumbPosition(animated: animated)
        updateTrackFill()
    }
    
    /// Assigns a thumb image to the specified control states.
    open func setThumbImage(_ image: UIImage?, for state: UIControl.State) {
        thumbImages[state.rawValue] = image
    }
    
    /// Assigns a minimum track image to the specified control states.
    open func setMinimumTrackImage(_ image: UIImage?, for state: UIControl.State) {
        minimumTrackImages[state.rawValue] = image
    }
    
    /// Assigns a maximum track image to the specified control states.
    open func setMaximumTrackImage(_ image: UIImage?, for state: UIControl.State) {
        maximumTrackImages[state.rawValue] = image
    }
    
    /// Returns the thumb image associated with the specified control state.
    open func thumbImage(for state: UIControl.State) -> UIImage? {
        thumbImages[state.rawValue] ?? nil
    }
    
    /// Returns the minimum track image associated with the specified control state.
    open func minimumTrackImage(for state: UIControl.State) -> UIImage? {
        minimumTrackImages[state.rawValue] ?? nil
    }
    
    /// Returns the maximum track image associated with the specified control state.
    open func maximumTrackImage(for state: UIControl.State) -> UIImage? {
        maximumTrackImages[state.rawValue] ?? nil
    }
    
    /// The thumb image currently being used to render the slider.
    open var currentThumbImage: UIImage? {
        thumbImage(for: state) ?? thumbImage(for: .normal)
    }
    
    /// The minimum track image currently being used to render the slider.
    open var currentMinimumTrackImage: UIImage? {
        minimumTrackImage(for: state) ?? minimumTrackImage(for: .normal)
    }
    
    /// The maximum track image currently being used to render the slider.
    open var currentMaximumTrackImage: UIImage? {
        maximumTrackImage(for: state) ?? maximumTrackImage(for: .normal)
    }
    
    /// Returns the drawing rectangle for the slider's minimum value image.
    open func minimumValueImageRect(forBounds bounds: CGRect) -> CGRect {
        guard minimumValueImage != nil else { return .zero }
        return CGRect(
            x: 0,
            y: (bounds.height - valueImageSize) / 2,
            width: valueImageSize,
            height: valueImageSize
        )
    }
    
    /// Returns the drawing rectangle for the slider's maximum value image.
    open func maximumValueImageRect(forBounds bounds: CGRect) -> CGRect {
        guard maximumValueImage != nil else { return .zero }
        return CGRect(
            x: bounds.width - valueImageSize,
            y: (bounds.height - valueImageSize) / 2,
            width: valueImageSize,
            height: valueImageSize
        )
    }
    
    /// Returns the drawing rectangle for the slider's track.
    open func trackRect(forBounds bounds: CGRect) -> CGRect {
        let minX = minimumValueImage != nil ? (valueImageSize + valueImagePadding) : 0
        let maxX = bounds.width - (maximumValueImage != nil ? (valueImageSize + valueImagePadding) : 0)
        return CGRect(
            x: minX,
            y: (bounds.height - trackHeight) / 2,
            width: maxX - minX,
            height: trackHeight
        )
    }
    
    /// Returns the drawing rectangle for the slider's thumb image.
    open func thumbRect(forBounds bounds: CGRect, trackRect rect: CGRect, value: Float) -> CGRect {
        guard maximumValue > minimumValue else {
            return CGRect(
                x: rect.minX,
                y: (bounds.height - contractedThumbHeight) / 2,
                width: contractedThumbWidth,
                height: contractedThumbHeight
            )
        }
        
        let normalizedValue = CGFloat((value - minimumValue) / (maximumValue - minimumValue))
        let thumbRange = rect.width - contractedThumbWidth
        let thumbX = rect.minX + thumbRange * normalizedValue
        
        return CGRect(
            x: thumbX,
            y: (bounds.height - contractedThumbHeight) / 2,
            width: contractedThumbWidth,
            height: contractedThumbHeight
        )
    }
    
    // MARK: - Track Appearance
    
    private func updateTrackAppearance() {
        trackView.backgroundColor = resolvedMaximumTrackTintColor
    }
    
    private func updateTrackFill() {
        let thumbCenterX = currentThumbCenterX
        
        // Calculate fill width based on thumb position, matching track frame
        let fillMinX = trackView.frame.minX
        let d = 10.0
        let kMin = min(max(0, (thumbCenterX - minThumbCenterX) / d), 1)
        let kMax = min(max(0, (maxThumbCenterX - thumbCenterX) / d), 1)
        let fillWidth = max(0, thumbCenterX - fillMinX) * kMin * kMax + trackView.frame.width * (1 - kMax)

        trackFillView.frame = CGRect(
            x: fillMinX,
            y: trackView.frame.minY,
            width: fillWidth,
            height: trackView.frame.height
        )
        trackFillView.layer.cornerRadius = trackView.layer.cornerRadius
        trackFillView.backgroundColor = resolvedMinimumTrackTintColor
    }
    
    private func updateValueImages() {
        minimumValueImageView.image = minimumValueImage
        minimumValueImageView.isHidden = minimumValueImage == nil
        
        maximumValueImageView.image = maximumValueImage
        maximumValueImageView.isHidden = maximumValueImage == nil
        
        setNeedsLayout()
    }
    
    // MARK: - Thumb Position
    
    private func updateThumbPosition(animated: Bool) {
        let centerY = bounds.height / 2
        let targetCenter = CGPoint(x: targetThumbCenterX, y: centerY)
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
            } completion: { _ in
                self.updateTrackFill()
            }
        } else {
            thumbView.center = targetCenter
        }
    }
    
    // MARK: - Thumb State (Contracted/Expanded Morphing)
    
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
    
    private func updateThumbAppearance() {
        contractedThumbView.backgroundColor = resolvedContractedThumbColor
    }
    
    // MARK: - Touch Handling
    
    open override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard isEnabled, let touch = touches.first else { return }
        
        isDragging = false
        didTriggerMinHaptic = false
        didTriggerMaxHaptic = false
        rubberBandOffset = 0
        touchBeganTime = CACurrentMediaTime()
        dragStartLocation = touch.location(in: self).x
        dragStartThumbCenterX = currentThumbCenterX
        
        // Expand thumb immediately
        expandThumb(animated: true)
        
        // Prepare haptic feedback
        lightFeedbackGenerator?.prepare()
        mediumFeedbackGenerator?.prepare()
    }
    
    open override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard isEnabled, let touch = touches.first else { return }
        
        // Promote to drag after time threshold
        let touchDuration = CACurrentMediaTime() - touchBeganTime
        if !isDragging && touchDuration >= tapTimeThreshold {
            isDragging = true
        }
        
        let currentX = touch.location(in: self).x
        let translation = currentX - dragStartLocation
        let newCenterX = dragStartThumbCenterX + translation
        
        // Apply rubber-band clamping to thumb position (same formula as LiquidGlassSwitch)
        let clampedCenterX = clampWithRubberBand(newCenterX, min: minThumbCenterX, max: maxThumbCenterX)
        
        // Calculate rubber-band offset for track layout
        if newCenterX < minThumbCenterX {
            rubberBandOffset = clampedCenterX - minThumbCenterX
        } else if newCenterX > maxThumbCenterX {
            rubberBandOffset = clampedCenterX - maxThumbCenterX
        } else {
            rubberBandOffset = 0
        }
        
        currentThumbCenterX = clampedCenterX

        // Update track layout with rubber-band effect
        updateTrackLayout()
        updateTrackFill()
        
        // Update value based on position (clamped to valid range)
        let effectiveCenterX = min(max(newCenterX, minThumbCenterX), maxThumbCenterX)
        let normalizedPosition = thumbCenterRange > 0 ? (effectiveCenterX - minThumbCenterX) / thumbCenterRange : 0
        let newValue = minimumValue + Float(normalizedPosition) * (maximumValue - minimumValue)
        
        isUpdatingValueProgrammatically = true
        value = newValue
        isUpdatingValueProgrammatically = false

        // Check for edge haptics
        checkForEdgeHaptics(at: newCenterX)
    }
    
    open override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        
        let touchDuration = CACurrentMediaTime() - touchBeganTime
        
        if touchDuration < tapTimeThreshold, let touch = touches.first {
            // This was a tap - move thumb to tap location
            let tapX = touch.location(in: self).x
            let clampedX = min(max(tapX, minThumbCenterX), maxThumbCenterX)
            let normalizedPosition = (clampedX - minThumbCenterX) / thumbCenterRange
            let newValue = minimumValue + Float(normalizedPosition) * (maximumValue - minimumValue)
            
            isUpdatingValueProgrammatically = true
            value = newValue
            isUpdatingValueProgrammatically = false
            
            updateThumbPosition(animated: true)
            updateTrackFill()
            
            // Trigger appropriate haptic based on position
            if abs(newValue - minimumValue) < 0.01 {
                lightFeedbackGenerator?.impactOccurred()
            } else if abs(newValue - maximumValue) < 0.01 {
                mediumFeedbackGenerator?.impactOccurred()
            }
            
            // Schedule contraction after tap animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self, !self.isDragging else { return }
                self.contractThumb(animated: true)
            }
        } else {
            // Finish drag
            finishDrag()
        }
    }
    
    open override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        if isDragging {
            finishDrag()
        } else if isThumbExpanded {
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
    
    private func checkForEdgeHaptics(at centerX: CGFloat) {
        let edgeThreshold: CGFloat = 2.0
        
        // Check minimum edge (lighter haptic)
        if centerX <= minThumbCenterX + edgeThreshold && !didTriggerMinHaptic {
            didTriggerMinHaptic = true
            didTriggerMaxHaptic = false
            lightFeedbackGenerator?.impactOccurred()
        }
        // Check maximum edge (stronger haptic)
        else if centerX >= maxThumbCenterX - edgeThreshold && !didTriggerMaxHaptic {
            didTriggerMaxHaptic = true
            didTriggerMinHaptic = false
            mediumFeedbackGenerator?.impactOccurred()
        }
        // Reset haptic flags when moving away from edges
        else if centerX > minThumbCenterX + edgeThreshold * 2 && centerX < maxThumbCenterX - edgeThreshold * 2 {
            didTriggerMinHaptic = false
            didTriggerMaxHaptic = false
        }
    }
    
    private func finishDrag() {
        isDragging = false
        rubberBandOffset = 0
        
        // Animate track back to normal and thumb to final position
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState]
        ) {
            self.updateTrackLayout()
            self.updateTrackFill()
        }
        
        // Contract thumb and animate to final position
        contractThumb(animated: true)
        updateThumbPosition(animated: true)
    }

    // MARK: - State Handling
    
    open override var isEnabled: Bool {
        didSet {
            alpha = isEnabled ? 1.0 : 0.5
        }
    }
    
    // MARK: - Accessibility
    
    open override func accessibilityIncrement() {
        let step = (maximumValue - minimumValue) / 10
        setValue(value + step, animated: true)
    }
    
    open override func accessibilityDecrement() {
        let step = (maximumValue - minimumValue) / 10
        setValue(value - step, animated: true)
    }
}
#endif

// MARK: - AnySlider Protocol

public protocol AnySlider: UIControl {
    var value: Float { get set }
    var minimumValue: Float { get set }
    var maximumValue: Float { get set }
    var minimumValueImage: UIImage? { get set }
    var maximumValueImage: UIImage? { get set }
    var isContinuous: Bool { get set }
    @available(iOS 26.0, *)
    var sliderStyle: UISlider.Style { get set }
    var minimumTrackTintColor: UIColor? { get set }
    var maximumTrackTintColor: UIColor? { get set }
    var thumbTintColor: UIColor? { get set }
    func setValue(_ value: Float, animated: Bool)
    func setThumbImage(_ image: UIImage?, for state: UIControl.State)
    func setMinimumTrackImage(_ image: UIImage?, for state: UIControl.State)
    func setMaximumTrackImage(_ image: UIImage?, for state: UIControl.State)
    func thumbImage(for state: UIControl.State) -> UIImage?
    func minimumTrackImage(for state: UIControl.State) -> UIImage?
    func maximumTrackImage(for state: UIControl.State) -> UIImage?
    var currentThumbImage: UIImage? { get }
    var currentMinimumTrackImage: UIImage? { get }
    var currentMaximumTrackImage: UIImage? { get }
    func minimumValueImageRect(forBounds bounds: CGRect) -> CGRect
    func maximumValueImageRect(forBounds bounds: CGRect) -> CGRect
    func trackRect(forBounds bounds: CGRect) -> CGRect
    func thumbRect(forBounds bounds: CGRect, trackRect rect: CGRect, value: Float) -> CGRect
}

extension UISlider: AnySlider { }

extension LiquidGlassSlider: AnySlider {
    public static func make(isNative: Bool = true) -> AnySlider {
        if #available(iOS 26.0, *), isNative {
            UISlider()
        } else {
            LiquidGlassSlider()
        }
    }
}
