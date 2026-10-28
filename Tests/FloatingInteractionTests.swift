import AppKit
import SwiftUI

@main
@MainActor
struct FloatingInteractionTests {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let suite = "ChatLedger.Shortcuts.Test." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let shortcuts = KeyboardShortcuts(defaults: preferences)
        precondition(Set(ShortcutAction.allCases.map { shortcuts.binding($0).display }).count == 7)
        precondition(!shortcuts.set(.search, to: shortcuts.binding(.newNote)))
        precondition(shortcuts.binding(.search) == ShortcutAction.search.defaultBinding)
        precondition(!shortcuts.set(.search, to: .init(key: "c", modifiers: 1)))
        let custom = ShortcutBinding(key: "k", modifiers: 5)
        precondition(shortcuts.set(.search, to: custom))
        precondition(KeyboardShortcuts(defaults: preferences).binding(.search) == custom)
        shortcuts.reset()
        precondition(shortcuts.binding(.search) == ShortcutAction.search.defaultBinding)
        let keyEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0, windowNumber: 0, context: nil, characters: "K", charactersIgnoringModifiers: "K", isARepeat: false, keyCode: 40)!
        precondition(ShortcutBinding.capture(keyEvent) == .init(key: "k", modifiers: 3))
        print("PASS: shortcut uniqueness, conflict rejection, persistence, reset, event capture")
        let screen = NSRect(x: -1440, y: 20, width: 1440, height: 880)
        let centered = WindowPlacement.centered(size: NSSize(width: 1000, height: 700), in: screen)
        precondition(abs(centered.midX - screen.midX) < 0.1 && abs(centered.midY - screen.midY) < 0.1)
        let bounded = WindowPlacement.clamped(NSRect(x: -5000, y: 3000, width: 320, height: 2000), to: screen)
        precondition(screen.contains(bounded), "移动显示器后恢复窗口必须可见")
        let ordinary = SidebarRegions(height: 800, tagCount: 2)
        let crowded = SidebarRegions(height: 800, tagCount: 20)
        precondition(ordinary.tasks == crowded.tasks && crowded.tags > ordinary.tags && crowded.calendar < ordinary.calendar, "标签可挤压日历，不能挤大待办")
        for height in [320.0, 480, 800, 1200] {
            let regions = SidebarRegions(height: height, tagCount: 30)
            precondition(regions.tasks + regions.tags + regions.calendar + 98 <= height, "左栏布局必须有界")
        }
        let toggle = FloatingToggleControl(frame: NSRect(x: 0, y: 0, width: 72, height: 24))
        precondition(toggle.focusRingType == .none && !toggle.acceptsFirstResponder, "Toolbar toggle must not retain a blue focus rectangle")
        var toggled = 0
        toggle.onActivate = { toggled += 1 }
        toggle.performClick(nil); toggle.performClick(nil)
        precondition(toggled == 2, "Removing toolbar focus must preserve both toggle actions")
        let window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 48, height: 48), styleMask: [.borderless], backing: .buffered, defer: false)
        let host = FloatingHostingView(rootView: AnyView(GlassOrb()))
        host.sizingOptions = []
        precondition(host.focusRingType == .none && host.focusRingMaskBounds == .zero, "Floating host must not draw a rectangular focus ring")
        window.contentView = host
        host.isCollapsed = { true }
        var opened = 0
        host.activate = { opened += 1 }
        func event(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func drain() { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        precondition(host.hitTest(NSPoint(x: 24, y: 24)) === host, "Collapsed sphere must receive pointer events")
        precondition(!host.mouseDownCanMoveWindow, "System background dragging must not bypass click/drag classification")
        host.mouseDown(with: event(.leftMouseDown, NSPoint(x: 24, y: 24)))
        host.mouseUp(with: event(.leftMouseUp, NSPoint(x: 24, y: 24)))
        drain()
        precondition(opened == 1, "Click opens exactly once on mouse up")
        let old = window.frame.origin
        host.mouseDown(with: event(.leftMouseDown, NSPoint(x: 24, y: 24)))
        host.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: -76, y: 44)))
        precondition(abs(window.frame.minX - (old.x - 100)) < 0.1 && abs(window.frame.minY - (old.y + 20)) < 0.1, "Dragging must move the sphere")
        host.mouseUp(with: event(.leftMouseUp, NSPoint(x: 24, y: 24)))
        drain()
        precondition(opened == 1, "Dragging must never activate the list on release")
        host.mouseDown(with: event(.leftMouseDown, NSPoint(x: 24, y: 24)))
        host.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: 26, y: 24)))
        host.mouseUp(with: event(.leftMouseUp, NSPoint(x: 26, y: 24)))
        drain()
        precondition(opened == 2, "Small hand movement must still count as a click")
        precondition(host.accessibilityPerformPress(), "Accessible activation must be supported")
        drain()
        precondition(opened == 3, "Accessible press must open once")
        window.contentView = nil
        print("PASS: production sphere click, drag movement, no activation after drag, hand jitter tolerance, accessibility press")
    }
}
