import AppKit
import SwiftUI

struct FloatingToggleButton: NSViewRepresentable {
    let visible: Bool
    let compact: Bool
    let action: () -> Void

    func makeNSView(context: Context) -> FloatingToggleControl { FloatingToggleControl(frame: .zero) }
    func updateNSView(_ button: FloatingToggleControl, context: Context) {
        button.onActivate = action
        button.title = compact ? "" : "悬浮球"
        button.image = NSImage(systemSymbolName: visible ? "circle.inset.filled" : "circle.dashed", accessibilityDescription: nil)
        button.imagePosition = compact ? .imageOnly : .imageLeading
        button.contentTintColor = visible ? NSColor(Palette.accent) : .secondaryLabelColor
        button.toolTip = visible ? "悬浮球已开启，点击隐藏" : "显示桌面悬浮球，单击或停留片刻展开待办"
        button.setAccessibilityLabel(visible ? "隐藏悬浮球" : "显示悬浮球")
    }
}

final class FloatingToggleControl: NSButton {
    var onActivate: (() -> Void)?
    override var acceptsFirstResponder: Bool { false }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }
    private func configure() {
        setButtonType(.momentaryPushIn)
        isBordered = false
        focusRingType = .none
        font = .systemFont(ofSize: 11, weight: .medium)
        imageScaling = .scaleProportionallyDown
        target = self
        action = #selector(activate)
    }
    @objc private func activate() { onActivate?() }
}

struct ToolbarActionButton: NSViewRepresentable {
    var title = ""
    let symbol: String
    let help: String
    let action: () -> Void
    func makeNSView(context: Context) -> FloatingToggleControl { FloatingToggleControl(frame: .zero) }
    func updateNSView(_ button: FloatingToggleControl, context: Context) {
        button.onActivate = action
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = help
        button.setAccessibilityLabel(help)
    }
}
