import SwiftUI

@main
struct ChatLedgerApp: App {
    @StateObject private var shortcuts = KeyboardShortcuts.shared
    @StateObject private var store = LedgerStore()
    @StateObject private var floating = FloatingTodo()

    var body: some Scene {
        Window("轻随", id: "main") {
            ContentView().environmentObject(store).environmentObject(floating)
                .frame(minWidth: 240, minHeight: 320)
                .onAppear {
                    floating.restore(store: store)
                    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
                        NSApp.applicationIconImage = icon
                    }
                }
                .tint(Palette.accent)
                .focusEffectDisabled()
                .appAppearance()
        }
        .defaultSize(width: 1120, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { SettingsWindow.show() }.keyboardShortcut(shortcuts.binding(.settings).shortcut)
            }
            CommandGroup(after: .textEditing) {
                Button("搜索消息") { store.beginSearch() }.keyboardShortcut(shortcuts.binding(.search).shortcut)
            }
            CommandGroup(replacing: .newItem) { }
            CommandMenu("资料库") {
                Button("备份全部数据…") { store.chooseArchive(.backup) }.disabled(store.folder == nil || store.archiveBusy)
                Button("导出记录…") { store.chooseArchive(.export) }.disabled(store.folder == nil || store.archiveBusy)
            }
            CommandMenu("窗口工具") {
                Button("侧边窄条 / 展开") { WindowMode.toggle() }.keyboardShortcut(shortcuts.binding(.toggleRail).shortcut)
                Button("展开悬浮清单") { floating.presentList(store: store) }.keyboardShortcut(shortcuts.binding(.floatingTasks).shortcut)
                Button("新建待办") { focusFloating(.focusFloatingTask) }.keyboardShortcut(shortcuts.binding(.newTask).shortcut)
                Button("新建记事") { focusFloating(.focusFloatingNote) }.keyboardShortcut(shortcuts.binding(.newNote).shortcut)
                Button(floating.visible ? "隐藏悬浮球" : "显示悬浮球") { floating.toggle(store: store) }
            }
            CommandGroup(replacing: .help) {
                Button("使用说明") { UserGuideWindow.show() }.keyboardShortcut(shortcuts.binding(.guide).shortcut)
                Divider()
                Button("关于轻随") {
                    let alert = NSAlert()
                    alert.messageText = "轻随 · 把内容和事情放在一起"
                    alert.informativeText = "本地聊天记录、待办与日历。\n\n版本 0.7.0\n\n完整操作请点击窗口右上角“使用说明”，或在 Help 菜单打开。备份时复制整个资料库文件夹即可。"
                    alert.runModal()
                }
            }
        }
    }
    private func focusFloating(_ name: Notification.Name) {
        floating.presentList(store: store)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { NotificationCenter.default.post(name: name, object: nil) }
    }

}

