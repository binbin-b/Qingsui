import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var searchFocused: Bool
    @State private var searchText = ""
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var floating: FloatingTodo
    @State private var selectedTags: [String] = []
    @State private var tagEditing = false
    @State private var tagQuery = ""
    @State private var tagChoice = 0
    @State private var editorFocusRequest = 0
    @FocusState private var tagFocused: Bool
    @State private var showVisibility = false
    @State private var selecting = false
    @State private var selectedMessages: Set<UUID> = []
    @State private var bulkAction: BulkAction?
    @StateObject private var selection = TranscriptSelection()
    @State private var text = ""
    @State private var draftBackup: MessageDraft?
    @State private var scrollTarget: UUID?
    @State private var selectedTaskID: UUID?
    @State private var newTaskTitle: String?
    @State private var dueDate: Date?
    @State private var drafts: [DraftAttachment] = []
    @State private var isDropTarget = false
    @State private var editorHeight: CGFloat = 28
    @State private var choice = 0
    @State private var dismissed = false
    @State private var dateError: String?
    @State private var showDatePicker = false
    @State private var visibleLimit = 60

    private var tagToken: TagInputToken? { dismissed || tagEditing ? nil : TagInputToken.parse(text) }
    private var currentTagQuery: String { tagEditing ? tagQuery : (tagToken?.query ?? "") }
    private var tagMatches: [String] { store.tags.filter { !selectedTags.contains($0) && (currentTagQuery.isEmpty || $0.localizedCaseInsensitiveContains(currentTagQuery)) } }
    private var canCreateTag: Bool { !currentTagQuery.isEmpty && !selectedTags.contains(currentTagQuery) && !tagMatches.contains(currentTagQuery) }
    private var tagOptionCount: Int { tagMatches.count + (canCreateTag ? 1 : 0) }
    private var dateMention: DateMention? { dismissed ? nil : DateMention.parse(text) }
    private var mention: TaskMention? { dismissed || tagEditing || tagToken != nil || showDatePicker || dateMention != nil ? nil : TaskMention.parse(text) }
    private var matches: [LedgerTask] {
        guard let mention else { return [] }
        return store.library.tasks.filter { mention.query.isEmpty || $0.title.localizedCaseInsensitiveContains(mention.query) }
    }
    private var canCreate: Bool {
        guard let mention, !mention.query.isEmpty else { return false }
        return !matches.contains { $0.title.localizedCaseInsensitiveCompare(mention.query) == .orderedSame }
    }
    private var options: Int { matches.count + (canCreate ? 1 : 0) }
    private var selectedTitle: String? { newTaskTitle ?? store.library.tasks.first { $0.id == selectedTaskID }?.title }
    private var hasDraft: Bool { !text.isEmpty || !drafts.isEmpty || selectedTitle != nil || dueDate != nil || !selectedTags.isEmpty || tagEditing }

    var body: some View {
        GeometryReader { geometry in
            let rail = geometry.size.width < 420
            HStack(spacing: 0) {
                if geometry.size.width >= 680 {
                    SidebarView(canChangeFolder: !hasDraft).frame(width: 238)
                    Divider()
                }
                VStack(spacing: 0) {
                    HStack(spacing: 7) {
                        Spacer()
                        ToolbarActionButton(symbol: "magnifyingglass", help: "搜索消息") {
                            if store.searchPresented { store.searchPresented = false; store.searchQuery = ""; searchText = "" } else { store.beginSearch() }
                        }.frame(width: 28, height: 28)
                        ToolbarActionButton(symbol: "gearshape", help: "设置") { SettingsWindow.show() }.frame(width: 28, height: 28)
                        ToolbarActionButton(symbol: "line.3.horizontal.decrease.circle", help: "隐藏指定标签的消息") { showVisibility.toggle() }
                            .frame(width: 28, height: 28)
                            .popover(isPresented: $showVisibility) { VisibilityPanel().environmentObject(store) }
                        FloatingToggleButton(visible: floating.visible, compact: rail) { floating.toggle(store: store) }
                            .frame(width: rail ? 30 : 72, height: 24)
                            .focusEffectDisabled().ledgerGlass(radius: 12).absorptionAnchor("floatingToggle")
                        ToolbarActionButton(title: rail ? "" : "使用说明", symbol: "questionmark.circle", help: "使用说明") {
                            UserGuideWindow.show()
                        }.frame(width: rail ? 26 : 82, height: 24).ledgerGlass(radius: 12)
                        ToolbarActionButton(symbol: rail ? "arrow.up.left.and.arrow.down.right" : "sidebar.right",
                            help: rail ? "展开窗口" : "收成侧边窄条") { WindowMode.toggle() }
                            .frame(width: 26, height: 24)
                    }.foregroundStyle(.secondary).padding(.horizontal, 12).frame(height: 34).focusEffectDisabled()
                    if store.searchPresented {
                        HStack(spacing: 7) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("搜索消息、待办、标签、文件", text: $searchText).textFieldStyle(.plain).focused($searchFocused)
                                .onAppear { searchFocused = true }
                                .onSubmit { store.searchQuery = searchText }
                                .onExitCommand { store.searchPresented = false; store.searchQuery = ""; searchText = "" }
                            Text("\(store.visibleMessages.count) 条").font(.caption).foregroundStyle(.secondary)
                            Button { store.searchPresented = false; store.searchQuery = ""; searchText = "" } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("退出搜索")
                        }.padding(9).ledgerGlass(radius: 12).padding(.horizontal, 10).padding(.bottom, 5)
                    }
                    if store.filter != .all || !store.hiddenTags.isEmpty {
                        HStack {
                            if store.filter != .all {
                                Button { store.filter = .all } label: { Label("返回", systemImage: "chevron.left") }.buttonStyle(.plain).padding(.vertical, 7).padding(.horizontal, 8).ledgerGlass(radius: 10)
                            }
                            Text(store.filter == .all ? "已隐藏 \(store.hiddenTags.count) 个标签" : filterTitle).font(.caption).lineLimit(1)
                            Spacer()
                            Button(store.filter == .all ? "恢复显示" : "退出筛选") { store.filter = .all; store.hiddenTags = [] }.buttonStyle(.plain).font(.caption).padding(6)
                        }.padding(.horizontal, 12).frame(height: 28)
                    }
                    if store.folder == nil {
                        Spacer()
                        Button("选择保存文件夹") { store.chooseFolder() }.buttonStyle(.borderedProminent)
                        Spacer()
                    } else {
                        timeline(rail: rail, width: max(180, floor(geometry.size.width - (geometry.size.width >= 680 ? 239 : 0) - (rail ? 16 : 28))))
                        composer
                    }
                }.background(Palette.canvas.opacity(colorScheme == .dark ? 0.86 : 0.30))
            }.background(DesktopGlass()).background(WindowModeObserver())
        }
        .overlayPreferenceValue(AbsorptionAnchorKey.self) { anchors in AbsorptionFeedback(anchors: anchors) }
        .overlay { ReminderOverlay() }
        .sheet(item: $bulkAction) { kind in
            Group {
                if kind == .task {
                    BulkTaskPicker(messageIDs: selectedMessages) { finishBulk() }
                } else {
                    BulkMetadataPicker(kind: kind, messageIDs: selectedMessages) { finishBulk() }
                }
            }.environmentObject(store).appAppearance()
        }
        .task {
            while !Task.isCancelled {
                store.refreshDueReminder()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .task(id: searchText) {
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            guard store.searchPresented else { return }
            store.searchQuery = searchText
        }
        .onChange(of: store.searchPresented) { _, presented in
            if presented { searchText = store.searchQuery; DispatchQueue.main.async { searchFocused = true } }
            else { searchText = "" }
        }
        .onChange(of: store.searchFocusRequest) { _, _ in searchFocused = true }
        .onChange(of: store.searchQuery) { _, _ in visibleLimit = 60; selection.anchor = nil }
        .onChange(of: scenePhase) { _, phase in if phase == .active { store.refreshDueReminder() } }
        .alert("未能完成", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("好", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .onChange(of: store.editingMessage) { _, message in
            guard let message else { return }
            if hasDraft { draftBackup = MessageDraft(text: text, task: selectedTaskID, title: newTaskTitle, date: dueDate, attachments: drafts, tags: selectedTags) }
            text = message.text; selectedTags = message.tags ?? []
            selectedTaskID = message.taskID; newTaskTitle = nil
            dueDate = store.library.tasks.first { $0.id == message.taskID }?.dueDate
            drafts = message.attachments.compactMap { store.attachmentURL($0).map(LedgerStore.draft) }
            store.editingMessage = nil
        }
        .onChange(of: text) { _, value in
            choice = 0; tagChoice = 0; dismissed = false; dateError = nil
            if !tagEditing, value.hasSuffix("# "), let token = TagInputToken.parse(value) {
                text.removeSubrange(token.range); tagQuery = ""; tagEditing = true
                DispatchQueue.main.async { tagFocused = true }
            }
        }
        .onChange(of: tagQuery) { _, _ in tagChoice = 0 }
        .onChange(of: store.folder) { _, _ in searchText = ""; selectedTaskID = nil; newTaskTitle = nil; dueDate = nil; selectedTags = []; tagEditing = false }
    }
    private var filterTitle: String {
        switch store.filter {
        case .all: return ""
        case .deleted: return "已删除消息"
        case .day(let date): return date.formatted(date: .abbreviated, time: .omitted)
        case .task(let id): return store.library.tasks.first { $0.id == id }?.title ?? ""
        case .tag(let tag): return "#" + tag
        }
    }
    private func timeline(rail: Bool, width: CGFloat) -> some View {
        let messages = store.visibleMessages
        let displayed = Array(messages.suffix(visibleLimit))
        return ScrollViewReader { proxy in
            VStack(spacing: 4) {
                if selecting {
                    HStack {
                        Text("已选 \(selectedMessages.count) 条").font(.caption)
                        Button("全选") { selectedMessages = Set(displayed.filter(\.isActive).map(\.id)) }
                        Spacer()
                        Menu("关联…") {
                            Button("待办事项") { bulkAction = .task }
                            Button("同一个日期") { bulkAction = .date }
                            Button("同一个标签") { bulkAction = .tag }
                        }.menuStyle(.borderlessButton).fixedSize().disabled(selectedMessages.isEmpty)
                        Button("取消") { selecting = false; selectedMessages = [] }
                    }.font(.caption).padding(8)
                }
                if !store.pinnedMessages.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(store.pinnedMessages) { message in
                                Button {
                                    store.filter = .all; visibleLimit = store.library.messages.count; scrollTarget = message.id
                                    DispatchQueue.main.async { proxy.scrollTo(message.id, anchor: .center) }
                                } label: { Label(String(message.text.prefix(44)), systemImage: "pin.fill").lineLimit(1) }
                                .buttonStyle(.plain).font(.system(size: 11)).padding(8).ledgerGlass(radius: 16)
                                .contextMenu { Button("取消置顶") { store.togglePin(message.id) } }
                            }
                        }.padding(.horizontal, 12)
                    }.frame(height: 36)
                }
                if store.lastDeletedID != nil {
                    HStack { Text("消息已删除"); Button("撤销") { store.undoDelete() }; Spacer(); Button { store.lastDeletedID = nil } label: { Image(systemName: "xmark") } }.font(.caption).padding(.horizontal, 12)
                }
            ScrollView {
                VStack(alignment: .trailing, spacing: 9) {
                    if messages.count > visibleLimit {
                        Button("加载更早的消息") { visibleLimit += 60 }.buttonStyle(.plain).font(.caption)
                            .frame(width: width)
                    }
                    if case .day(let date) = store.filter, !store.tasks(on: date).isEmpty {
                        VStack(spacing: 1) {
                            ForEach(store.tasks(on: date)) { task in CompactTaskRow(task: task) }
                        }.padding(5).background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    }
                    ForEach(displayed) { message in
                        MessageBubble(message: message, compact: rail, availableWidth: width, selection: selection,
                            selecting: selecting, selected: selectedMessages.contains(message.id), choose: {
                                if !selecting { selecting = true; selection.anchor = nil }
                                if selectedMessages.contains(message.id) { selectedMessages.remove(message.id) } else { selectedMessages.insert(message.id) }
                            })
                            .equatable().frame(width: width, alignment: .trailing).id(message.id)
                            .absorptionAnchor("message." + message.id.uuidString)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.frame(width: width, alignment: .trailing).padding(rail ? 8 : 14)
            }
            }
            .onAppear { selection.order = displayed.map(\.id); DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: store.library.messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: displayed.map(\.id)) { _, ids in selection.order = ids }
            .onChange(of: store.filter) { _, _ in
                selection.anchor = nil
                if let target = scrollTarget { scrollTarget = nil; DispatchQueue.main.async { proxy.scrollTo(target, anchor: .center) }; return }
                visibleLimit = 60
                DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .overlay { if isDropTarget { RoundedRectangle(cornerRadius: 9).stroke(Palette.accent, lineWidth: 2).padding(4).allowsHitTesting(false) } }
        .overlay {
            if store.searchPresented && !store.searchQuery.isEmpty && messages.isEmpty {
                VStack(spacing: 8) { Image(systemName: "magnifyingglass").font(.system(size: 24)); Text("没有找到相关消息").font(.system(size: 13)) }.foregroundStyle(.secondary).allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTarget) { providers in
            return acceptDrop(providers)
        }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let backup = draftBackup {
                Button("恢复之前的草稿") {
                    let current = MessageDraft(text: text, task: selectedTaskID, title: newTaskTitle, date: dueDate, attachments: drafts, tags: selectedTags)
                    text = backup.text; selectedTags = backup.tags; selectedTaskID = backup.task; newTaskTitle = backup.title; dueDate = backup.date; drafts = backup.attachments
                    draftBackup = (!current.text.isEmpty || !current.attachments.isEmpty || current.task != nil || current.title != nil || current.date != nil) ? current : nil
                }.font(.caption)
            }
            if case .tag(let tag) = store.filter {
                HStack(spacing: 8) {
                    Label("# " + tag, systemImage: "number").lineLimit(1)
                    Spacer(minLength: 4)
                    Button { store.filter = .all } label: { Label("退出标签", systemImage: "xmark") }
                        .buttonStyle(.plain).padding(.vertical, 5).padding(.horizontal, 7)
                }.font(.caption).foregroundStyle(Palette.accent).padding(.horizontal, 8).ledgerGlass(radius: 10)
                    .accessibilityElement(children: .contain)
            }
            if let task = store.activeTaskCollection {
                HStack(spacing: 8) {
                    Label(task.title, systemImage: "checklist").lineLimit(1)
                    Spacer(minLength: 4)
                    Button { store.filter = .all } label: { Label("退出待办", systemImage: "xmark") }
                        .buttonStyle(.plain).padding(.vertical, 5).padding(.horizontal, 7)
                }.font(.caption).foregroundStyle(Palette.accent).padding(.horizontal, 8).ledgerGlass(radius: 10)
                    .accessibilityElement(children: .contain)
            }
            if tagEditing || tagToken != nil { tagPicker }
            if !selectedTags.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 5) { ForEach(selectedTags, id: \.self) { tag in chip("# " + tag) { selectedTags.removeAll { $0 == tag } } } }
                }.fixedSize(horizontal: false, vertical: true)
            }
            if showDatePicker || dateMention != nil {
                DueDatePicker(query: dateMention?.query ?? "", error: dateError, select: chooseDate)
            } else if let mention { picker(mention) }
            if selectedTitle != nil || dueDate != nil {
                HStack(spacing: 6) {
                    if let title = selectedTitle {
                        chip("@ " + title) { selectedTaskID = nil; newTaskTitle = nil; dueDate = nil }
                    }
                    if let dueDate { chip(dueDate.formatted(date: .abbreviated, time: .omitted)) { self.dueDate = nil } }
                }
            }
            if !drafts.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        ForEach(drafts) { draft in
                            HStack(spacing: 4) {
                                Image(systemName: draft.isImage ? "photo" : "doc")
                                Text(draft.name).lineLimit(1).frame(maxWidth: 115)
                                Button { drafts.removeAll { $0.id == draft.id } } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                            }.font(.system(size: 10)).padding(5).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }.frame(height: 25)
            }
            HStack(alignment: .bottom, spacing: 7) {
                Button {
                    showDatePicker.toggle(); dismissed = false; dateError = nil
                } label: {
                    Image(systemName: "calendar").font(.system(size: 16)).frame(width: 28, height: 28)
                }.help("选择待办日期 · /月日").accessibilityLabel("选择待办日期")
                ZStack(alignment: .topLeading) {
                    if text.isEmpty { Text("消息 · @待办 · #标签").font(.system(size: 14)).foregroundStyle(.tertiary).padding(.top, 5).padding(.leading, 7).allowsHitTesting(false) }
                    MessageEditor(text: $text, height: $editorHeight, onFiles: addFiles, onImage: { data in
                        drafts.append(DraftAttachment(name: "粘贴图片-\(drafts.count + 1).png", sourceURL: nil, data: data, isImage: true))
                    }, onReturn: confirmOrSend, onNavigation: navigate, focusRequest: editorFocusRequest).frame(height: editorHeight)
                }
                Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 23)).frame(width: 28, height: 28) }
                    .foregroundStyle(Palette.accent).disabled(!hasDraft).help("Enter 发送 · Shift Enter 换行")
            }.buttonStyle(.plain)
        }.padding(9).ledgerGlass(radius: 18)
            .padding(.horizontal, 12).padding(.bottom, 10).padding(.top, 4)
            .absorptionAnchor("composer")
            .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: acceptDrop)
    }
    private var tagPicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            if tagEditing {
                HStack {
                    Text("#").foregroundStyle(Palette.accent)
                    TextField("标签内容", text: $tagQuery).textFieldStyle(.plain).focused($tagFocused)
                        .onSubmit(confirmTag)
                        .onKeyPress(.tab) { tagChoice = (tagChoice + 1) % max(1, tagOptionCount); return .handled }
                        .onKeyPress(.escape) { tagEditing = false; dismissed = true; editorFocusRequest += 1; return .handled }
                }.padding(8).background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(tagMatches.enumerated()), id: \.element) { index, tag in
                            tagOption("# " + tag, index: index).id(index)
                        }
                        if canCreateTag { tagOption("新建 # " + currentTagQuery, index: tagMatches.count).id(tagMatches.count) }
                        if tagOptionCount == 0 { Text(currentTagQuery.isEmpty ? "输入标签名称" : "这个标签已选择").font(.caption).foregroundStyle(.secondary).padding(6) }
                    }
                }.frame(height: min(110, CGFloat(max(1, tagOptionCount)) * 28))
                .onChange(of: tagChoice) { _, value in proxy.scrollTo(value) }
            }
            Text("Tab 切换 · Enter 确认 · Esc 取消").font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(8).ledgerGlass(radius: 12)
    }
    private func tagOption(_ title: String, index: Int) -> some View {
        Button { tagChoice = index; confirmTag() } label: {
            Text(title).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(5)
        }.buttonStyle(.plain).background(tagChoice == index ? Palette.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
    }
    private func confirmTag() {
        let value: String
        if tagChoice < tagMatches.count { value = tagMatches[tagChoice] }
        else if canCreateTag { value = currentTagQuery }
        else { return }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if let token = tagToken { text.removeSubrange(token.range) }
        if !selectedTags.contains(clean) { selectedTags.append(clean) }
        tagEditing = false; tagQuery = ""; tagChoice = 0; editorFocusRequest += 1
    }

    private func chip(_ label: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) { Text(label).lineLimit(1); Button(action: remove) { Image(systemName: "xmark") }.buttonStyle(.plain) }
            .font(.system(size: 11)).foregroundStyle(Palette.accent).padding(.horizontal, 7).padding(.vertical, 3)
            .background(Palette.accent.opacity(0.08), in: Capsule())
    }
    private func picker(_ mention: TaskMention) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, task in
                            option(task.title, index: index) { chooseTask(index) }.id(index)
                        }
                        if canCreate { option("新建「\(mention.query)」", index: matches.count) { chooseTask(matches.count) }.id(matches.count) }
                    }
                }.frame(height: min(CGFloat(max(options, 1)) * 27, 135))
                    .onChange(of: choice) { _, value in proxy.scrollTo(value) }
            }
            Text("↑↓ 选择 · Enter / Tab 确认").font(.system(size: 9)).foregroundStyle(.secondary)
        }.padding(6).ledgerGlass(radius: 12)
    }
    private func option(_ title: String, index: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.system(size: 12)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(6).contentShape(Rectangle()) }
            .buttonStyle(.plain).background(choice == index ? Palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 4))
    }
    private func chooseTask(_ index: Int) {
        guard let mention else { return }
        if index < matches.count {
            selectedTaskID = matches[index].id; newTaskTitle = nil
        } else if canCreate { newTaskTitle = mention.query; selectedTaskID = nil }
        else { return }
        text.removeSubrange(mention.range)
    }
    private func chooseDate(_ date: Date) {
        let token = dateMention
        let prefix = token.map { String(text[..<$0.range.lowerBound]) } ?? text
        if let rawTask = TaskMention.parse(prefix), !rawTask.query.isEmpty {
            newTaskTitle = rawTask.query; selectedTaskID = nil
            var remainder = prefix; remainder.removeSubrange(rawTask.range); text = remainder
        } else if let token { text.removeSubrange(token.range) }
        dueDate = date; dateError = nil; showDatePicker = false
    }
    private func confirmOrSend() {
        if tagEditing || tagToken != nil { confirmTag(); return }
        if let token = dateMention {
            guard let date = DateMention.date(token.query) else { dateError = "请输入有效的四位月日，如 0104"; return }
            chooseDate(date)
        } else if mention != nil { chooseTask(min(choice, max(0, options - 1))) }
        else { send() }
    }
    private func navigate(_ key: UInt16) -> Bool {
        if tagEditing || tagToken != nil {
            if key == 48 || key == 125 { tagChoice = (tagChoice + 1) % max(1, tagOptionCount); return true }
            if key == 126 { tagChoice = (tagChoice + max(1, tagOptionCount) - 1) % max(1, tagOptionCount); return true }
            if key == 53 { tagEditing = false; dismissed = true; editorFocusRequest += 1; return true }
        }
        guard mention != nil || dateMention != nil || showDatePicker else { return false }
        if key == 53 { dismissed = true; showDatePicker = false; return true }
        if key == 48 { confirmOrSend(); return true }
        if mention != nil && options > 0 {
            if key == 125 { choice = (choice + 1) % options; return true }
            if key == 126 { choice = (choice + options - 1) % options; return true }
        }
        return false
    }
    private func send() {
        if tagEditing || tagToken != nil || dateMention != nil { confirmOrSend(); return }
        var body = text
        var taskID = selectedTaskID
        var title = newTaskTitle
        if let mention, !mention.query.isEmpty { title = mention.query; taskID = nil; body.removeSubrange(mention.range) }
        guard store.sendFromMainComposer(text: body, taskID: taskID, newTaskTitle: title, drafts: drafts, dueDate: dueDate, tags: selectedTags) else { return }
        switch store.filter {
        case .deleted: store.filter = .all
        case .tag(let tag) where !(store.library.messages.last?.tags ?? []).contains(tag): store.filter = .all
        case .day(let date) where !Calendar.current.isDateInToday(date): store.filter = .all
        case .task(let id) where store.library.messages.last?.taskID != id: store.filter = .all
        default: break
        }
        text = ""; selectedTaskID = nil; newTaskTitle = nil; dueDate = nil; drafts = []; editorHeight = 28; showDatePicker = false; selectedTags = []
    }
    private func finishBulk() { bulkAction = nil; selecting = false; selectedMessages = [] }
    private func addFiles(_ urls: [URL]) {
        for url in urls {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { drafts.append(LedgerStore.draft(for: url)) }
            else { store.errorMessage = "请添加文件，暂不支持文件夹。" }
        }
    }
    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in guard let url else { return }; Task { @MainActor in addFiles([url]) } }
        }
        return !providers.isEmpty
    }
}

