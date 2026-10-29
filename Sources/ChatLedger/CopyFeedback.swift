import AppKit
import ApplicationServices
import SwiftUI
import Combine

@MainActor
final class CopyFeedback: ObservableObject {
    static let shared = CopyFeedback()
    @Published var enabled: Bool { didSet { changed(restart: true) } }
    @Published var globalEnabled: Bool { didSet { changed(restart: true) } }
    @Published var effect: CopyFeedbackEffect { didSet { changed() } }
    @Published var content: CopyConfettiContent { didSet { changed() } }
    @Published private(set) var emoji: String
    @Published private(set) var trusted = false
    @Published private(set) var globalListening = false
    private let defaults: UserDefaults
    private let pasteboard: NSPasteboard
    private let onCopy: (() -> Void)?
    private var tracker: CopyAttemptTracker
    private var started = false
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var permissionObserver: NSObjectProtocol?
    private var baselineTimer: Timer?
    private var permissionTimer: Timer?
    private var pollTask: Task<Void, Never>?
    private var panel: CopyFeedbackPanel?
    private var hideWork: DispatchWorkItem?
    private var lastPresentation: TimeInterval = -.infinity

    init(defaults: UserDefaults = .standard, pasteboard: NSPasteboard = .general, onCopy: (() -> Void)? = nil) {
        self.defaults = defaults; self.pasteboard = pasteboard; self.onCopy = onCopy
        enabled = defaults.bool(forKey: "copyFeedbackEnabled")
        globalEnabled = defaults.bool(forKey: "copyFeedbackGlobal")
        effect = CopyFeedbackEffect(rawValue: defaults.string(forKey: "copyFeedbackEffect") ?? "") ?? .confetti
        content = CopyConfettiContent(rawValue: defaults.string(forKey: "copyConfettiContent") ?? "") ?? .ribbons
        let saved = defaults.string(forKey: "copyFeedbackEmoji") ?? "🍏 ✨"
        emoji = EmojiSelection.error(saved) == nil ? saved : "🍏 ✨"
        tracker = CopyAttemptTracker(count: pasteboard.changeCount, now: ProcessInfo.processInfo.systemUptime)
    }
    func start() {
        guard !started else { return }
        started = true
        permissionObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermission() }
        }
        reconfigure()
    }
    private func changed(restart: Bool = false) {
        defaults.set(enabled, forKey: "copyFeedbackEnabled")
        defaults.set(globalEnabled, forKey: "copyFeedbackGlobal")
        defaults.set(effect.rawValue, forKey: "copyFeedbackEffect")
        defaults.set(content.rawValue, forKey: "copyConfettiContent")
        if started && restart { reconfigure() }
    }
    @discardableResult func saveEmoji(_ input: String) -> Bool {
        guard EmojiSelection.error(input) == nil else { return false }
        emoji = EmojiSelection.values(input).joined(separator: " ")
        defaults.set(emoji, forKey: "copyFeedbackEmoji")
        return true
    }
    func openPermissionSettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    func refreshPermission() {
        let value = AXIsProcessTrusted()
        if trusted != value { trusted = value; if started { reconfigure() } }
    }
    private func reconfigure() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }; localMonitor = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }; globalMonitor = nil
        baselineTimer?.invalidate(); baselineTimer = nil
        permissionTimer?.invalidate(); permissionTimer = nil
        pollTask?.cancel(); pollTask = nil
        tracker = CopyAttemptTracker(count: pasteboard.changeCount, now: ProcessInfo.processInfo.systemUptime)
        trusted = AXIsProcessTrusted(); globalListening = false
        guard enabled else { hide(); return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event, global: false) }
            return event // Never swallow, rewrite or replace the user's shortcut.
        }
        if globalEnabled && trusted {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated { self?.receive(event, global: true) }
            }
            globalListening = globalMonitor != nil
            // Low-frequency metadata baseline handles asynchronous global event delivery.
            baselineTimer = timer(interval: 0.12) { [weak self] in self?.sample() }
        }
        if globalEnabled {
            permissionTimer = timer(interval: 2) { [weak self] in self?.refreshPermission() }
        }
    }
    private func timer(interval: TimeInterval, action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { action() } }
        timer.tolerance = interval * 0.15
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
    static func isCopy(_ event: NSEvent) -> Bool {
        event.type == .keyDown && !event.isARepeat &&
        event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command &&
        event.charactersIgnoringModifiers?.lowercased() == "c"
    }
    func receive(_ event: NSEvent, global: Bool) {
        guard enabled, Self.isCopy(event) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        tracker.arm(count: pasteboard.changeCount, eventTime: event.timestamp, now: now, global: global)
        pollTask?.cancel()
        sample()
        guard tracker.pending else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
                guard let self, self.enabled else { return }
                self.sample()
                if !self.tracker.pending { return }
            }
        }
    }
    private func sample() {
        let hasTypes = tracker.pending && !(pasteboard.types ?? []).isEmpty
        if tracker.observe(count: pasteboard.changeCount, hasTypes: hasTypes, now: ProcessInfo.processInfo.systemUptime) {
            if let onCopy { onCopy() } else { present() }
        }
    }
    func preview() { present() }
    private func present() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPresentation >= 0.7 else { return }
        lastPresentation = now
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return }
        let frame = CopyFeedbackPlacement.frame(in: screen.visibleFrame)
        if panel == nil {
            let panel = CopyFeedbackPanel.make(frame: frame)
            self.panel = panel
        }
        guard let panel else { return }
        hideWork?.cancel()
        panel.setFrame(frame, display: false)
        let brief = effect == .brief || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let host = NSHostingView(rootView: CopyBurstView(brief: brief, emoji: content == .emoji ? EmojiSelection.values(emoji) : []).appAppearance())
        host.sizingOptions = []
        panel.contentView = host
        panel.orderFrontRegardless()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (brief ? 0.85 : 0.75), execute: work)
    }
    private func hide() { hideWork?.cancel(); hideWork = nil; panel?.orderOut(nil); panel?.contentView = nil }
    deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let permissionObserver { NotificationCenter.default.removeObserver(permissionObserver) }
        baselineTimer?.invalidate(); permissionTimer?.invalidate(); pollTask?.cancel(); hideWork?.cancel()
    }
}

