import AppKit
import SwiftUI
import Combine

enum ShortcutAction: String, CaseIterable, Identifiable {
    case toggleRail, floatingTasks, newTask, newNote, search, settings, guide
    var id: String { rawValue }
    var title: String {
        switch self {
        case .toggleRail: return "收起 / 展开页面"
        case .floatingTasks: return "展开悬浮待办"
        case .newTask: return "新建待办"
        case .newNote: return "新建记事"
        case .search: return "搜索消息"
        case .settings: return "打开设置"
        case .guide: return "使用说明"
        }
    }
    var defaultBinding: ShortcutBinding {
        switch self {
        case .toggleRail: return .init(key: "m", modifiers: 3)
        case .floatingTasks: return .init(key: "t", modifiers: 3)
        case .newTask: return .init(key: "n", modifiers: 3)
        case .newNote: return .init(key: "j", modifiers: 3)
        case .search: return .init(key: "f", modifiers: 1)
        case .settings: return .init(key: ",", modifiers: 1)
        case .guide: return .init(key: "h", modifiers: 3)
        }
    }
}
struct ShortcutBinding: Codable, Equatable {
    var key: String
    // Command=1, Shift=2, Option=4, Control=8.
    var modifiers: Int
    var valid: Bool { key.count == 1 && "abcdefghijklmnopqrstuvwxyz0123456789,./;-=".contains(key) && modifiers & 13 != 0 && modifiers & ~15 == 0 }
    var eventModifiers: EventModifiers {
        var value: EventModifiers = []
        if modifiers & 1 != 0 { value.insert(.command) }; if modifiers & 2 != 0 { value.insert(.shift) }
        if modifiers & 4 != 0 { value.insert(.option) }; if modifiers & 8 != 0 { value.insert(.control) }
        return value
    }
    var shortcut: KeyboardShortcut { KeyboardShortcut(KeyEquivalent(key.first ?? "?"), modifiers: eventModifiers) }
    var display: String {
        (modifiers & 8 != 0 ? "⌃" : "") + (modifiers & 4 != 0 ? "⌥" : "") + (modifiers & 2 != 0 ? "⇧" : "") + (modifiers & 1 != 0 ? "⌘" : "") + key.uppercased()
    }
    static func capture(_ event: NSEvent) -> ShortcutBinding? {
        guard let key = event.charactersIgnoringModifiers?.lowercased(), key.count == 1 else { return nil }
        var modifiers = 0
        if event.modifierFlags.contains(.command) { modifiers |= 1 }; if event.modifierFlags.contains(.shift) { modifiers |= 2 }
        if event.modifierFlags.contains(.option) { modifiers |= 4 }; if event.modifierFlags.contains(.control) { modifiers |= 8 }
        let result = ShortcutBinding(key: key, modifiers: modifiers)
        return result.valid ? result : nil
    }
}
@MainActor final class KeyboardShortcuts: ObservableObject {
    static let shared = KeyboardShortcuts()
    @Published private(set) var bindings: [String: ShortcutBinding]
    @Published var error: String?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var result = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0.rawValue, $0.defaultBinding) })
        if let data = defaults.data(forKey: "keyboardShortcuts"), let saved = try? JSONDecoder().decode([String: ShortcutBinding].self, from: data) {
            var used = Set<String>()
            for action in ShortcutAction.allCases {
                let value = saved[action.rawValue] ?? action.defaultBinding
                let signature = value.display
                // Discard damaged settings instead of creating duplicate commands.
                if value.valid && !used.contains(signature) { result[action.rawValue] = value; used.insert(signature) }
                else { result = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0.rawValue, $0.defaultBinding) }); break }
            }
        }
        bindings = result
    }
    func binding(_ action: ShortcutAction) -> ShortcutBinding { bindings[action.rawValue] ?? action.defaultBinding }
    @discardableResult func set(_ action: ShortcutAction, to value: ShortcutBinding) -> Bool {
        guard value.valid else { error = "请使用 ⌘、⌥ 或 ⌃ 搭配字母、数字或标点。"; return false }
        if value.modifiers == 1 && ["q", "w", "c", "v", "x", "a", "z"].contains(value.key) { error = "这个组合键用于退出、关闭或文字编辑，请换一个。"; return false }
        if let other = ShortcutAction.allCases.first(where: { $0 != action && binding($0) == value }) { error = "已用于“\(other.title)”，请换一个组合键。"; return false }
        bindings[action.rawValue] = value; error = nil; persist(); return true
    }
    func reset() { bindings = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0.rawValue, $0.defaultBinding) }); error = nil; persist() }
    private func persist() { if let data = try? JSONEncoder().encode(bindings) { defaults.set(data, forKey: "keyboardShortcuts") } }
}

struct ShortcutRecorder: NSViewRepresentable {
    let binding: ShortcutBinding
    var record: (ShortcutBinding) -> Void
    func makeNSView(context: Context) -> RecorderButton { RecorderButton(frame: .zero) }
    func updateNSView(_ view: RecorderButton, context: Context) { view.record = record; view.value = binding; if !view.waiting { view.title = binding.display }; view.setAccessibilityLabel("修改快捷键，当前 " + binding.display) }
    final class RecorderButton: NSButton {
        var value = ShortcutBinding(key: "m", modifiers: 3)
        var record: (ShortcutBinding) -> Void = { _ in }
        var waiting = false
        private var monitor: Any?
        override var acceptsFirstResponder: Bool { true }
        override init(frame frameRect: NSRect) { super.init(frame: frameRect); configure() }
        required init?(coder: NSCoder) { super.init(coder: coder); configure() }
        private func configure() { bezelStyle = .rounded; focusRingType = .none; target = self; action = #selector(beginRecording); font = .monospacedSystemFont(ofSize: 12, weight: .medium) }
        @objc private func beginRecording() {
            stop(); waiting = true; title = "按下组合键…"; window?.makeFirstResponder(self)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.waiting else { return event }
                if event.keyCode == 53 { self.stop(); return nil }
                if let value = ShortcutBinding.capture(event) { self.stop(); self.record(value) }
                else { NSSound.beep() }
                return nil
            }
        }
        private func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; waiting = false; title = value.display }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { stop() } }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
extension Notification.Name {
    static let focusFloatingTask = Notification.Name("Qingsui.FocusFloatingTask")
    static let focusFloatingNote = Notification.Name("Qingsui.FocusFloatingNote")
}
