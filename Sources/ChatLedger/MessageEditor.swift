import AppKit
import SwiftUI

struct MessageEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var onFiles: ([URL]) -> Void
    var onImage: (Data) -> Void
    var onReturn: () -> Void
    var onNavigation: (UInt16) -> Bool
    var focusRequest = 0
    var accessibilityName = "消息输入框"

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = Self.makeScrollView()
        if let editor = scroll.documentView as? PasteTextView {
            editor.delegate = context.coordinator
            callbacks(editor)
        }
        return scroll
    }
    static func makeScrollView() -> MessageScrollView {
        let scroll = MessageScrollView()
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScrollElasticity = .none
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let editor = PasteTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.font = .systemFont(ofSize: 14)
        editor.textColor = .labelColor
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 2, height: 4)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.minSize = NSSize(width: 0, height: 28)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.setAccessibilityLabel("消息输入框")
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? PasteTextView else { return }
        let changed = editor.string != text && !editor.hasMarkedText()
        if changed {
            editor.string = text
            editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        callbacks(editor)
        let width = max(1, scroll.contentSize.width)
        let targetSize = NSSize(width: width, height: max(editor.frame.height, 28, scroll.contentSize.height))
        if abs(editor.frame.width - targetSize.width) > 0.5 || abs(editor.frame.height - targetSize.height) > 0.5 {
            editor.setFrameSize(targetSize)
        }
        if changed { editor.scheduleMeasurement() }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { [weak editor] in if let editor { editor.window?.makeFirstResponder(editor) } }
        }
    }
    private func callbacks(_ editor: PasteTextView) {
        editor.setAccessibilityLabel(accessibilityName)
        editor.onFiles = onFiles; editor.onImage = onImage
        editor.onReturn = onReturn; editor.onNavigation = onNavigation
        editor.onHeight = { value in
            if abs(height - value) > 0.5 { height = value }
        }
    }
    class Coordinator: NSObject, NSTextViewDelegate {
        var lastFocusRequest = 0
        var parent: MessageEditor
        init(_ parent: MessageEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? PasteTextView else { return }
            parent.text = view.string
            view.scheduleMeasurement()
        }
    }
}

final class PasteTextView: NSTextView {
    var onFiles: (([URL]) -> Void)?
    var onImage: ((Data) -> Void)?
    var onReturn: (() -> Void)?
    var onNavigation: ((UInt16) -> Bool)?
    var onHeight: ((CGFloat) -> Void)?
    private var lastReportedHeight: CGFloat?
    private var measurementPending = false
    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(frame.width - newSize.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged { scheduleMeasurement() }
    }
    func scheduleMeasurement() {
        guard !measurementPending else { return }
        measurementPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.measurementPending = false
            self.measure()
        }
    }
    private func measure() {
        guard let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let height = layoutManager.usedRect(for: textContainer).height + 9
        let documentHeight = max(28, ceil(height), enclosingScrollView?.contentSize.height ?? 28)
        if abs(frame.height - documentHeight) > 0.5 { setFrameSize(NSSize(width: frame.width, height: documentHeight)) }
        let measured = min(140, max(28, ceil(height)))
        guard lastReportedHeight != measured else { return }
        lastReportedHeight = measured
        onHeight?(measured)
    }
    override func paste(_ sender: Any?) {
        let board = NSPasteboard.general
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            onFiles?(urls); return
        }
        if let image = NSImage(pasteboard: board), let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            onImage?(png); return
        }
        super.paste(sender)
    }
    override func keyDown(with event: NSEvent) {
        if !hasMarkedText() {
            if [36, 76].contains(event.keyCode) {
                if event.modifierFlags.contains(.shift) { insertNewline(nil) }
                else { onReturn?() }
                return
            }
            if [48, 53, 125, 126].contains(event.keyCode), onNavigation?(event.keyCode) == true { return }
        }
        super.keyDown(with: event)
    }
}

/// NSTextView must have a nonzero hit area before the first keystroke,
/// including when the app starts/restores directly into a narrow window.
final class MessageScrollView: NSScrollView {
    override func tile() {
        super.tile()
        guard let editor = documentView as? PasteTextView, contentSize.width > 0 else { return }
        let size = NSSize(width: contentSize.width, height: max(28, contentSize.height, editor.frame.height))
        if abs(editor.frame.width - size.width) > 0.5 || abs(editor.frame.height - size.height) > 0.5 {
            editor.setFrameSize(size)
        }
    }
}
