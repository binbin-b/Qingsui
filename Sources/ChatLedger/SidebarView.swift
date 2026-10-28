import SwiftUI

struct SidebarRegions {
    let tasks: CGFloat
    let tags: CGFloat
    let calendar: CGFloat
    init(height: CGFloat, tagCount: Int) {
        let usable = max(180, height - 112)
        tasks = min(330, max(96, usable * 0.48))
        let remaining = max(70, usable - tasks - 18)
        let requestedTags = tagCount > 8 ? CGFloat(160) : (tagCount > 2 ? CGFloat(116) : CGFloat(72))
        tags = min(requestedTags, max(48, remaining * 0.42))
        calendar = max(0, remaining - tags)
    }
}

struct SidebarView: View {
    @EnvironmentObject var store: LedgerStore
    let canChangeFolder: Bool
    @State private var showCompleted = false
    @State private var expandedTasks = false
    var body: some View {
        GeometryReader { geometry in
            let regions = SidebarRegions(height: geometry.size.height, tagCount: store.tags.count)
            VStack(alignment: .leading, spacing: 8) {
                if expandedTasks {
                    taskRegion(expanded: true).frame(maxHeight: .infinity)
                } else {
                    taskRegion(expanded: false).frame(height: regions.tasks)
                    Divider()
                    tagRegion.frame(height: regions.tags)
                    Divider()
                    ScrollView { CalendarView(compact: regions.calendar < 230).padding(8).ledgerGlass(radius: 18).absorptionAnchor("calendar") }
                        .frame(height: regions.calendar)
                }
                Spacer(minLength: 0)
                archiveBar
            }.padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
        }.background(.ultraThinMaterial)
    }
    private func taskRegion(expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("待办").font(.system(size: 13, weight: .semibold)).absorptionAnchor("taskList")
                Spacer()
                Button(expanded ? "收起" : "展开全部") { expandedTasks.toggle() }.buttonStyle(.plain).font(.caption).padding(.vertical, 5)
            }
            if store.folder != nil { QuickTaskEntry() }
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(store.library.tasks.filter { !store.library.isComplete($0.id) || store.finishingTasks.contains($0.id) }.reversed()) { task in CompactTaskRow(task: task) }
                    let completed = store.library.tasks.filter { store.library.isComplete($0.id) && !store.finishingTasks.contains($0.id) }
                    if !completed.isEmpty {
                        Button { showCompleted.toggle() } label: {
                            HStack { Image(systemName: showCompleted ? "chevron.down" : "chevron.right"); Text("已完成 \(completed.count)"); Spacer() }.font(.system(size: 10)).foregroundStyle(.secondary).padding(6)
                        }.buttonStyle(.plain)
                        if showCompleted { ForEach(completed) { task in CompactTaskRow(task: task) } }
                    }
                }
            }.scrollIndicators(.visible)
            if store.library.tasks.count > 3 { Text("滚动查看 · 共 \(store.library.tasks.count) 项").font(.system(size: 10)).foregroundStyle(.secondary) }
        }.clipped()
    }
    private var tagRegion: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text("标签").font(.system(size: 12, weight: .semibold)); Spacer(); Text("\(store.tags.count)").font(.caption).foregroundStyle(.secondary) }
            if store.tags.isEmpty { Text("输入 # 空格创建标签").font(.system(size: 11)).foregroundStyle(.tertiary); Spacer(minLength: 0) }
            else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], alignment: .leading, spacing: 5) {
                        ForEach(store.tags, id: \.self) { tag in
                            Button("# " + tag) { store.filter = .tag(tag) }.buttonStyle(.plain)
                                .font(.system(size: 11)).lineLimit(1).padding(6)
                                .background(Palette.accent.opacity(store.filter == .tag(tag) ? 0.2 : 0.06), in: Capsule())
                                .contextMenu {
                                    Button(store.hiddenTags.contains(tag) ? "在全部消息中显示" : "从全部消息中隐藏") {
                                        if store.hiddenTags.contains(tag) { store.hiddenTags.remove(tag) } else { store.hiddenTags.insert(tag) }
                                    }
                                }
                        }
                    }
                }.scrollIndicators(.visible)
            }
        }.clipped()
    }
    private var archiveBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.archiveBusy { ProgressView().controlSize(.small) }
            if let status = store.archiveStatus { Text(status).font(.system(size: 10)).foregroundStyle(.secondary) }
            HStack(spacing: 8) {
                Button { store.chooseFolder() } label: { Image(systemName: "folder").frame(width: 24, height: 28) }
                    .disabled(!canChangeFolder || store.archiveBusy).help("选择资料库文件夹").accessibilityLabel("选择资料库文件夹")
                    .contextMenu {
                        Button("已删除消息") { store.filter = .deleted }
                        Button("在 Finder 中显示") { if let folder = store.folder { NSWorkspace.shared.open(folder) } }.disabled(store.folder == nil)
                        Button("关闭资料库") { store.closeFolder() }.disabled(!canChangeFolder || store.archiveBusy || store.folder == nil)
                    }
                Spacer()
                Button("备份") { store.chooseArchive(.backup) }.help("备份全部数据和附件，可完整恢复")
                Button("导出") { store.chooseArchive(.export) }.help("导出可阅读记录、待办表格和附件")
            }.buttonStyle(.plain).font(.system(size: 11)).disabled(store.folder == nil || store.archiveBusy)
        }.frame(minHeight: 30)
    }
}

