import SwiftUI

struct AbsorptionAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
    static func day(_ date: Date) -> String { "calendar." + String(Calendar.current.startOfDay(for: date).timeIntervalSinceReferenceDate) }
}

extension View {
    func absorptionAnchor(_ name: String) -> some View {
        anchorPreference(key: AbsorptionAnchorKey.self, value: .bounds) { [name: $0] }
    }
}

struct AbsorptionFeedback: View {
    @EnvironmentObject var store: LedgerStore
    let anchors: [String: Anchor<CGRect>]
    var body: some View {
        GeometryReader { geometry in
            if let notice = store.taskNotice {
                let sourceNames = notice.messageID.map { ["message." + $0.uuidString, "composer"] } ?? ["quickEntry"]
                let targetNames = (notice.dueDate.map { [AbsorptionAnchorKey.day($0), "calendar"] } ?? []) + ["task." + notice.taskID.uuidString, "taskList", "floatingToggle"]
                let source = sourceNames.compactMap { anchors[$0] }.first.map { geometry[$0] }
                let target = targetNames.compactMap { anchors[$0] }.first.map { geometry[$0] }
                if let source, let target {
                    AbsorptionFlight(notice: notice,
                        start: CGPoint(x: min(max(source.midX, 30), geometry.size.width - 30), y: min(max(source.midY, 44), geometry.size.height - 30)),
                        end: CGPoint(x: target.midX, y: target.midY))
                        .id(notice.id)
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
            .task(id: store.taskNotice?.id) {
                guard let id = store.taskNotice?.id else { return }
                do { try await Task.sleep(for: .milliseconds(950)) } catch { return }
                store.dismissTaskNotice(id)
            }
    }
}

private struct AbsorptionFlight: View {
    let notice: TaskSavedNotice
    let start: CGPoint
    let end: CGPoint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var arrived = false
    var body: some View {
        ZStack {
            FlyingInformation(title: notice.title, dated: notice.dueDate != nil,
                start: start, end: end, progress: progress)
                .opacity(reduceMotion ? 0 : 1)
            if arrived { AbsorptionPulse().position(end) }
        }.task {
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            if reduceMotion { arrived = true; return }
            withAnimation(.easeInOut(duration: 0.72)) { progress = 1 }
            do { try await Task.sleep(for: .milliseconds(620)) } catch { return }
            arrived = true
        }
    }
}

private struct AbsorptionPulse: View {
    @State private var expanded = false
    var body: some View {
        Circle().stroke(Palette.accent.opacity(0.7), lineWidth: 2)
            .frame(width: 28, height: 28).scaleEffect(expanded ? 1.5 : 0.5)
            .opacity(expanded ? 0 : 0.75)
            .task { withAnimation(.easeOut(duration: 0.28)) { expanded = true } }
    }
}

private struct FlyingInformation: View, Animatable {
    let title: String
    let dated: Bool
    let start: CGPoint
    let end: CGPoint
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    var body: some View {
        let t = progress
        let control = CGPoint(x: start.x + (end.x - start.x) * 0.25, y: min(start.y, end.y) - 65)
        let x = (1-t)*(1-t)*start.x + 2*(1-t)*t*control.x + t*t*end.x
        let y = (1-t)*(1-t)*start.y + 2*(1-t)*t*control.y + t*t*end.y
        HStack(spacing: 6) {
            Image(systemName: dated ? "calendar" : "checklist")
            Text(title).lineLimit(1)
        }.font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
            .padding(.horizontal, 12).padding(.vertical, 9).frame(maxWidth: 170)
            .background(Palette.pending.opacity(0.96), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.8), lineWidth: 1))
            .shadow(color: Palette.accent.opacity(0.12), radius: 7, y: 3)
            .scaleEffect(1 - 0.88 * t)
            .opacity(t < 0.78 ? 1 : Double((1 - t) / 0.22))
            .position(x: x, y: y)
    }
}
