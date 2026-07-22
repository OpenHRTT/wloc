import AppKit

extension NSTextField {
    static func wlocLabel(_ text: String) -> NSTextField {
        let field = NSTextField(frame: .zero)
        field.stringValue = text
        field.isEditable = false
        field.isSelectable = false
        field.isBordered = false
        field.drawsBackground = false
        return field
    }

    static func wlocWrappingLabel(_ text: String) -> NSTextField {
        let field = wlocLabel(text)
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.maximumNumberOfLines = 0
        return field
    }
}

extension NSButton {
    static func wlocButton(_ title: String) -> NSButton {
        let button = NSButton(frame: .zero)
        button.title = title
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        return button
    }
}
