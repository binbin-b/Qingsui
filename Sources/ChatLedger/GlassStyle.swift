import AppKit
import SwiftUI

extension View {
    @ViewBuilder
    func ledgerGlass(radius: CGFloat = 18, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint), in: RoundedRectangle(cornerRadius: radius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
                .background(tint?.opacity(0.25) ?? .clear, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(Palette.glassEdge, lineWidth: 0.7))
        }
    }
}

struct DesktopGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { }
}

struct DueReminderBanner: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sway: CGFloat = 0
    var open: (() -> Void)?
    var body: some View {
        if let task = store.dueReminder {
            Button {
                store.acknowledgeDueReminder(); open?()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 21)).foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                        if let date = task.dueDate {
                            Text(date, format: .dateTime.month().day()).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }.padding(14).frame(maxWidth: 300)
                    .ledgerGlass(radius: 24, tint: .orange.opacity(0.10))
                    .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
            }.buttonStyle(.plain).offset(x: sway)
                .accessibilityLabel("到期提醒，" + task.title + "，点击确认并查看")
                .help("点击确认提醒并查看关联内容，待办仍保持未完成")
                .task(id: task.id.uuidString + String(task.dueDate?.timeIntervalSinceReferenceDate ?? 0)) {
                    sway = 0
                    guard !reduceMotion else { return }
                    for position: CGFloat in [-4, 4, -3, 3, 0] {
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.10)) { sway = position }
                        do { try await Task.sleep(for: .milliseconds(110)) } catch { return }
                    }
                }
        }
    }
}

struct ReminderOverlay: View {
    @EnvironmentObject var store: LedgerStore
    var open: (() -> Void)?
    var body: some View {
        VStack {
            DueReminderBanner(open: open).padding(.horizontal, 12).padding(.top, 40)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity)
    }
}

enum Palette {
    private static func adaptive(_ name: String, day: NSColor, night: NSColor) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name(name)) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? night : day
        })
    }
    static let accent = adaptive("LedgerAccent", day: NSColor(calibratedRed: 0.16, green: 0.43, blue: 0.37, alpha: 1), night: NSColor(calibratedRed: 0.41, green: 0.84, blue: 0.68, alpha: 1))
    static let canvas = adaptive("LedgerCanvas", day: NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.98, alpha: 1), night: NSColor(calibratedWhite: 0.025, alpha: 1))
    static let sidebar = adaptive("LedgerSidebar", day: NSColor(calibratedWhite: 0.94, alpha: 1), night: NSColor(calibratedWhite: 0.06, alpha: 1))
    static let pending = adaptive("LedgerPending", day: NSColor(calibratedRed: 0.76, green: 0.91, blue: 0.70, alpha: 1), night: NSColor(calibratedRed: 0.08, green: 0.25, blue: 0.18, alpha: 1))
    static let processed = adaptive("LedgerProcessed", day: NSColor(calibratedWhite: 0.925, alpha: 1), night: NSColor(calibratedWhite: 0.15, alpha: 1))
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let glassEdge = adaptive("LedgerGlassEdge", day: NSColor.white.withAlphaComponent(0.65), night: NSColor.white.withAlphaComponent(0.12))
    static let fileCard = adaptive("LedgerFileCard", day: NSColor.white.withAlphaComponent(0.7), night: NSColor(calibratedWhite: 0.06, alpha: 0.72))
    static let onAccent = adaptive("LedgerOnAccent", day: .white, night: .black)
}