struct CalendarView: View {
    @EnvironmentObject var store: LedgerStore
    var compact = false
    @State private var month = Date()
    private let calendar = Calendar.current
    private var monthStart: Date { calendar.date(from: calendar.dateComponents([.year, .month], from: month))! }
    private var leadingDays: Int { (calendar.component(.weekday, from: monthStart) + 5) % 7 }
    private var dayCount: Int { calendar.range(of: .day, in: .month, for: monthStart)!.count }
    private var selectedDay: Date? { if case .day(let date) = store.filter { return date }; return nil }

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(month.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month(.wide)))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("上个月")
                Button("今天") { month = Date(); store.filter = .day(Date()) }.font(.system(size: 10))
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("下个月")
            }.buttonStyle(.plain).foregroundStyle(Palette.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 2) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { day in
                    Text(day).font(.system(size: 10)).foregroundStyle(Palette.secondary).frame(height: 16)
                }
                ForEach(0..<(leadingDays + dayCount), id: \.self) { index in
                    if index < leadingDays { Color.clear.frame(height: compact ? 19 : 24) }
                    else { dayCell(index - leadingDays + 1) }
                }
            }
            HStack(spacing: 5) {
                Circle().fill(Palette.accent).frame(width: 4, height: 4)
                Text("记录").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                Circle().fill(Color.orange).frame(width: 4, height: 4)
                Text("待办").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                Spacer()
            }
        }
    }

    private func dayCell(_ number: Int) -> some View {
        let date = calendar.date(byAdding: .day, value: number - 1, to: monthStart)!
        let selected = selectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let hasMessages = store.library.messages.contains {  $0.deletedAt == nil && calendar.isDate($0.createdAt, inSameDayAs: date) }
        let hasTodo = store.hasScheduledMessages(on: date) || store.tasks(on: date).contains { !store.library.isComplete($0.id) || store.finishingTasks.contains($0.id) }
        let today = calendar.isDateInToday(date)
        return Button { store.filter = .day(date) } label: {
            VStack(spacing: 2) {
                Text("\(number)").font(.system(size: 11, weight: today || selected ? .bold : .regular))
                HStack(spacing: 2) {
                    if hasMessages { Circle().fill(selected ? Palette.onAccent : Palette.accent).frame(width: 3, height: 3) }
                    if hasTodo { Circle().fill(Color.orange).frame(width: 4, height: 4) }
                }.frame(height: 4)
            }.frame(maxWidth: .infinity).frame(height: compact ? 19 : 24)
                .background(selected ? Palette.accent : (today ? Palette.accent.opacity(0.10) : .clear), in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(selected ? Palette.onAccent : (today ? Palette.accent : .primary))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).absorptionAnchor(AbsorptionAnchorKey.day(date)).accessibilityLabel("\(date.formatted(date: .long, time: .omitted))\(hasMessages ? "，有记录" : "")")
    }

    private func moveMonth(_ offset: Int) { month = calendar.date(byAdding: .month, value: offset, to: monthStart)! }
}
