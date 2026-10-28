import SwiftUI
import AppKit

enum InterfaceTheme: String, CaseIterable, Identifiable {
    case liquidGlass
    var id: String { rawValue }
    var title: String { "液态玻璃" }
}
enum DisplayMode: String, CaseIterable, Identifiable {
    case day, night
    var id: String { rawValue }
    var title: String { self == .day ? "日间" : "夜间" }
    var scheme: ColorScheme { self == .day ? .light : .dark }
    var appearance: NSAppearance { NSAppearance(named: self == .day ? .aqua : .darkAqua)! }
}

struct AppAppearance: ViewModifier {
    @AppStorage("displayMode") private var mode = DisplayMode.day
    func body(content: Content) -> some View {
        content.preferredColorScheme(mode.scheme).background(AppearanceBridge(mode: mode))
    }
}
private struct AppearanceBridge: NSViewRepresentable {
    let mode: DisplayMode
    func makeNSView(context: Context) -> AppearanceView { AppearanceView() }
    func updateNSView(_ view: AppearanceView, context: Context) { view.mode = mode; view.applyAppearance() }
    final class AppearanceView: NSView {
        var mode = DisplayMode.day
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); applyAppearance() }
        func applyAppearance() { if window?.appearance?.name != mode.appearance.name { window?.appearance = mode.appearance } }
    }
}
extension View { func appAppearance() -> some View { modifier(AppAppearance()) } }

@MainActor enum SettingsWindow {
    private static var window: NSWindow?
    static func show() {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 620), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            panel.title = "设置"; panel.minSize = NSSize(width: 400, height: 420); panel.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: SettingsPanel().appAppearance()); host.sizingOptions = []
            panel.contentView = host; panel.center(); window = panel
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
}
struct SettingsPanel: View {
    @ObservedObject private var shortcuts = KeyboardShortcuts.shared
    @AppStorage("interfaceTheme") private var theme = InterfaceTheme.liquidGlass
    @AppStorage("displayMode") private var mode = DisplayMode.day
    var body: some View {
        Form {
            Section("主题") {
                Picker("界面风格", selection: $theme) { ForEach(InterfaceTheme.allCases) { Text($0.title).tag($0) } }
            }
            Section("模式") {
                Picker("明暗", selection: $mode) { ForEach(DisplayMode.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            }
            Section("键盘快捷键") {
                Text("在轻随处于前台时生效。点击组合键后按新快捷键，Esc 取消。").font(.caption).foregroundStyle(.secondary)
                ForEach(ShortcutAction.allCases) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        ShortcutRecorder(binding: shortcuts.binding(action)) { shortcuts.set(action, to: $0) }.frame(width: 125, height: 28)
                    }
                }
                if let error = shortcuts.error { Text(error).font(.caption).foregroundStyle(.red) }
                Button("恢复默认快捷键") { shortcuts.reset() }
            }
        }.formStyle(.grouped).padding(8).frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
    }
}
