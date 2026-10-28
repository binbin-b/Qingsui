import AppKit
import SwiftUI

final class TodoPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingTodo: ObservableObject {
    private var panel: TodoPanel?
    private var closeWork: DispatchWorkItem?
    private var openWork: DispatchWorkItem?
    private var pointerDown = false
    private var keyboardOpen = false
    @Published var expanded = false
    @Published var visible = false
    private var store: LedgerStore?
    private var mainWindow: NSWindow?

    func restore(store: LedgerStore) {
        if UserDefaults.standard.object(forKey: "floatingTodoEnabled") as? Bool != false { show(store: store) }
    }
    func show(store: LedgerStore) {
        self.store = store
        if mainWindow == nil {
            mainWindow = NSApp.windows.first { !($0 is NSPanel) && $0.title == "轻随" }
            mainWindow?.isReleasedWhenClosed = false
        }
        if panel == nil {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            let panel = TodoPanel(contentRect: NSRect(x: screen.maxX - 100, y: screen.midY, width: 68, height: 68),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "轻随待办"
            panel.acceptsMouseMovedEvents = true
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = expanded
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            let hosting = FloatingHostingView(rootView: AnyView(FloatingTodoView(controller: self).environmentObject(store)))
            hosting.sizingOptions = []
            hosting.isCollapsed = { [weak self] in self?.expanded == false }
            hosting.activate = { [weak self] in self?.expand() }
            hosting.pressBegan = { [weak self] in self?.pointerDown = true; self?.openWork?.cancel() }
            hosting.pressEnded = { [weak self] dragged in
                self?.pointerDown = false
                if dragged { self?.hover(true) }
            }
            hosting.hover = { [weak self] inside in
                DispatchQueue.main.async { self?.hover(inside) }
            }
            panel.contentView = hosting
            self.panel = panel
        }
        panel?.orderFrontRegardless(); visible = true
        UserDefaults.standard.set(true, forKey: "floatingTodoEnabled")
    }
    func presentList(store: LedgerStore) {
        show(store: store)
        expand()
        keyboardOpen = true
        panel?.makeKeyAndOrderFront(nil)
    }
    func toggle(store: LedgerStore) {
        if visible { closeWork?.cancel(); openWork?.cancel(); panel?.orderOut(nil); visible = false }
        else { show(store: store) }
        UserDefaults.standard.set(visible, forKey: "floatingTodoEnabled")
    }
    func expand() {
        closeWork?.cancel(); openWork?.cancel(); keyboardOpen = false; resize(true)
    }
    func hover(_ inside: Bool) {
        closeWork?.cancel(); openWork?.cancel()
        guard visible, !pointerDown else { return }
        if !expanded {
            guard inside else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.visible, !self.pointerDown else { return }
                self.expand()
            }
            openWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
        } else if !inside && !keyboardOpen {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.panel?.isKeyWindow == true, let editor = self.panel?.firstResponder as? NSTextView, editor.isEditable { return }
                self.resize(false)
            }
            closeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }
    private func resize(_ expand: Bool) {
        guard let panel, expanded != expand else { return }
        let old = panel.frame
        let size = expand ? NSSize(width: 300, height: 440) : NSSize(width: 68, height: 68)
        var frame = NSRect(x: old.maxX - size.width, y: old.maxY - size.height, width: size.width, height: size.height)
        if let screen = panel.screen?.visibleFrame {
            frame.origin.x = max(screen.minX, min(frame.origin.x, screen.maxX - size.width))
            frame.origin.y = max(screen.minY, min(frame.origin.y, screen.maxY - size.height))
        }
        expanded = expand
        panel.hasShadow = expand
        if !expand { panel.makeFirstResponder(nil) }
        panel.setFrame(frame, display: true)
    }
    func collapse() {
        keyboardOpen = false; closeWork?.cancel(); openWork?.cancel(); resize(false)
    }
    func openMain() {
        collapse()
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow ?? NSApp.windows.first(where: { !($0 is NSPanel) && $0.title == "轻随" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

struct FloatingTodoView: View {
    @ObservedObject var controller: FloatingTodo
    @State private var showCompleted = false
    @State private var noteText = ""
    @State private var noteHeight: CGFloat = 28
    @State private var noteAttachments: [DraftAttachment] = []
    @EnvironmentObject var store: LedgerStore
    var body: some View {
        Group {
            if controller.expanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("待办").font(.system(size: 13, weight: .semibold)).absorptionAnchor("taskList")
                        Spacer()
                        Button { controller.collapse() } label: { Image(systemName: "minus") }.buttonStyle(.plain).help("收起")
                        Button { controller.openMain() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                            .buttonStyle(.plain).help("打开主窗口")
                    }
                    if store.folder == nil {
                        Button("选择资料库") { controller.openMain(); store.chooseFolder() }
                        Spacer()
                    } else {
                        QuickTaskEntry(floatingShortcutTarget: true)
                        if let error = store.errorMessage {
                            Text(error).font(.system(size: 10)).foregroundStyle(.red).lineLimit(3)
                        }
                        GeometryReader { geometry in
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    ForEach(store.library.tasks.filter { !store.library.isComplete($0.id) || store.finishingTasks.contains($0.id) }.sorted {
                                        let a = store.library.isComplete($0.id), b = store.library.isComplete($1.id)
                                        return a != b ? !a : $0.createdAt > $1.createdAt
                                    }) { task in
                                        CompactTaskRow(task: task, open: { controller.openMain() })
                                    }
                                    let completed = store.library.tasks.filter { store.library.isComplete($0.id) && !store.finishingTasks.contains($0.id) }
                                    if !completed.isEmpty {
                                        Button { showCompleted.toggle() } label: {
                                            Label("已完成 \(completed.count)", systemImage: showCompleted ? "chevron.down" : "chevron.right").font(.caption).foregroundStyle(.secondary)
                                        }.buttonStyle(.plain)
                                        if showCompleted { ForEach(completed) { task in CompactTaskRow(task: task, open: { controller.openMain() }) } }
                                    }
                                }.frame(maxWidth: .infinity).frame(minHeight: geometry.size.height, alignment: .top)
                                    .background(collapseArea)
                            }
                        }
                        Divider()
                        QuickNoteEntry(text: $noteText, height: $noteHeight, attachments: $noteAttachments)
                    }
                }.padding(12).frame(width: 300, height: 440)
                    .background(collapseArea)
                    .ledgerGlass(radius: 24)
            } else {
                GlassOrb().focusEffectDisabled().help("单击或停留片刻展开 · 按住拖动移动")
            }
        }.overlayPreferenceValue(AbsorptionAnchorKey.self) { anchors in
            if controller.expanded { AbsorptionFeedback(anchors: anchors) }
        }.overlay {
            if controller.expanded { ReminderOverlay(open: { controller.openMain() }) }
        }.onExitCommand { controller.collapse() }.tint(Palette.accent).appAppearance()
    }
    private var collapseArea: some View {
        Color.clear.contentShape(Rectangle()).onTapGesture(count: 2) { controller.collapse() }
    }

}