struct MessageBubble: View, Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message == rhs.message && lhs.compact == rhs.compact && lhs.availableWidth == rhs.availableWidth &&
        lhs.selecting == rhs.selecting && lhs.selected == rhs.selected && lhs.selection === rhs.selection
    }

    @EnvironmentObject var store: LedgerStore
    let message: Message
    var compact = false
    var availableWidth: CGFloat = 560
    var selection: TranscriptSelection
    var selecting = false
    var selected = false
    var choose: () -> Void = {}
    private var textWidth: CGFloat {
        let size = (message.text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: compact ? 12 : 14)])
        return min(min(540, max(120, availableWidth - 20 - (selecting ? 26 : 0))), max(50, ceil(size.width) + 2))
    }
    private var task: LedgerTask? { store.library.tasks.first { $0.id == message.taskID } }
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if selecting && message.isActive {
                Button(action: choose) { Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(Palette.accent) }.buttonStyle(.plain).padding(.top, 8)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                if let task, message.isActive {
                    Button { store.filter = .task(task.id) } label: {
                        HStack(spacing: 5) {
                            Text("@ " + task.title)
                            if let due = task.dueDate, message.scheduledDate == nil { Text(due, format: .dateTime.month().day()).font(.system(size: 10)) }
                        }.font(.system(size: 11, weight: .medium)).foregroundStyle(message.isProcessed ? .gray : Palette.accent)
                    }.buttonStyle(.plain).help("进入待办合集，之后发送的消息自动关联此待办")
                        .accessibilityLabel("进入待办合集：" + task.title)
                }
                if message.retractedAt != nil {
                    HStack { Text("消息已撤回").foregroundStyle(.secondary); Button("重新编辑") { store.editingMessage = message } }.font(.caption)
                } else if !message.text.isEmpty {
                    SelectableMessage(id: message.id, text: MessagePresentation.preview(message.text), width: textWidth, fontSize: compact ? 12 : 14,
                        processed: message.isProcessed, selection: selection, doubleClick: { if selecting { choose() } else { store.complete(message.id) } }, singleClick: selecting ? choose : nil, actions: messageActions)
                }
                if message.isActive && MessagePresentation.isLong(message.text) {
                    Button { MessageReaderWindow.show(message.id, store: store) } label: {
                        Label("展开阅读 · \(message.text.count) 字", systemImage: "doc.text.magnifyingglass").font(.system(size: 11, weight: .medium))
                    }.buttonStyle(.plain).foregroundStyle(Palette.accent).padding(.vertical, 3)
                }
                if message.scheduledDate != nil && message.isActive {
                    Label(message.scheduledDate!.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar").font(.caption).foregroundStyle(Palette.accent)
                }
                if message.isActive, let tags = message.tags, !tags.isEmpty {
                    HStack { ForEach(tags, id: \.self) { tag in Button("#" + tag) { store.filter = .tag(tag) }.buttonStyle(.plain).help("进入标签合集，之后发送的消息自动带上此标签").accessibilityLabel("进入标签合集：" + tag) } }.font(.caption).foregroundStyle(Palette.accent)
                }
                let images = message.isActive ? message.attachments.filter(\.isImage) : []
                if !images.isEmpty { ImageStack(attachments: images).saturation(message.isProcessed ? 0.1 : 1).opacity(message.isProcessed ? 0.6 : 1) }
                ForEach(message.attachments.filter { !$0.isImage && message.isActive }) { attachment in
                    FileAttachmentCard(attachment: attachment, width: min(250, max(120, availableWidth - 46)), action: selecting ? choose : nil)
                }
            }.padding(.horizontal, 10).padding(.vertical, 8)
                .background(LinearGradient(colors: [
                    (message.isProcessed ? Palette.processed : Palette.pending).opacity(0.92),
                    (message.isProcessed ? Palette.processed : Palette.pending).opacity(0.70)
                ], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.glassEdge, lineWidth: 0.7))
                .contentShape(RoundedRectangle(cornerRadius: 9))
                .onTapGesture(count: 2) { if !selecting && message.isActive { store.complete(message.id) } }
                .contextMenu {
                    ForEach(Array(messageActions.enumerated()), id: \.offset) { _, item in Button(item.0, action: item.1) }
                }
                .frame(maxWidth: min(560, max(140, availableWidth - (selecting ? 26 : 0))), alignment: .trailing)
                .help(message.createdAt.formatted(date: .abbreviated, time: .shortened))
        }
    }

    private var messageActions: [(String, () -> Void)] {
        if message.deletedAt != nil { return [("恢复消息", { store.restoreMessage(message.id) })] }
        var actions: [(String, () -> Void)] = [("复制全部内容", { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) })]
        if message.isActive {
            if MessagePresentation.isLong(message.text) { actions.append(("展开阅读", { MessageReaderWindow.show(message.id, store: store) })) }
            actions.append(("多选", choose))
            actions.append((message.isProcessed ? "撤销完成" : "标记完成", { store.toggle(message.id) }))
            actions.append((message.pinnedAt == nil ? "置顶" : "取消置顶", { store.togglePin(message.id) }))
            actions.append(("撤回消息", { store.retractMessage(message.id) }))
        } else { actions.append(("重新编辑", { store.editingMessage = message })) }
        actions.append(("删除", { store.deleteMessage(message.id) }))
        return actions
    }

}

