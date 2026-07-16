//
//  LiquidGlassEffectView.swift
//  LiquidGlass
//
//  Created by Alexey Demin on 2025-12-23.
//

#if canImport(UIKit)
import UIKit

public class LiquidGlassEffectView: UIView, AnyVisualEffectView {

    public let contentView = UIView()
    public var effect: UIVisualEffect?

    var liquidGlassView: LiquidGlassView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let liquidGlassView {
                insertSubview(liquidGlassView, belowSubview: contentView)
            }
        }
    }

    public required init(effect: LiquidGlassEffect) {
        self.effect = effect

        super.init(frame: .zero)

        let liquidGlassView = LiquidGlassView(effect.style.liquidGlass)
        addSubview(liquidGlassView)
        self.liquidGlassView = liquidGlassView
        
        setupContentView()
    }

    public required init(effect: LiquidGlassContainerEffect) {
        self.effect = effect

        super.init(frame: .zero)

        setupContentView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupContentView() {
        addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        liquidGlassView?.frame = contentView.frame
        liquidGlassView?.layer.cornerRadius = layer.cornerRadius
        if #available(iOS 13.0, *) {
            liquidGlassView?.layer.cornerCurve = layer.cornerCurve
        }
    }
}

/// A visual effect that renders a glass material.
public class LiquidGlassEffect: UIVisualEffect {

    public enum Style {
        case regular, clear

        @available(iOS 26.0, *)
        var nativeStyle: UIGlassEffect.Style {
            switch self {
            case .regular: .regular
            case .clear: .clear
            }
        }

        var liquidGlass: LiquidGlass {
            switch self {
            case .regular: .regular
            case .clear: .regular // TODO: Add clear LiquidGlass preset.
            }
        }
    }
    let style: Style

    let isNative: Bool

    /// Enables interactive behavior for the glass effect.
    public var isInteractive = false

    /// A tint color applied to the glass.
    public var tintColor: UIColor?

    /// Creates a glass effect with the specified style.
    /// - Parameters:
    ///   - style: The glass effect style.
    ///   - isNative: Whether to use `UIGlassEffect` on iOS 26+.
    public init(style: Style, isNative: Bool = true) {
        self.style = style
        self.isNative = isNative
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// A `LiquidGlassContainerEffect` renders multiple glass elements into a combined effect.
public class LiquidGlassContainerEffect: UIVisualEffect {

    let isNative: Bool

    /// The spacing specifies the distance between elements at which they begin to merge.
    public var spacing = 10.0

    /// Creates a combined glass effect.
    /// - Parameters:
    ///   - isNative: Whether to use `UIGlassContainerEffect` on iOS 26+.
    public init(isNative: Bool = true) {
        self.isNative = isNative
        super.init()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public protocol AnyVisualEffectView: UIView {
    var contentView: UIView { get }
    var effect: UIVisualEffect? { get set }
}

extension UIVisualEffectView: AnyVisualEffectView { }

public func VisualEffectView(effect: UIVisualEffect?) -> AnyVisualEffectView {
    if let effect = effect as? LiquidGlassEffect {
        if #available(iOS 26.0, *), effect.isNative {
            let nativeEffect = UIGlassEffect(style: effect.style.nativeStyle)
            nativeEffect.isInteractive = effect.isInteractive
            nativeEffect.tintColor = effect.tintColor
            return UIVisualEffectView(effect: nativeEffect)
        } else {
            return LiquidGlassEffectView(effect: effect)
        }
    } else if let effect = effect as? LiquidGlassContainerEffect {
        if #available(iOS 26.0, *), effect.isNative {
            let nativeEffect = UIGlassContainerEffect()
            nativeEffect.spacing = effect.spacing
            return UIVisualEffectView(effect: nativeEffect)
        } else {
            return LiquidGlassEffectView(effect: effect)
        }
    } else {
        return UIVisualEffectView(effect: effect)
    }
}

#elseif canImport(AppKit)
import AppKit

public class LiquidGlassEffect: NSObject {
    public enum Style {
        case regular, clear

        @available(macOS 26.0, *)
        var nativeStyle: NSGlassEffectView.Style {
            switch self {
            case .regular: .regular
            case .clear: .clear
            }
        }

        var liquidGlass: LiquidGlass {
            switch self {
            case .regular: .regular
            case .clear: .regular
            }
        }
    }

    let style: Style
    let isNative: Bool

    public var isInteractive = false
    public var tintColor: NSColor?

    public init(style: Style, isNative: Bool = true) {
        self.style = style
        self.isNative = isNative
        super.init()
    }
}

public class LiquidGlassContainerEffect: NSObject {
    let isNative: Bool
    public var spacing = 10.0

    public init(isNative: Bool = true) {
        self.isNative = isNative
        super.init()
    }
}

public protocol AnyVisualEffectView: NSView {
    var contentView: NSView { get }
}

public final class LiquidGlassEffectView: NSView, AnyVisualEffectView {
    public let contentView = NSView()

    private var liquidGlassView: LiquidGlassView?
    private var nativeGlassView: NSView?
    private let cornerRadius: CGFloat

    public init(effect: LiquidGlassEffect, cornerRadius: CGFloat = 24) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true

        if #available(macOS 26.0, *), effect.isNative {
            let glassView = NSGlassEffectView()
            glassView.style = effect.style.nativeStyle
            glassView.cornerRadius = cornerRadius
            glassView.tintColor = effect.tintColor
            glassView.contentView = contentView
            addSubview(glassView)
            nativeGlassView = glassView
        } else {
            let glassView = LiquidGlassView(effect.style.liquidGlass)
            glassView.layer?.cornerRadius = cornerRadius
            addSubview(glassView)
            liquidGlassView = glassView
            addSubview(contentView)
        }
    }

    public init(effect: LiquidGlassContainerEffect, cornerRadius: CGFloat = 24) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true

        if #available(macOS 26.0, *), effect.isNative {
            let containerView = NSGlassEffectContainerView()
            containerView.spacing = effect.spacing
            containerView.contentView = contentView
            addSubview(containerView)
            nativeGlassView = containerView
        } else {
            let glassView = LiquidGlassView(.regular)
            glassView.layer?.cornerRadius = cornerRadius
            addSubview(glassView)
            liquidGlassView = glassView
            addSubview(contentView)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layout() {
        super.layout()

        nativeGlassView?.frame = bounds
        liquidGlassView?.frame = bounds
        liquidGlassView?.layer?.cornerRadius = cornerRadius
        contentView.frame = bounds
    }
}

public func VisualEffectView(effect: LiquidGlassEffect) -> AnyVisualEffectView {
    LiquidGlassEffectView(effect: effect)
}

public func VisualEffectView(effect: LiquidGlassContainerEffect) -> AnyVisualEffectView {
    LiquidGlassEffectView(effect: effect)
}
#endif