struct GlassOrb: View {
    private static let artwork: NSImage? = Bundle.main.url(forResource: "FloatingOrb", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    var body: some View {
        Group {
            if let artwork = Self.artwork {
                Image(nsImage: artwork).resizable().interpolation(.high)
                    .frame(width: 81, height: 81).offset(x: 0.06, y: 2.07)
                    .frame(width: 60, height: 60).clipShape(Circle())
            } else {
                Circle().fill(Color.mint.opacity(0.6))
                    .overlay(Circle().stroke(.white, lineWidth: 1.3).frame(width: 13, height: 13))
                    .frame(width: 60, height: 60)
            }
        }.frame(width: 68, height: 68).accessibilityHidden(true)
    }
}

final class FloatingHostingView: NSHostingView<AnyView> {
    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        focusRingType = .none
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        focusRingType = .none
    }
    override var focusRingMaskBounds: NSRect { .zero }
    override func drawFocusRingMask() { }
    var hover: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?
    var isCollapsed: (() -> Bool)?
    var activate: (() -> Void)?
    var pressBegan: (() -> Void)?
    var pressEnded: ((Bool) -> Void)?
    private var pressPoint: NSPoint?
    private var pressOrigin: NSPoint?
    private var dragged = false
    override var mouseDownCanMoveWindow: Bool { isCollapsed?() != true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        if isCollapsed?() == true && bounds.contains(point) { return self }
        return super.hitTest(point)
    }
    override func accessibilityRole() -> NSAccessibility.Role? {
        isCollapsed?() == true ? .button : super.accessibilityRole()
    }
    override func accessibilityLabel() -> String? {
        isCollapsed?() == true ? "青绿色悬浮球，单击或停留展开待办，按住可拖动" : super.accessibilityLabel()
    }
    override func isAccessibilityElement() -> Bool {
        isCollapsed?() == true || super.isAccessibilityElement()
    }
    override func accessibilityPerformPress() -> Bool {
        guard isCollapsed?() == true else { return super.accessibilityPerformPress() }
        DispatchQueue.main.async { [weak self] in self?.activate?() }
        return true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard hoverArea == nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        hoverArea = area
        addTrackingArea(area)
    }
    override func mouseEntered(with event: NSEvent) { hover?(true) }
    override func mouseExited(with event: NSEvent) { hover?(false) }
    override func mouseDown(with event: NSEvent) {
        guard isCollapsed?() == true, let window else { super.mouseDown(with: event); return }
        pressBegan?()
        pressPoint = window.convertPoint(toScreen: event.locationInWindow)
        pressOrigin = window.frame.origin
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, let start = pressPoint, let origin = pressOrigin else { super.mouseDragged(with: event); return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        let dx = point.x - start.x, dy = point.y - start.y
        if hypot(dx, dy) > 4 { dragged = true }
        if dragged { window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy)) }
    }
    override func mouseUp(with event: NSEvent) {
        guard pressPoint != nil else { super.mouseUp(with: event); return }
        let shouldOpen = !dragged
        pressPoint = nil; pressOrigin = nil; dragged = false
        pressEnded?(!shouldOpen)
        if shouldOpen { DispatchQueue.main.async { [weak self] in self?.activate?() } }
    }
}