struct ImageStack: View {
    @EnvironmentObject var store: LedgerStore
    let attachments: [Attachment]
    @State private var preview = false
    var body: some View {
        Button { preview = true } label: {
            ZStack(alignment: .bottomTrailing) {
                ForEach(Array(attachments.prefix(3).enumerated().reversed()), id: \.element.id) { index, attachment in
                    ImageThumbnail(url: store.attachmentURL(attachment))
                        .frame(width: 168, height: 116).clipped().clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white, lineWidth: 2))
                        .rotationEffect(.degrees(Double(index) * 3)).offset(x: CGFloat(index) * 5, y: -CGFloat(index) * 5)
                }
                if attachments.count > 1 {
                    Text("\(attachments.count) 张").font(.system(size: 10)).padding(5).foregroundStyle(.white).background(.black.opacity(0.65), in: Capsule()).padding(5)
                }
            }.frame(width: 182, height: 130, alignment: .bottomLeading)
        }.buttonStyle(.plain).sheet(isPresented: $preview) { ImageGallery(attachments: attachments).environmentObject(store) }
    }
}
struct ImageThumbnail: View {
    let url: URL?
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.gray.opacity(0.1)) }
        }.task(id: url) { image = url.flatMap { NSImage(contentsOf: $0) } }
    }
}
struct ImageGallery: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) var dismiss
    let attachments: [Attachment]
    @State private var index = 0
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(attachments[index].name).lineLimit(1)
                Spacer()
                Text("\(index + 1) / \(attachments.count)")
                Button { dismiss() } label: { Image(systemName: "xmark") }.help("关闭").accessibilityLabel("关闭").keyboardShortcut(.cancelAction)
            }
            ImageThumbnail(url: store.attachmentURL(attachments[index])).frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Button { index -= 1 } label: { Image(systemName: "chevron.left") }.help("上一张").accessibilityLabel("上一张").disabled(index == 0).keyboardShortcut(.leftArrow, modifiers: [])
                Button { store.openAttachment(attachments[index]) } label: { Image(systemName: "arrow.up.right.square") }.help("打开原图").accessibilityLabel("打开原图")
                Button { index += 1 } label: { Image(systemName: "chevron.right") }.help("下一张").accessibilityLabel("下一张").disabled(index == attachments.count - 1).keyboardShortcut(.rightArrow, modifiers: [])
            }
        }.padding(16).frame(width: 620, height: 500)
    }
}

