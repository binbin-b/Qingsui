import AppKit

@main
@MainActor
struct EditorLayoutTests {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let scroll = MessageEditor.makeScrollView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 140), styleMask: [.borderless], backing: .buffered, defer: false)
        // This test window is never ordered on screen or activated.
        window.contentView = scroll
        guard let editor = scroll.documentView as? PasteTextView else { fatalError("Missing production editor") }
        var heights: [CGFloat] = []
        editor.onHeight = { heights.append($0) }
        let widths: [CGFloat] = [220, 280, 700, 260, 900, 220, 240, 600]
        let start = Date()
        for cycle in 0..<12 {
            for width in widths {
                scroll.setFrameSize(NSSize(width: width, height: 28))
                scroll.tile()
                precondition(editor.frame.width > 0 && editor.frame.height >= 28, "Editor hit area must survive narrow resizing")
                precondition(abs(editor.frame.width - scroll.contentSize.width) < 1, "Editor must match viewport width")
                editor.string = cycle % 2 == 0 ? "" : "First line\nSecond line " + String(repeating: "long content ", count: 12)
                editor.scheduleMeasurement()
                RunLoop.current.run(until: Date().addingTimeInterval(0.003))
            }
        }
        scroll.setFrameSize(NSSize(width: 220, height: 140)); scroll.tile()
        editor.string = ""
        var lastDocumentHeight: CGFloat = 28
        for _ in 0..<180 {
            editor.insertText("连续输入文字", replacementRange: NSRange(location: (editor.string as NSString).length, length: 0))
            editor.scheduleMeasurement()
            RunLoop.current.run(until: Date().addingTimeInterval(0.002))
            precondition(editor.frame.height >= lastDocumentHeight, "持续输入不能反复压缩文档高度")
            lastDocumentHeight = editor.frame.height
        }
        precondition(editor.frame.height > 140 && heights.last == 140, "长文本保留完整文档高度，输入框只扩展到最大高度")
        let settled = heights.count
        for _ in 0..<50 { scroll.tile(); editor.scheduleMeasurement() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        precondition(heights.count == settled, "长文布局必须收敛，不能不断发布高度")
        editor.string = ""
        editor.scheduleMeasurement()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        precondition(heights.last == 28, "Clearing must restore one-line height")
        let count = heights.count
        for _ in 0..<100 { editor.scheduleMeasurement() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        precondition(heights.count == count, "Unchanged layout must not republish height")
        precondition(Date().timeIntervalSince(start) < 10, "Layout must settle without a feedback loop")
        print("PASS: production editor survives 96 narrow/wide resizes, empty hit area, multiline measurement, unchanged-height coalescing; 1080 continuous characters without document-height oscillation")
        window.contentView = nil
    }
}