struct QuickNoteEntry: View {
    @State private var focusRequest = 0
    @EnvironmentObject var store: LedgerStore
    @Binding var text: String
    @Binding var height: CGFloat
    @Binding var attachments: [DraftAttachment]
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("快速记事", systemImage: "square.and.pencil").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            if !attachments.isEmpty { Text("\(attachments.count) 个附件").font(.caption2).foregroundStyle(.secondary) }
            HStack(alignment: .bottom, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty { Text("记下来，Enter 发送到主页面").font(.system(size: 12)).foregroundStyle(.tertiary).padding(.top, 5).padding(.leading, 4).allowsHitTesting(false) }
                    MessageEditor(text: $text, height: $height, onFiles: { attachments += $0.map(LedgerStore.draft) }, onImage: { data in
                        attachments.append(DraftAttachment(name: "记事图片.png", sourceURL: nil, data: data, isImage: true))
                    }, onReturn: send, onNavigation: { _ in false }, focusRequest: focusRequest, accessibilityName: "快速记事输入框").frame(height: min(70, height))
                }
                Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 20)).frame(width: 25, height: 28) }
                    .buttonStyle(.plain).foregroundStyle(Palette.accent).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty).help("发送记事到主页面")
            }.padding(6).ledgerGlass(radius: 12)
                .onReceive(NotificationCenter.default.publisher(for: .focusFloatingNote)) { _ in focusRequest += 1 }
        }
    }
    private func send() {
        if store.send(text: text, taskID: nil, newTaskTitle: nil, drafts: attachments) {
            text = ""; attachments = []; height = 28
            store.filter = .all; store.searchQuery = ""; store.searchPresented = false
        }
    }
}