private struct MessageDraft {
    var text: String
    var task: UUID?
    var title: String?
    var date: Date?
    var attachments: [DraftAttachment]
    var tags: [String]
}

struct BulkTaskPicker: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) var dismiss
    let messageIDs: Set<UUID>
    var finished: () -> Void
    @State private var title = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("为 \(messageIDs.count) 条消息关联待办").font(.headline); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
            HStack {
                TextField("新待办标题", text: $title).textFieldStyle(.roundedBorder).onSubmit { apply(nil) }
                Button("新建并关联") { apply(nil) }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("或选择已有待办").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(store.library.tasks.filter { title.isEmpty || $0.title.localizedCaseInsensitiveContains(title) }) { task in
                        Button { apply(task.id) } label: { Label(task.title, systemImage: "checklist").frame(maxWidth: .infinity, alignment: .leading).padding(8) }.buttonStyle(.plain)
                    }
                }
            }
            if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(20).frame(width: 380, height: 360)
    }
    private func apply(_ id: UUID?) { if store.assignTask(to: messageIDs, existingID: id, title: title) { finished() } }
}

struct VisibilityPanel: View {
    @EnvironmentObject var store: LedgerStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("从全部消息中隐藏").font(.headline)
            Text("记录会保留，点击左侧标签仍可单独查看。").font(.caption).foregroundStyle(.secondary)
            if store.tags.isEmpty { Text("暂无标签").foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.tags, id: \.self) { tag in
                        Toggle("# " + tag, isOn: Binding(get: { store.hiddenTags.contains(tag) }, set: { hidden in
                            if hidden { store.hiddenTags.insert(tag) } else { store.hiddenTags.remove(tag) }
                        }))
                    }
                }
            }.frame(maxHeight: 220)
            Button("恢复全部显示") { store.hiddenTags = [] }
        }.padding(16).frame(width: 260)
    }
}