final class CopyFeedbackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    static func make(frame: NSRect) -> CopyFeedbackPanel {
        let panel = CopyFeedbackPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "复制反馈"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .statusBar; panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        return panel
    }
}
struct CopyFeedbackPlacement {
    static func frame(in visible: NSRect) -> NSRect {
        NSRect(x: visible.minX + 12, y: visible.minY + 12, width: min(240, visible.width - 24), height: min(180, visible.height - 24))
    }
}
private struct CopyBurstView: View {
    let brief: Bool
    let emoji: [String]
    private let start = Date()
    var body: some View {
        Group {
            if brief {
                VStack {
                    Spacer()
                    HStack {
                        Label("已复制", systemImage: "checkmark.circle.fill").font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.accent).padding(.horizontal, 12).padding(.vertical, 9).ledgerGlass(radius: 16)
                        Spacer()
                    }
                }.padding(8)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
                    CopyConfettiParticles(emoji: emoji, elapsed: timeline.date.timeIntervalSince(start))
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct CopyConfettiParticles: View {
    let emoji: [String]
    let elapsed: TimeInterval
    private let colors: [Color] = [.mint, .green, .teal, Color(red: 0.8, green: 0.9, blue: 0.45), Color(red: 1, green: 0.78, blue: 0.55)]
    var body: some View {
        Canvas { context, size in
            let t = min(0.75, max(0, elapsed))
            let count = emoji.isEmpty ? 28 : 12
            for index in 0..<count {
                let seed = Double((index * 37 + 11) % 101) / 100
                let vx = 30 + seed * 265
                let vy = -150 - Double((index * 47) % 220)
                let point = CGPoint(x: 26 + vx * t, y: size.height - 18 + vy * t + 210 * t * t)
                var particle = context
                particle.opacity = max(0, 1 - pow(t / 0.75, 2))
                particle.translateBy(x: point.x, y: point.y)
                particle.rotate(by: .degrees(Double(index * 41) + t * 180))
                if emoji.isEmpty {
                    particle.fill(Path(roundedRect: CGRect(x: -2, y: -4, width: 4, height: 8), cornerRadius: 1), with: .color(colors[index % colors.count]))
                } else {
                    particle.draw(Text(emoji[index % emoji.count]).font(.system(size: 15 + seed * 7)), at: .zero)
                }
            }
        }
    }
}
