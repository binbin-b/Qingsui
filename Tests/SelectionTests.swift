import AppKit
import SwiftUI

@main @MainActor struct SelectionTests {
    static func main() {
        _ = NSApplication.shared
        let selection = TranscriptSelection()
        let ids = [UUID(), UUID(), UUID()]
        let strings = ["第一条😀文字", "中间的气泡", "第三条内容"]
        let views = strings.enumerated().map { index, value -> BubbleTextView in
            let view = BubbleTextView(frame: NSRect(x: 0, y: index*60, width: 220, height: 50))
            view.string = value; view.messageID = ids[index]; view.selection = selection
            view.isEditable = false; view.isSelectable = true
            selection.entries[ids[index]] = .init(view: view)
            return view
        }
        selection.order = ids
        selection.anchor = (ids[0], 1)
        selection.extend(to: views[0], index: 3)
        precondition(selection.selectedText == "一条")
        selection.anchor = (ids[0], 3)
        selection.extend(to: views[2], index: 2)
        precondition(selection.selectedText == "😀文字\n\n中间的气泡\n\n第三")
        selection.anchor = (ids[2], 2)
        selection.extend(to: views[0], index: 3)
        precondition(selection.selectedText == "😀文字\n\n中间的气泡\n\n第三")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 250), styleMask: [.borderless], backing: .buffered, defer: false)
        let content = NSView(frame: window.contentView!.bounds); window.contentView = content
        for view in views { content.addSubview(view); view.layoutManager?.ensureLayout(for: view.textContainer!) }
        let start = views[0].convert(NSPoint(x: 12, y: 8), to: nil)
        let end = views[2].convert(NSPoint(x: 25, y: 8), to: nil)
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        views[0].mouseDown(with: mouse(.leftMouseDown, start))
        views[0].mouseDragged(with: mouse(.leftMouseDragged, end))
        views[0].mouseUp(with: mouse(.leftMouseUp, end))
        precondition(selection.selectedText.contains("中间的气泡"), "真实事件处理应选择中间气泡")
        let old = NSPasteboard.general.string(forType: .string)
        views[2].copy(nil)
        precondition(NSPasteboard.general.string(forType: .string) == selection.selectedText)
        NSPasteboard.general.clearContents(); if let old { NSPasteboard.general.setString(old, forType: .string) }
        var completionCount = 0
        views[0].doubleClick = { completionCount += 1 }
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 2, pressure: 1)!
        views[0].mouseDown(with: event); precondition(completionCount == 1)
        for width in [120.0, 220, 540] {
            let component = SelectableMessage(id: ids[0], text: String(repeating: "长消息😀与跨气泡选择。\n", count: 150), width: width, fontSize: 14, processed: false, selection: selection, doubleClick: {}, actions: [])
            let host = NSHostingView(rootView: component); host.sizingOptions = []
            host.frame = NSRect(x: 0, y: 0, width: width, height: 7000)
            for _ in 0..<20 { host.layoutSubtreeIfNeeded() }
            precondition(host.fittingSize.height.isFinite)
        }
        print("PASS: 单气泡部分选择、跨三气泡正反拖选、UTF16、复制、双击、长消息三种宽度布局")
    }
}
