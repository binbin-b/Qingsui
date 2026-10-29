import AppKit
import SwiftUI

struct WindowPlacement {
    static func clamped(_ frame: NSRect, to screen: NSRect) -> NSRect {
        let width = min(max(240, frame.width), screen.width)
        let height = min(max(320, frame.height), screen.height)
        return NSRect(x: min(max(frame.minX, screen.minX), screen.maxX-width),
                      y: min(max(frame.minY, screen.minY), screen.maxY-height), width: width, height: height)
    }
    static func centered(size: NSSize, in screen: NSRect) -> NSRect {
        clamped(NSRect(x: screen.midX-size.width/2, y: screen.midY-size.height/2, width: size.width, height: size.height), to: screen)
    }
}

@MainActor
enum WindowMode {
    static var regularFrame: NSRect?
    static func toggle() {
        guard let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.title == "轻随" }) else { return }
        window.makeKeyAndOrderFront(nil)
        let defaults = UserDefaults.standard
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        if window.frame.width < 420 {
            defaults.set(NSStringFromRect(window.frame), forKey: "railFrame")
            let saved = defaults.string(forKey: "regularFrame").map(NSRectFromString)
            let size = saved?.size ?? regularFrame?.size ?? NSSize(width: 1120, height: 800)
            window.setFrame(WindowPlacement.centered(size: size, in: screen), display: true, animate: true)
        } else {
            regularFrame = window.frame
            defaults.set(NSStringFromRect(window.frame), forKey: "regularFrame")
            let frame: NSRect
            if let saved = defaults.string(forKey: "railFrame") {
                frame = WindowPlacement.clamped(NSRectFromString(saved), to: screen)
            } else {
                let left = window.frame.midX < screen.midX
                let height = min(window.frame.height, screen.height)
                frame = WindowPlacement.clamped(NSRect(x: left ? screen.minX : screen.maxX-320, y: window.frame.minY, width: 320, height: height), to: screen)
            }
            window.setFrame(frame, display: true, animate: true)
        }
        apply(window)
    }
    static func remember(_ window: NSWindow) {
        let value = NSStringFromRect(window.frame)
        let defaults = UserDefaults.standard
        defaults.set(value, forKey: "lastMainFrame")
        defaults.set(value, forKey: window.frame.width < 420 ? "railFrame" : "regularFrame")
        if window.frame.width >= 420 { regularFrame = window.frame }
    }
    static func restore(_ window: NSWindow) {
        guard let value = UserDefaults.standard.string(forKey: "lastMainFrame") else { apply(window); return }
        let frame = NSRectFromString(value)
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        window.setFrame(WindowPlacement.clamped(frame, to: screen), display: true)
        apply(window)
    }
    static func apply(_ window: NSWindow) {
        // The main chat window always follows normal macOS stacking, including in rail mode.
        if window.level != .normal { window.level = .normal }
        if window.collectionBehavior != [.managed] { window.collectionBehavior = [.managed] }
    }
}
struct WindowModeObserver: NSViewRepresentable {
    func makeNSView(context: Context) -> ObserverView { ObserverView() }
    func updateNSView(_ view: ObserverView, context: Context) { }
    final class ObserverView: NSView {
        private var tokens: [NSObjectProtocol] = []
        private var pending: DispatchWorkItem?
        private weak var restoredWindow: NSWindow?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for token in tokens { NotificationCenter.default.removeObserver(token) }; tokens = []
            guard let window else { return }
            window.isOpaque = false; window.backgroundColor = .clear; window.titlebarAppearsTransparent = true
            if restoredWindow !== window {
                restoredWindow = window
                DispatchQueue.main.async { [weak window] in if let window { WindowMode.restore(window) } }
            }
            for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
                tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                    MainActor.assumeIsolated {
                        guard let self, let window else { return }
                        WindowMode.apply(window)
                        self.pending?.cancel()
                        let save = DispatchWorkItem { [weak window] in if let window { WindowMode.remember(window) } }
                        self.pending = save
                        DispatchQueue.main.asyncAfter(deadline: .now()+0.25, execute: save)
                    }
                })
            }
        }
        deinit { pending?.cancel(); for token in tokens { NotificationCenter.default.removeObserver(token) } }
    }
}
