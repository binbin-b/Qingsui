import SwiftUI

struct CompactTaskRow: View {
    @EnvironmentObject var store: LedgerStore
    let task: LedgerTask
    var open: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dispersing = false
    @State private var particleProgress: CGFloat = 0

    var body: some View {
        let complete = store.library.isComplete(task.id)
        let progress = store.library.progress(for: task.id)
        HStack(spacing: 8) {
            Button { store.toggleTask(task.id) } label: {
                Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(complete ? Color.green : Palette.accent)
            }.buttonStyle(.plain).help(complete ? "撤销完成" : "完成整个待办及其关联消息")
            Button {
                store.filter = .task(task.id); open?()
            } label: {
                HStack(spacing: 6) {
                    Text(task.title).lineLimit(2).strikethrough(complete)
                    Spacer(minLength: 2)
                    if let due = task.dueDate {
                        Text(due, format: .dateTime.month().day()).font(.system(size: 10, weight: .medium))
                            .foregroundStyle(complete ? .gray : Color(red: 0.72, green: 0.34, blue: 0.12))
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(complete ? Color.gray.opacity(0.08) : Color.orange.opacity(0.16), in: Capsule())
                    }
                    if progress.total > 0 {
                        Text("\(progress.done)/\(progress.total)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(complete ? .secondary : .primary)
        }.font(.system(size: 12)).padding(.vertical, 10).padding(.horizontal, 12)
            .ledgerGlass(radius: 22, tint: store.filter == .task(task.id) ? Palette.accent.opacity(0.12) : nil)
            .opacity(dispersing ? 0 : (complete ? 0.55 : 1))
            .overlay {
                if dispersing && !reduceMotion {
                    CompletionFragments(progress: particleProgress).allowsHitTesting(false)
                }
            }
            .task(id: store.finishingTasks.contains(task.id)) {
                dispersing = false; particleProgress = 0
                guard store.finishingTasks.contains(task.id) else { return }
                do { try await Task.sleep(for: .milliseconds(330)) } catch { return }
                dispersing = true
                do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
                withAnimation(.easeOut(duration: 0.65)) { particleProgress = 1 }
            }
            .absorptionAnchor("task." + task.id.uuidString)
    }
}

struct QuickTaskEntry: View {
    var floatingShortcutTarget = false
    @FocusState private var entryFocused: Bool
    @EnvironmentObject var store: LedgerStore
    @State private var title = ""
    @State private var date: Date?
    @State private var dateError: String?
    var dateMention: DateMention? { DateMention.parse(title) }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                TextField("新待办", text: $title).textFieldStyle(.plain).focused($entryFocused).onSubmit(create)
                    .accessibilityLabel("新建独立待办")
                if let date {
                    Button { self.date = nil } label: { Text(date, format: .dateTime.month().day()).font(.system(size: 10)) }.buttonStyle(.plain)
                }
                Button(action: create) { Image(systemName: "plus") }.buttonStyle(.plain).disabled(title.isEmpty)
            }.font(.system(size: 12)).padding(10).ledgerGlass(radius: 18)
            if let mention = dateMention {
                DueDatePicker(query: mention.query, error: dateError) { day in
                    date = day; title.removeSubrange(mention.range); dateError = nil
                }
            }
            if let dateError, dateMention == nil { Text(dateError).font(.caption2).foregroundStyle(.red) }
        }.absorptionAnchor("quickEntry")
            .onReceive(NotificationCenter.default.publisher(for: .focusFloatingTask)) { _ in if floatingShortcutTarget { entryFocused = true } }
    }
    private func create() {
        var value = title
        var due = date
        if let mention = dateMention {
            guard let parsed = DateMention.date(mention.query) else { dateError = "请输入未来一年内的月日，如 0104"; return }
            due = parsed; value.removeSubrange(mention.range)
        }
        if store.createTask(title: value, dueDate: due) { title = ""; date = nil; dateError = nil }
    }
}

struct DueDatePicker: View {
    let query: String
    var error: String?
    var select: (Date) -> Void
    @State private var month = Date()
    private let calendar = Calendar.current
    private var start: Date { calendar.date(from: calendar.dateComponents([.year, .month], from: month))! }
    private var leading: Int { (calendar.component(.weekday, from: start) + 5) % 7 }
    private var count: Int { calendar.range(of: .day, in: .month, for: start)!.count }
    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(month, format: .dateTime.year().month()).font(.caption)
                Spacer()
                Button { move(1) } label: { Image(systemName: "chevron.right") }
            }.buttonStyle(.plain)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text($0).foregroundStyle(.secondary).font(.system(size: 10)) }
                ForEach(0..<(leading + count), id: \.self) { index in
                    if index < leading { Color.clear.frame(height: 22) }
                    else {
                        let date = calendar.date(byAdding: .day, value: index - leading, to: start)!
                        Button { select(date) } label: {
                            Text("\(index - leading + 1)").font(.system(size: 11))
                                .frame(maxWidth: .infinity).frame(height: 22)
                                .background(DateMention.date(query).map { calendar.isDate($0, inSameDayAs: date) } == true ? Palette.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 4))
                        }.buttonStyle(.plain).disabled(!DateMention.isAllowed(date))
                    }
                }
            }
            Text(error ?? DateMention.date(query).map { $0.formatted(date: .abbreviated, time: .omitted) + " · Enter 确认" } ?? "输入四位月日 · 今天起一年内")
                .font(.system(size: 10)).foregroundStyle(error == nil ? Color.secondary : Color.red)
        }.padding(9).frame(width: 238).ledgerGlass(radius: 16)
            .onAppear { if let date = DateMention.date(query) { month = date } }
            .onChange(of: query) { _, value in if let date = DateMention.date(value) { month = date } }
    }
    private func move(_ offset: Int) {
        let next = calendar.date(byAdding: .month, value: offset, to: start)!
        let today = calendar.startOfDay(for: Date())
        let minMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
        let limit = calendar.date(byAdding: .year, value: 1, to: today)!
        if next >= minMonth && next <= limit { month = next }
    }
}

struct CompletionFragments: View, Animatable {
    var progress: CGFloat
    var animatableData: CGFloat { get { progress } set { progress = newValue } }
    var body: some View {
        Canvas { context, size in
            for i in 0..<32 {
                let x = CGFloat(i % 8) / 7 * size.width
                let y = CGFloat(i / 8) / 3 * size.height
                let angle = Double(i) * 2.39996
                let distance = CGFloat(25 + i % 7 * 7) * progress
                let rect = CGRect(x: x + cos(angle) * distance, y: y + sin(angle) * distance, width: 3 + CGFloat(i % 3), height: 3)
                context.opacity = Double(1-progress)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.green))
            }
        }
    }
}
