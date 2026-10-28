import SwiftUI
import AppKit

@MainActor
final class TranscriptSelection: ObservableObject {
    struct Entry { weak var view: BubbleTextView? }
    var entries: [UUID: Entry] = [:]
    var order: [UUID] = []
    var anchor: (UUID, Int)?
    func begin(_ view: BubbleTextView, at point: NSPoint) {
        for entry in entries.values { entry.view?.setSelectedRange(NSRange(location: 0, length: 0)) }
        anchor = (view.messageID, view.character(at: point))
    }
    func extend(to view: BubbleTextView, index: Int) {
        guard let anchor, let a = order.firstIndex(of: anchor.0), let b = order.firstIndex(of: view.messageID) else { return }
        let forward = a < b || (a == b && anchor.1 <= index)
        let start = forward ? (a, anchor.1) : (b, index)
        let end = forward ? (b, index) : (a, anchor.1)
        for (i, id) in order.enumerated() {
            guard let text = entries[id]?.view else { continue }
            let length = (text.string as NSString).length
            let low = i == start.0 ? min(start.1, length) : 0
            let high = i == end.0 ? min(end.1, length) : length
            text.setSelectedRange(i >= start.0 && i <= end.0 ? NSRange(location: low, length: max(0, high-low)) : NSRange(location: 0, length: 0))
        }
    }
    func drag(_ event: NSEvent, source: BubbleTextView) {
        let point = event.locationInWindow
        let views = order.compactMap { entries[$0]?.view }.filter { $0.window === source.window }
        guard let nearest = views.min(by: { distance($0, point) < distance($1, point) }) else { return }
        extend(to: nearest, index: nearest.character(at: nearest.convert(point, from: nil)))
        source.enclosingScrollView?.autoscroll(with: event)
    }
    private func distance(_ view: NSView, _ point: NSPoint) -> CGFloat {
        let rect = view.convert(view.bounds, to: nil)
        return max(rect.minY-point.y, 0, point.y-rect.maxY)
    }
    var selectedText: String {
        order.compactMap { id -> String? in
            guard let view = entries[id]?.view, view.selectedRange().length > 0 else { return nil }
            return (view.string as NSString).substring(with: view.selectedRange())
        }.joined(separator: "\n\n")
    }
}

final class BubbleTextView: NSTextView {
    var messageID = UUID()
    weak var selection: TranscriptSelection?
    var singleClick: (() -> Void)?
    var doubleClick: () -> Void = {}
    var actions: [(String, () -> Void)] = []
    private var dragged = false
    override var focusRingType: NSFocusRingType { get { .none } set {} }
    func character(at point: NSPoint) -> Int {
        guard let manager = layoutManager, let container = textContainer else { return 0 }
        let p = NSPoint(x: max(0, point.x-textContainerOrigin.x), y: max(0, point.y-textContainerOrigin.y))
        if p.y > manager.usedRect(for: container).maxY { return (string as NSString).length }
        return min((string as NSString).length, manager.characterIndex(for: p, in: container, fractionOfDistanceBetweenInsertionPoints: nil))
    }
    override func mouseDown(with event: NSEvent) {
        if let singleClick { singleClick(); return }
        if event.clickCount == 2 { doubleClick(); return }
        dragged = false; window?.makeFirstResponder(self)
        selection?.begin(self, at: convert(event.locationInWindow, from: nil))
    }
    override func mouseDragged(with event: NSEvent) { dragged = true; selection?.drag(event, source: self) }
    override func mouseUp(with event: NSEvent) {
        guard singleClick == nil, !dragged else { return }
        let i = character(at: convert(event.locationInWindow, from: nil))
        if i < (string as NSString).length, let url = textStorage?.attribute(.link, at: i, effectiveRange: nil) as? URL { NSWorkspace.shared.open(url) }
    }
    override func copy(_ sender: Any?) {
        let content = selection?.selectedText ?? ""
        if !content.isEmpty { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(content, forType: .string) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        if !(selection?.selectedText.isEmpty ?? true) {
            let item = NSMenuItem(title: "复制所选文字", action: #selector(copy(_:)), keyEquivalent: "")
            item.target = self; menu.addItem(item); menu.addItem(.separator())
        }
        for (index, pair) in actions.enumerated() {
            let item = NSMenuItem(title: pair.0, action: #selector(runAction(_:)), keyEquivalent: "")
            item.tag = index; item.target = self; menu.addItem(item)
        }
        return menu
    }
    @objc private func runAction(_ sender: NSMenuItem) { if actions.indices.contains(sender.tag) { actions[sender.tag].1() } }
}

struct SelectableMessage: NSViewRepresentable {
    let id: UUID
    let text: String
    let width: CGFloat
    let fontSize: CGFloat
    let processed: Bool
    let selection: TranscriptSelection
    let doubleClick: () -> Void
    var singleClick: (() -> Void)? = nil
    let actions: [(String, () -> Void)]
    private func attributed() -> NSAttributedString {
        let style = NSMutableParagraphStyle(); style.lineSpacing = 2
        let value = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: processed ? NSColor.secondaryLabelColor : NSColor.labelColor, .paragraphStyle: style])
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: text, range: NSRange(location: 0, length: value.length)) {
                if let url = match.url { value.addAttribute(.link, value: url, range: match.range) }
            }
        }
        return value
    }
    func makeNSView(context: Context) -> BubbleTextView {
        let view = BubbleTextView(frame: .zero)
        view.isEditable = false; view.isSelectable = true; view.drawsBackground = false
        view.textContainerInset = .zero; view.textContainer?.lineFragmentPadding = 0
        view.isHorizontallyResizable = false; view.isVerticallyResizable = false
        return view
    }
    func updateNSView(_ view: BubbleTextView, context: Context) {
        view.messageID = id; view.selection = selection; view.doubleClick = doubleClick; view.singleClick = singleClick; view.actions = actions
        selection.entries[id] = .init(view: view)
        let value = attributed()
        if view.textStorage?.isEqual(to: value) != true {
            let range = view.selectedRange(); view.textStorage?.setAttributedString(value)
            if NSMaxRange(range) <= value.length { view.setSelectedRange(range) }
        }
        view.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        view.linkTextAttributes = [.foregroundColor: processed ? NSColor.secondaryLabelColor : NSColor.systemTeal, .underlineStyle: NSUnderlineStyle.single.rawValue]
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BubbleTextView, context: Context) -> CGSize? {
        let storage = NSTextStorage(attributedString: attributed())
        let manager = NSLayoutManager(); let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0; manager.addTextContainer(container); storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        return CGSize(width: width, height: ceil(manager.usedRect(for: container).height)+1)
    }
}
