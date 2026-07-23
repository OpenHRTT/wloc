import SnapKit
import UIKit

final class WLocGlassView: UIView {
    let contentView: UIView

    init(cornerRadius: CGFloat = 24, fallbackStyle: UIBlurEffect.Style = .light) {
        let effectView = UIVisualEffectView(effect: UIBlurEffect(style: fallbackStyle))
        contentView = effectView.contentView
        super.init(frame: .zero)
        addSubview(effectView)
        effectView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        clipsToBounds = false
        layer.cornerRadius = cornerRadius
        if #available(iOS 13.0, *) {
            layer.cornerCurve = .continuous
        }
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.16
        layer.shadowRadius = 22
        layer.shadowOffset = CGSize(width: 0, height: 10)

        contentView.superview?.clipsToBounds = true
        contentView.superview?.layer.cornerRadius = cornerRadius
        if #available(iOS 13.0, *) {
            contentView.superview?.layer.cornerCurve = .continuous
        }

        let highlight = UIView()
        highlight.isUserInteractionEnabled = false
        highlight.layer.borderWidth = 1
        highlight.layer.borderColor = UIColor.white.withAlphaComponent(0.55).cgColor
        highlight.layer.cornerRadius = cornerRadius
        if #available(iOS 13.0, *) {
            highlight.layer.cornerCurve = .continuous
        }
        addSubview(highlight)
        highlight.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        nil
    }
}

final class WLocGlassButton: UIButton {
    enum Style {
        case primary
        case secondary
        case icon
    }

    init(title: String, style: Style = .secondary) {
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        titleLabel?.font = .systemFont(ofSize: style == .primary ? 16 : 14, weight: .semibold)
        layer.cornerRadius = style == .icon ? 24 : 16
        if #available(iOS 13.0, *) {
            layer.cornerCurve = .continuous
        }
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.55).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = style == .primary ? 0.18 : 0.1
        layer.shadowRadius = style == .primary ? 14 : 8
        layer.shadowOffset = CGSize(width: 0, height: style == .primary ? 8 : 4)
        contentEdgeInsets = UIEdgeInsets(top: 11, left: 14, bottom: 11, right: 14)

        switch style {
        case .primary:
            setTitleColor(.white, for: .normal)
            backgroundColor = UIColor(red: 0.06, green: 0.35, blue: 0.95, alpha: 0.88)
        case .secondary:
            setTitleColor(UIColor(red: 0.08, green: 0.12, blue: 0.18, alpha: 1), for: .normal)
            backgroundColor = UIColor.white.withAlphaComponent(0.46)
        case .icon:
            setTitleColor(UIColor(red: 0.08, green: 0.12, blue: 0.18, alpha: 1), for: .normal)
            backgroundColor = UIColor.white.withAlphaComponent(0.5)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }
}
