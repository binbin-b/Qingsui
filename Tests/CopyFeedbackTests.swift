import AppKit
import SwiftUI

@main @MainActor struct CopyFeedbackTests {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var tracker = CopyAttemptTracker(count: 10, now: 1)
        precondition(!tracker.observe(count: 11, hasTypes: true, now: 1.1), "没有 CmdC 的剪贴板更新不能触发")
        tracker.arm(count: 11, eventTime: 2, now: 2, global: false)
        precondition(!tracker.observe(count: 11, hasTypes: true, now: 2.1), "只按键未复制不能触发")
        precondition(!tracker.observe(count: 12, hasTypes: false, now: 2.2), "剪贴板为空时不能触发")
        precondition(tracker.observe(count: 12, hasTypes: true, now: 2.3), "延迟写入内容后触发一次")
        precondition(!tracker.observe(count: 12, hasTypes: true, now: 2.4), "重复采样不重复触发")
        tracker.arm(count: 12, eventTime: 2.5, now: 2.5, global: false)
        precondition(!tracker.observe(count: 13, hasTypes: true, now: 2.6), "快速连续复制限制频率")
        tracker.arm(count: 13, eventTime: 3.1, now: 3.1, global: false)
        precondition(!tracker.observe(count: 14, hasTypes: true, now: 4.2) && !tracker.pending, "超过时间窗不宣称成功")
        tracker.arm(count: 14, eventTime: 5, now: 5, global: false)
        precondition(tracker.observe(count: 15, hasTypes: true, now: 5.1), "超时后下一次正常复制可触发")
        var global = CopyAttemptTracker(count: 20, now: 10)
        global.arm(count: 21, eventTime: 10.05, now: 10.1, global: true)
        precondition(global.observe(count: 21, hasTypes: true, now: 10.11), "全局事件异步送达且尚未轮询")
        _ = global.observe(count: 22, hasTypes: true, now: 11.1)
        global.arm(count: 22, eventTime: 11.05, now: 11.15, global: true)
        precondition(global.observe(count: 22, hasTypes: true, now: 11.16), "已轮询到更新的异步事件")
        global.arm(count: 22, eventTime: 12, now: 12, global: true)
        precondition(!global.observe(count: 22, hasTypes: true, now: 12.1), "旧的剪贴板变化不能算新复制")
        print("PASS: metadata-only detection, no false key-only feedback, delayed writes, timeout, cooldown, asynchronous global delivery")

        for valid in ["🍏", "🍏 ✨ 🎉", "👨‍👩‍👧‍👦 🇨🇳 👍🏽 1️⃣ 🍏"] {
            precondition(EmojiSelection.error(valid) == nil)
        }
        precondition(EmojiSelection.values("👨‍👩‍👧‍👦 🇨🇳 👍🏽 1️⃣ 🍏").count == 5)
        for invalid in ["", "  ", "apple", "123", "🍏🍏🍏🍏🍏🍏", "🍏a", "a\u{20E3}"] { precondition(EmojiSelection.error(invalid) != nil, invalid) }
        print("PASS: 1–5 emoji, composed family, skin tone, flag, keycap, rejects plain text and more than five")

        func key(_ chars: String, flags: NSEvent.ModifierFlags = .command, repeating: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: repeating, keyCode: 8)!
        }
        precondition(CopyFeedback.isCopy(key("c")) && CopyFeedback.isCopy(key("C", flags: [.command, .capsLock])))
        precondition(!CopyFeedback.isCopy(key("c", flags: [.command, .shift])) && !CopyFeedback.isCopy(key("c", repeating: true)) && !CopyFeedback.isCopy(key("v")))
        let suite = "Qingsui.Copy.Test." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        var count = 0
        let feedback = CopyFeedback(defaults: preferences, pasteboard: pasteboard, onCopy: { count += 1 })
        precondition(!feedback.enabled && !feedback.globalEnabled)
        feedback.enabled = true; feedback.content = .emoji
        precondition(feedback.saveEmoji("🍏") && !feedback.saveEmoji("not emoji"))
        let restored = CopyFeedback(defaults: preferences, pasteboard: pasteboard)
        precondition(restored.enabled && restored.content == .emoji && restored.emoji == "🍏")
        feedback.receive(key("c"), global: false)
        pasteboard.clearContents(); pasteboard.setString("isolated fixture", forType: .string)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        precondition(count == 1, "真实检测管线用独立剪贴板确认一次，不接触用户剪贴板")
        feedback.enabled = false
        feedback.receive(key("c"), global: false)
        pasteboard.clearContents(); pasteboard.setString("another fixture", forType: .string)
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        precondition(count == 1, "关闭后不再反馈")
        print("PASS: native shortcut filtering, settings persistence, real metadata polling on isolated pasteboard, disabled state")
        let panel = CopyFeedbackPanel.make(frame: .zero)
        precondition(!panel.canBecomeKey && !panel.canBecomeMain && panel.ignoresMouseEvents && !panel.hasShadow && panel.level == .statusBar)
        let screen = NSRect(x: -1440, y: 20, width: 1440, height: 880)
        let frame = CopyFeedbackPlacement.frame(in: screen)
        precondition(screen.contains(frame) && frame.minX == screen.minX + 12 && frame.minY == screen.minY + 12)
        print("PASS: overlay never becomes key/main, left-bottom placement handles negative display coordinates")
        let previews = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/copy-previews")
        try! FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)
        for (name, values) in [("ribbons", [String]()), ("single-emoji", ["🍏"]), ("multi-emoji", ["🍏", "✨", "🎉"])] {
            let render = ImageRenderer(content: CopyConfettiParticles(emoji: values, elapsed: 0.38).frame(width: 240, height: 180).background(Color.white))
            render.scale = 2
            let data = render.nsImage!.tiffRepresentation!
            try! NSBitmapImageRep(data: data)!.representation(using: .png, properties: [:])!.write(to: previews.appendingPathComponent(name + ".png"))
        }
        print("PASS: production particle renderer exported for ribbons and 1/multiple emoji visual acceptance")
    }
}
