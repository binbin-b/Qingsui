import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class LedgerStore: ObservableObject {
    @Published private(set) var library = Library()
    @Published private(set) var folder: URL?
    @Published var errorMessage: String?
    @Published private(set) var dueReminder: LedgerTask?
    @Published private(set) var taskNotice: TaskSavedNotice?
    @Published var searchQuery = ""
    @Published var searchPresented = false
    @Published var searchFocusRequest = 0
    func beginSearch() { searchPresented = true; searchFocusRequest += 1 }
    @Published var archiveBusy = false
    @Published var archiveStatus: String?
    @Published var hiddenTags: Set<String> = [] {
        didSet { defaults.set(Array(hiddenTags), forKey: visibilityPreferenceKey) }
    }
    @Published var filter: TimelineFilter = .all
    @Published var editingMessage: Message?
    @Published var lastDeletedID: UUID?
    @Published private(set) var finishingTasks: Set<UUID> = []
    private var visibilityPreferenceKey: String { "hiddenTags|" + (folder?.standardizedFileURL.path ?? "none") }
    private let defaults: UserDefaults
    private var choosingFolder = false
    nonisolated static let manifestName = "ChatLedger.library.json"

    init(defaults: UserDefaults = .standard, restore: Bool = true) {
        self.defaults = defaults
        if restore, let path = defaults.string(forKey: "libraryFolder") {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            do {
                guard FileManager.default.fileExists(atPath: url.appendingPathComponent(Self.manifestName).path) else {
                    throw LedgerError.invalidLibrary("上次的资料库暂时找不到，请重新选择原文件夹。")
                }
                try openFolder(url)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func openFolder(_ url: URL) throws {
        let manifest = url.appendingPathComponent(Self.manifestName)
        let candidate: Library
        if FileManager.default.fileExists(atPath: manifest.path) {
            candidate = try JSONDecoder().decode(Library.self, from: Data(contentsOf: manifest))
            try candidate.validate()
        } else {
            candidate = Library()
            try write(candidate, to: url)
        }
        taskNotice = nil
        searchQuery = ""; searchPresented = false
        library = candidate
        folder = url
        hiddenTags = Set(defaults.stringArray(forKey: visibilityPreferenceKey) ?? [])
        archiveStatus = nil
        filter = .all
        defaults.set(url.path, forKey: "libraryFolder")
        refreshDueReminder()
    }

    func chooseFolder() {
        guard !choosingFolder else { return }
        choosingFolder = true
        let panel = NSOpenPanel()
        panel.title = "选择记录保存位置"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "使用此文件夹"
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.choosingFolder = false
            guard response == .OK, let url = panel.url else { return }
            do { try self.openFolder(url) }
            catch { self.errorMessage = "无法打开资料库：\(error.localizedDescription)" }
        }
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.title == "轻随" }) {
            window.makeKeyAndOrderFront(nil)
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else { panel.begin(completionHandler: completion) }
    }

    func closeFolder() {
        searchQuery = ""; searchPresented = false
        taskNotice = nil
        dueReminder = nil
        folder = nil
        hiddenTags = []; archiveStatus = nil
        library = Library()
        filter = .all
        defaults.removeObject(forKey: "libraryFolder")
    }

    private func write(_ candidate: Library, to directory: URL) throws {
        try candidate.validate()
        let original = directory.appendingPathComponent(Self.manifestName)
        let backup = directory.appendingPathComponent("ChatLedger.v1-backup.json")
        if !FileManager.default.fileExists(atPath: backup.path),
           let data = try? Data(contentsOf: original),
           let old = try? JSONDecoder().decode(Library.self, from: data), old.version == 1 {
            try data.write(to: backup, options: .atomic)
        }
        let migrationBackup = directory.appendingPathComponent("ChatLedger.pre-v3-backup.json")
        if !FileManager.default.fileExists(atPath: migrationBackup.path),
           let data = try? Data(contentsOf: original),
           let old = try? JSONDecoder().decode(Library.self, from: data), old.version < 3 {
            try data.write(to: migrationBackup, options: .atomic)
        }
        let v4Backup = directory.appendingPathComponent("ChatLedger.pre-v4-backup.json")
        if !FileManager.default.fileExists(atPath: v4Backup.path),
           let data = try? Data(contentsOf: original),
           let old = try? JSONDecoder().decode(Library.self, from: data), old.version < 4 {
            try data.write(to: v4Backup, options: .atomic)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(candidate).write(to: directory.appendingPathComponent(Self.manifestName), options: .atomic)
    }

    @discardableResult
    func send(text: String, taskID: UUID?, newTaskTitle: String?, drafts: [DraftAttachment], dueDate: Date? = nil, tags: [String] = []) -> Bool {
        guard let folder else { errorMessage = LedgerError.noFolder.localizedDescription; return false }
        let parsed = TagMention.extract(text)
        let trimmed = parsed.body
        var title = newTaskTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if dueDate != nil && taskID == nil && (title ?? "").isEmpty {
            guard !trimmed.isEmpty else { errorMessage = "选好日期后，写下要做的事情即可发送。"; return false }
            title = String((trimmed.split(whereSeparator: \.isNewline).first ?? Substring(trimmed)).prefix(60))
        }
        guard !trimmed.isEmpty || !drafts.isEmpty || taskID != nil || !(title ?? "").isEmpty else { return false }
        var candidate = library
        candidate.version = 4
        var assignedID = taskID
        if let title, !title.isEmpty {
            if let existing = candidate.tasks.first(where: { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }) {
                assignedID = existing.id
            } else {
                let task = LedgerTask(title: title)
                candidate.tasks.append(task)
                assignedID = task.id
            }
        }
        if let dueDate {
            guard DateMention.isAllowed(dueDate), let id = assignedID,
                  let index = candidate.tasks.firstIndex(where: { $0.id == id }) else {
                errorMessage = "请关联待办，并选择今天起一年以内的日期。"; return false
            }
            candidate.tasks[index].dueDate = dueDate
        }
        let existingTaskIDs = Set(library.tasks.map(\.id))
        var copied: [URL] = []
        do {
            var attachments: [Attachment] = []
            if !drafts.isEmpty {
                let attachmentFolder = folder.appendingPathComponent("Attachments", isDirectory: true)
                try FileManager.default.createDirectory(at: attachmentFolder, withIntermediateDirectories: true)
                for draft in drafts {
                    let ext = (draft.name as NSString).pathExtension
                    let filename = UUID().uuidString + (ext.isEmpty ? "" : "." + ext)
                    let destination = attachmentFolder.appendingPathComponent(filename)
                    copied.append(destination)
                    if let source = draft.sourceURL {
                        let scoped = source.startAccessingSecurityScopedResource()
                        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                        let values = try source.resourceValues(forKeys: [.isRegularFileKey])
                        guard values.isRegularFile == true else { throw LedgerError.invalidLibrary("请添加文件，暂不支持整个文件夹。") }
                        try FileManager.default.copyItem(at: source, to: destination)
                    } else if let data = draft.data {
                        try data.write(to: destination, options: .atomic)
                    } else { throw LedgerError.invalidLibrary("附件内容无法读取。") }
                    attachments.append(Attachment(name: draft.name, filename: filename, isImage: draft.isImage))
                }
            }
            candidate.messages.append(Message(text: trimmed, taskID: assignedID, attachments: attachments, tags: Array(Set(parsed.tags + tags)).sorted()))
            try write(candidate, to: folder)
            publish(candidate)
            if let task = candidate.tasks.first(where: { $0.id == assignedID }) {
                taskNotice = TaskSavedNotice(title: task.title, dueDate: task.dueDate,
                    caption: dueDate != nil ? "已安排" : (existingTaskIDs.contains(task.id) ? "已关联待办" : "已添加待办"),
                    taskID: task.id, messageID: candidate.messages.last?.id)
            }
            refreshDueReminder()
            return true
        } catch {
            for url in copied { try? FileManager.default.removeItem(at: url) }
            errorMessage = "未能保存，输入内容已保留：\(error.localizedDescription)"
            return false
        }
    }

    func toggle(_ messageID: UUID) {
        guard let message = library.messages.first(where: { $0.id == messageID }) else { return }
        setProcessed(messageID, to: !message.isProcessed)
    }

    func complete(_ messageID: UUID) { setProcessed(messageID, to: true) }

    private func setProcessed(_ messageID: UUID, to processed: Bool) {
        guard let folder, let index = library.messages.firstIndex(where: { $0.id == messageID }),
              library.messages[index].isProcessed != processed else { return }
        var candidate = library
        candidate.version = 4
        candidate.messages[index].isProcessed = processed
        do { try write(candidate, to: folder); publish(candidate); refreshDueReminder() }
        catch { errorMessage = "状态未能保存：\(error.localizedDescription)" }
    }

    @discardableResult
    func createTask(title: String, dueDate: Date? = nil) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let folder else { errorMessage = "请先选择资料库并填写标题。"; return false }
        if let dueDate, !DateMention.isAllowed(dueDate) {
            errorMessage = "只支持今天起一年以内的日期。"; return false
        }
        var candidate = library
        candidate.version = 4
        if let index = candidate.tasks.firstIndex(where: { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }) {
            if let dueDate { candidate.tasks[index].dueDate = dueDate }
        } else {
            candidate.tasks.append(LedgerTask(title: title, dueDate: dueDate, standaloneCompleted: false))
        }
        do {
            try write(candidate, to: folder)
            let existing = library.tasks.contains { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }
            publish(candidate)
            if let saved = candidate.tasks.first(where: { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }) {
                taskNotice = TaskSavedNotice(title: saved.title, dueDate: saved.dueDate,
                    caption: existing ? (dueDate != nil ? "已更新日期" : "待办已存在") : "已添加待办", taskID: saved.id)
            }
            refreshDueReminder()
            return true
        }
        catch { errorMessage = error.localizedDescription; return false }
    }

    func dismissTaskNotice(_ id: UUID) {
        if taskNotice?.id == id { taskNotice = nil }
    }

    func toggleTask(_ id: UUID) {
        guard let folder, let index = library.tasks.firstIndex(where: { $0.id == id }) else { return }
        let complete = !library.isComplete(id)
        var candidate = library
        candidate.version = 4
        candidate.tasks[index].standaloneCompleted = complete
        for i in candidate.messages.indices where candidate.messages[i].taskID == id {
            candidate.messages[i].isProcessed = complete
        }
        do { try write(candidate, to: folder); publish(candidate); refreshDueReminder() }
        catch { errorMessage = error.localizedDescription }
    }

    private func reminderKey(_ task: LedgerTask) -> String? {
        guard let folder, let date = task.dueDate else { return nil }
        let day = Calendar.current.startOfDay(for: date).timeIntervalSinceReferenceDate
        return folder.path + "|" + task.id.uuidString + "|" + String(day)
    }

    func refreshDueReminder(now: Date = Date()) {
        let acknowledged = Set(defaults.stringArray(forKey: "acknowledgedDueReminders") ?? [])
        let today = Calendar.current.startOfDay(for: now)
        let next = library.tasks.filter { task in
            guard let due = task.dueDate, let key = reminderKey(task) else { return false }
            return Calendar.current.startOfDay(for: due) <= today && !library.isComplete(task.id) && !acknowledged.contains(key)
        }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }.first
        if dueReminder != next { dueReminder = next }
    }

    func acknowledgeDueReminder() {
        guard let task = dueReminder, let key = reminderKey(task) else { return }
        var acknowledged = Set(defaults.stringArray(forKey: "acknowledgedDueReminders") ?? [])
        acknowledged.insert(key)
        defaults.set(Array(acknowledged), forKey: "acknowledgedDueReminders")
        filter = .task(task.id)
        refreshDueReminder()
    }

    func tasks(on date: Date) -> [LedgerTask] {
        library.tasks.filter { task in
            task.dueDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
        }
    }

    func attachmentURL(_ attachment: Attachment) -> URL? {
        folder?.appendingPathComponent("Attachments", isDirectory: true).appendingPathComponent(attachment.filename)
    }

    func openAttachment(_ attachment: Attachment) {
        guard let url = attachmentURL(attachment), FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "附件文件找不到，可能已被移动或删除。"; return
        }
        if !NSWorkspace.shared.open(url) { errorMessage = "没有找到可以打开此附件的应用。" }
    }

    var visibleMessages: [Message] {
        let titles = Dictionary(uniqueKeysWithValues: library.tasks.map { ($0.id, $0.title) })
        return library.messages.filter { message in
            guard message.deletedAt == nil || filter == .deleted else { return false }
            if filter == .all && !hiddenTags.isDisjoint(with: message.tags ?? []) { return false }
            guard MessageSearch.matches(message, taskTitle: message.taskID.flatMap { titles[$0] }, query: searchQuery) else { return false }
            switch filter {
            case .all: return true
            case .deleted: return message.deletedAt != nil
            case .day(let day): return Calendar.current.isDate(message.createdAt, inSameDayAs: day) || (message.isActive && message.scheduledDate.map { Calendar.current.isDate($0, inSameDayAs: day) } == true)
            case .task(let id): return message.taskID == id
            case .tag(let tag): return message.isActive && (message.tags ?? []).contains(tag)
            }
        }.sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    func assignTask(to messageIDs: Set<UUID>, existingID: UUID?, title: String) -> Bool {
        guard let folder, !messageIDs.isEmpty else { return false }
        var candidate = library; candidate.version = 4
        let selected = candidate.messages.filter { messageIDs.contains($0.id) && $0.isActive }
        guard selected.count == messageIDs.count else { errorMessage = "部分消息已撤回或删除，请重新选择。"; return false }
        var id = existingID
        if id == nil {
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { errorMessage = "请填写待办标题。"; return false }
            if let task = candidate.tasks.first(where: { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }) { id = task.id }
            else { let task = LedgerTask(title: title); candidate.tasks.append(task); id = task.id }
        }
        guard let id, candidate.tasks.contains(where: { $0.id == id }) else { errorMessage = "待办已不存在。"; return false }
        for i in candidate.messages.indices where messageIDs.contains(candidate.messages[i].id) { candidate.messages[i].taskID = id }
        do { try write(candidate, to: folder); publish(candidate); refreshDueReminder(); return true }
        catch { errorMessage = "关联未能保存：\(error.localizedDescription)"; return false }
    }

    @discardableResult
    private func updateSelected(_ ids: Set<UUID>, change: (inout Message) -> Void) -> Bool {
        guard let folder, !ids.isEmpty else { return false }
        guard library.messages.filter({ ids.contains($0.id) && $0.isActive }).count == ids.count else { errorMessage = "部分消息已撤回或删除，请重新选择。"; return false }
        var candidate = library; candidate.version = 4
        for i in candidate.messages.indices where ids.contains(candidate.messages[i].id) { change(&candidate.messages[i]) }
        do { try write(candidate, to: folder); publish(candidate); refreshDueReminder(); return true }
        catch { errorMessage = "关联未能保存：\(error.localizedDescription)"; return false }
    }
    @discardableResult
    func assignDate(to ids: Set<UUID>, date: Date) -> Bool {
        guard DateMention.isAllowed(date) else { errorMessage = "请选择今天起一年内的日期。"; return false }
        return updateSelected(ids) { $0.scheduledDate = Calendar.current.startOfDay(for: date) }
    }
    @discardableResult
    func assignTag(to ids: Set<UUID>, tag: String) -> Bool {
        let value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { errorMessage = "请填写标签名称。"; return false }
        return updateSelected(ids) { $0.tags = Array(Set(($0.tags ?? []) + [value])).sorted() }
    }
    func hasScheduledMessages(on date: Date) -> Bool {
        library.messages.contains { $0.isActive && !$0.isProcessed && $0.scheduledDate.map { Calendar.current.isDate($0, inSameDayAs: date) } == true }
    }

    // Collection context belongs to the main composer; quick notes remain independent.
    func tagsForCurrentCollection(_ explicit: [String]) -> [String] {
        guard case .tag(let tag) = filter else { return explicit }
        return Array(Set(explicit + [tag])).sorted()
    }

    var tags: [String] { Array(Set(library.messages.filter(\.isActive).flatMap { $0.tags ?? [] })).sorted() }
    var pinnedMessages: [Message] { library.messages.filter { $0.isActive && $0.pinnedAt != nil }.sorted { $0.pinnedAt! < $1.pinnedAt! } }

    private func publish(_ candidate: Library) {
        let newly = Set(candidate.tasks.filter { candidate.isComplete($0.id) && !library.isComplete($0.id) }.map(\.id))
        finishingTasks.formUnion(newly)
        library = candidate
        finishingTasks = finishingTasks.filter { candidate.isComplete($0) }
        if !newly.isEmpty {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(1050))
                self?.finishingTasks.subtract(newly)
            }
        }
    }

    private func changeMessage(_ id: UUID, change: (inout Message) -> Void) {
        guard let folder, let index = library.messages.firstIndex(where: { $0.id == id }) else { return }
        var candidate = library; candidate.version = 4
        change(&candidate.messages[index])
        do { try write(candidate, to: folder); publish(candidate); refreshDueReminder() }
        catch { errorMessage = "未能保存：\(error.localizedDescription)" }
    }
    func deleteMessage(_ id: UUID) {
        changeMessage(id) { $0.deletedAt = Date(); $0.pinnedAt = nil }
        if library.messages.first(where: { $0.id == id })?.deletedAt != nil { lastDeletedID = id }
    }
    func restoreMessage(_ id: UUID) { changeMessage(id) { $0.deletedAt = nil } }
    func undoDelete() {
        guard let id = lastDeletedID else { return }
        changeMessage(id) { $0.deletedAt = nil }; lastDeletedID = nil
    }
    func retractMessage(_ id: UUID) { changeMessage(id) { $0.retractedAt = Date(); $0.pinnedAt = nil } }
    func togglePin(_ id: UUID) { changeMessage(id) { $0.pinnedAt = $0.pinnedAt == nil ? Date() : nil } }

    static func draft(for url: URL) -> DraftAttachment {
        let type = UTType(filenameExtension: url.pathExtension)
        return DraftAttachment(name: url.lastPathComponent, sourceURL: url, data: nil, isImage: type?.conforms(to: .image) == true)
    }
}
