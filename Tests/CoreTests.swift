import AppKit

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func check(_ condition: @autoclosure () -> Bool, _ description: String) throws {
    if !condition() { throw TestFailure(description: description) }
}

@main
@MainActor
struct CoreTests {
    static func main() throws {
        let cases: [(String, () throws -> Void)] = [
            ("多气泡汇总、撤销、新消息重新打开", completion),
            ("附件复制、持久化、普通消息状态", persistence),
            ("附件失败回滚，不产生空待办", rollback),
            ("日期筛选、任务筛选、同标题合并", filters),
            ("损坏资料库保护", corruption),
            ("@ 解析和数据完整性", validation),
            ("写入失败不改变已处理状态", failedToggle),
            ("跨年和未来一年日期范围", dateRange),
            ("日期合法性与闰年边界", leapDates),
            ("日期命令不捕获网址", dateCommands),
            ("独立待办与气泡完成联动", standalone),
            ("日期保存与日历待办查询", scheduling),
            ("旧资料库兼容及原始备份", migration),
            ("双击完成幂等与撤销", completionIdempotency),
            ("待办保存提示只在保存成功后出现", taskNotices),
            ("到期提醒、确认持久化、改期与完成", dueReminders),
            ("标签、置顶、撤回、删除恢复和迁移", messageFeatures),
            ("多选关联、同名复用、完成汇总与原子失败", bulkAssignment),
            ("新标签输入、显式标签和隐藏筛选", tagInputAndVisibility),
            ("完整备份恢复、导出附件及源数据保护", archives),
            ("长消息折叠与搜索范围", presentationAndSearch),
            ("批量日期标签、迁移与独立记事", bulkMetadataAndNote)
        ]
        var failures = 0
        for (name, test) in cases {
            do { try test(); print("PASS: \(name)") }
            catch { failures += 1; print("FAIL: \(name): \(error)") }
        }
        print("\(cases.count - failures)/\(cases.count) tests passed")
        if failures > 0 { exit(1) }
    }

    static func presentationAndSearch() throws {
        let text = String(repeating: "长消息😀完整正文\n", count: 80)
        try check(MessagePresentation.isLong(text), "长消息应折叠")
        try check(MessagePresentation.preview(text).count <= 321 && text.hasPrefix(String(MessagePresentation.preview(text).dropLast())), "预览有界且不损坏原文")
        try check(!MessagePresentation.isLong("短消息") && MessagePresentation.preview("短消息") == "短消息", "短消息不折叠")
        try withStore { store, _ in
            _ = store.send(text: text, taskID: nil, newTaskTitle: "Review计划", drafts: [DraftAttachment(name: "Analysis.PDF", sourceURL: nil, data: Data("file".utf8), isImage: false)], tags: ["研究"])
            store.searchQuery = "analysis 研究"
            try check(store.visibleMessages.count == 1, "文件名与标签支持多词搜索")
            store.searchQuery = "review"
            try check(store.visibleMessages.count == 1, "待办标题忽略大小写")
            store.searchQuery = "不存在"
            try check(store.visibleMessages.isEmpty, "无匹配")
            store.searchQuery = "完整正文"
            try check(store.visibleMessages.count == 1, "搜索完整长文而非折叠预览")
            store.retractMessage(store.library.messages[0].id)
            try check(store.visibleMessages.isEmpty, "撤回正文不被搜索泄露")
            store.searchQuery = "消息已撤回"
            try check(store.visibleMessages.count == 1, "可搜索撤回占位")
        }
    }
    static func bulkMetadataAndNote() throws {
        let contextDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let contextStore = LedgerStore(defaults: contextDefaults, restore: false)
        contextStore.filter = .tag("阅读")
        precondition(contextStore.tagsForCurrentCollection([]) == ["阅读"])
        precondition(contextStore.tagsForCurrentCollection(["阅读", "工作"]).count == 2)
        contextStore.filter = .all
        precondition(contextStore.tagsForCurrentCollection([]).isEmpty)
        try withStore { store, folder in
            _ = store.send(text: "同组 A", taskID: nil, newTaskTitle: "原待办", drafts: [], tags: ["原标签"])
            let task = store.library.tasks[0].id
            _ = store.send(text: "未选中的同组 B", taskID: task, newTaskTitle: nil, drafts: [])
            _ = store.send(text: "另外 C", taskID: nil, newTaskTitle: nil, drafts: [])
            let a = store.library.messages[0].id, b = store.library.messages[1].id, c = store.library.messages[2].id
            let day = Calendar.current.date(byAdding: .day, value: 5, to: Calendar.current.startOfDay(for: Date()))!
            try check(store.assignDate(to: [a,c], date: day), "统一关联一天")
            try check(store.library.messages[1].scheduledDate == nil && store.library.tasks[0].dueDate == nil, "未选消息与原待办不受影响")
            store.filter = .day(day)
            try check(Set(store.visibleMessages.map(\.id)) == [a,c] && store.hasScheduledMessages(on: day), "未来日历显示关联气泡")
            try check(store.assignTag(to: [a,c], tag: "共同标签"), "统一关联一个标签")
            try check(store.library.messages[0].tags == ["共同标签", "原标签"] && store.library.messages[1].tags == [], "保留原标签且不改未选消息")
            let before = store.library
            try check(!store.assignTag(to: [b,UUID()], tag: "失败"), "无效选择拒绝整个批次")
            try check(before == store.library, "批量失败原子性")
            try store.openFolder(folder)
            try check(store.library.messages[0].scheduledDate == day, "日期持久化")
            let count = store.library.tasks.count
            try check(store.send(text: "悬浮记事", taskID: nil, newTaskTitle: nil, drafts: []), "记事直接发送")
            try check(store.library.tasks.count == count && store.library.messages.last?.taskID == nil, "记事不产生待办")
        }
        try withStore { store, folder in
            var old = Library(); old.version = 3
            try JSONEncoder().encode(old).write(to: folder.appendingPathComponent(LedgerStore.manifestName))
            try store.openFolder(folder)
            _ = store.send(text: "升级", taskID: nil, newTaskTitle: nil, drafts: [])
            let saved = try JSONDecoder().decode(Library.self, from: Data(contentsOf: folder.appendingPathComponent("ChatLedger.pre-v4-backup.json")))
            try check(saved.version == 3 && saved.messages.isEmpty, "升级前保留原格式备份")
        }
    }

    static func tagInputAndVisibility() throws {
        try check(TagInputToken.parse("正文 # ")?.query == "", "空格触发标签框")
        try check(TagInputToken.parse("正文 #工作")?.query == "工作", "标签候选")
        try check(TagInputToken.parse("https://a.com/#work") == nil && TagInputToken.parse("正文 #标签 后文") == nil, "不捕获网址和正文")
        try withStore { store, folder in
            _ = store.send(text: "内容", taskID: nil, newTaskTitle: nil, drafts: [], tags: ["工作", "工作"])
            _ = store.send(text: "其他 #阅读", taskID: nil, newTaskTitle: nil, drafts: [])
            try check(store.library.messages[0].tags == ["工作"], "标签与正文分离并去重")
            store.hiddenTags = ["工作"]
            try check(store.visibleMessages.count == 1 && store.library.messages.count == 2, "隐藏不删除")
            store.filter = .tag("工作")
            try check(store.visibleMessages.count == 1, "显式标签筛选仍可查看")
            try store.openFolder(folder); store.filter = .all
            try check(store.visibleMessages.count == 1, "重新打开保留隐藏偏好")
            store.hiddenTags = []
            try check(store.visibleMessages.count == 2, "恢复全部显示")
        }
    }
    static func archives() throws {
        try withStore { store, folder in
            let draft = DraftAttachment(name: "附件.txt", sourceURL: nil, data: Data("附件正文".utf8), isImage: false)
            _ = store.send(text: "导出内容 #阅读", taskID: nil, newTaskTitle: "待办,带逗号", drafts: [draft])
            _ = store.send(text: "已删除内容", taskID: nil, newTaskTitle: nil, drafts: [])
            store.deleteMessage(store.library.messages.last!.id)
            _ = store.createTask(title: "本地日期导出", dueDate: Calendar.current.startOfDay(for: Date()))
            let original = try Data(contentsOf: folder.appendingPathComponent(LedgerStore.manifestName))
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveTests-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            for kind in [ArchiveService.Kind.backup, .export] {
                let name = kind == .backup ? "backup" : "export"
                let zip = root.appendingPathComponent(name + ".zip")
                try ArchiveService.create(library: store.library, source: folder, destination: zip, kind: kind)
                let unpack = root.appendingPathComponent(name)
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); process.arguments = ["-x", "-k", zip.path, unpack.path]
                try process.run(); process.waitUntilExit(); try check(process.terminationStatus == 0, "ZIP 可解压")
                let package = unpack.appendingPathComponent(kind == .backup ? "轻随备份" : "轻随导出")
                let attachment = store.library.messages[0].attachments[0]
                let data = try Data(contentsOf: package.appendingPathComponent("Attachments").appendingPathComponent(attachment.filename))
                try check(data == Data("附件正文".utf8), "附件完整")
                if kind == .backup {
                    let restored = try JSONDecoder().decode(Library.self, from: Data(contentsOf: package.appendingPathComponent(LedgerStore.manifestName)))
                    try check(restored == store.library, "备份恢复所有消息、删除状态、标签、待办")
                } else {
                    let markdown = try String(contentsOf: package.appendingPathComponent("记录.md"), encoding: .utf8)
                    try check(markdown.contains("导出内容") && !markdown.contains("已删除内容"), "导出可读记录不泄露已删除正文")
                    let csv = try String(contentsOf: package.appendingPathComponent("待办.csv"), encoding: .utf8)
                    try check(csv.contains("\"待办,带逗号\""), "CSV 正确转义")
                    let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = .current
                    try check(csv.contains(formatter.string(from: Date())), "导出当地日期不能偏移到前一天")
                }
            }
            do {
                try ArchiveService.create(library: store.library, source: folder, destination: folder.appendingPathComponent("wrong.zip"), kind: .backup)
                throw TestFailure(description: "禁止向资料库内写入备份")
            } catch is LedgerError { }
            let after = try Data(contentsOf: folder.appendingPathComponent(LedgerStore.manifestName))
            try check(original == after, "备份导出不写源数据")
        }
    }

    static func bulkAssignment() throws {
        try withStore { store, folder in
            _ = store.send(text: "A", taskID: nil, newTaskTitle: nil, drafts: [])
            _ = store.send(text: "B", taskID: nil, newTaskTitle: nil, drafts: [])
            let ids = Set(store.library.messages.map(\.id))
            try check(store.assignTask(to: ids, existingID: nil, title: "一起处理"), "新建批量关联")
            let task = store.library.tasks[0].id
            try check(store.library.progress(for: task).total == 2 && store.library.tasks.count == 1, "同一个待办")
            store.complete(store.library.messages[0].id)
            try check(!store.library.isComplete(task), "一条完成不能完成整个待办")
            store.complete(store.library.messages[1].id)
            try check(store.library.isComplete(task) && store.finishingTasks.contains(task), "全完成触发散开状态")
            try check(store.assignTask(to: ids, existingID: nil, title: "一起处理") && store.library.tasks.count == 1, "复用同名待办")
            _ = store.createTask(title: "已有")
            let existing = store.library.tasks.last!.id
            try check(store.assignTask(to: ids, existingID: existing, title: ""), "关联已有")
            try check(store.library.messages.allSatisfy { $0.taskID == existing }, "替换原关联，保持一条一个待办")
            let original = store.library
            try check(!store.assignTask(to: ids.union([UUID()]), existingID: existing, title: ""), "无效消息拒绝整个操作")
            try check(store.library == original, "失败不部分关联")
            store.deleteMessage(store.library.messages[0].id)
            store.filter = .deleted
            try check(store.visibleMessages.count == 1, "删除消息可查看")
            try store.openFolder(folder)
            let deleted = store.library.messages.first { $0.deletedAt != nil }!
            store.restoreMessage(deleted.id)
            try check(store.visibleMessages.count == 2, "重新启动后仍可恢复")
        }
    }

    static func messageFeatures() throws {
        let tags = TagMention.extract("开会 #研究 #work https://example.com/#fragment C# #研究")
        try check(tags.tags == ["work", "研究"] && tags.body.contains("#fragment") && tags.body.contains("C#"), "标签去重且不捕获网址")
        let mention = TaskMention.parse("内容 @开会 #研究")!
        try check(mention.query == "开会" && String("内容 @开会 #研究"[mention.range]) == "@开会 ", "待办和标签分别解析")
        try withStore { store, folder in
            try check(store.send(text: "第一条 #研究", taskID: nil, newTaskTitle: "任务", drafts: []), "发送")
            let first = store.library.messages[0].id, task = store.library.tasks[0].id
            try check(store.send(text: "第二条 #研究 #work", taskID: task, newTaskTitle: nil, drafts: []), "关联")
            let second = store.library.messages[1].id
            store.filter = .tag("研究")
            try check(store.visibleMessages.count == 2 && store.tags.count == 2, "标签筛选")
            store.togglePin(first)
            try check(store.pinnedMessages.map(\.id) == [first], "置顶")
            store.complete(first)
            try check(!store.library.isComplete(task), "多个关联未全部完成")
            store.retractMessage(second)
            try check(store.library.isComplete(task) && store.library.progress(for: task).total == 1, "撤回不计进度")
            try check(store.library.messages[1].text == "第二条" && store.library.messages[1].retractedAt != nil, "撤回保留重编内容")
            store.deleteMessage(first)
            try check(store.visibleMessages.isEmpty && store.pinnedMessages.isEmpty, "删除隐藏并取消置顶")
            store.undoDelete()
            try check(store.visibleMessages.count == 1, "删除可恢复")
            try store.openFolder(folder)
            try check(store.library.messages[1].retractedAt != nil && store.tags == ["研究"], "元数据持久化")
        }
        try withStore { store, folder in
            var old = Library(); old.version = 2
            try JSONEncoder().encode(old).write(to: folder.appendingPathComponent(LedgerStore.manifestName))
            try store.openFolder(folder)
            _ = store.send(text: "新版", taskID: nil, newTaskTitle: nil, drafts: [])
            let backup = try JSONDecoder().decode(Library.self, from: Data(contentsOf: folder.appendingPathComponent("ChatLedger.pre-v3-backup.json")))
            try check(backup.version == 2 && backup.messages.isEmpty, "升级保存原版备份")
        }
    }

    static func dueReminders() throws {
        try withStore { store, folder in
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            try check(store.createTask(title: "今天提醒", dueDate: Date()), "创建今天事项")
            let id = store.library.tasks[0].id
            try check(store.dueReminder?.id == id, "今天应提醒")
            store.acknowledgeDueReminder()
            try check(store.dueReminder == nil && !store.library.isComplete(id), "确认只关闭提醒，不完成事项")
            try store.openFolder(folder)
            try check(store.dueReminder == nil, "重新打开资料库不能重复提醒已确认日期")
            try check(store.createTask(title: "今天提醒", dueDate: tomorrow), "改期")
            try check(store.dueReminder == nil, "未来日期不能提前提醒")
            store.refreshDueReminder(now: tomorrow)
            try check(store.dueReminder?.id == id, "到新日期重新提醒")
            store.toggleTask(id)
            store.refreshDueReminder(now: tomorrow)
            try check(store.dueReminder == nil, "完成后不提醒")
            store.toggleTask(id)
            store.refreshDueReminder(now: tomorrow)
            try check(store.dueReminder?.id == id, "撤销完成仍可提醒尚未确认的新日期")
            store.refreshDueReminder(now: Calendar.current.date(byAdding: .day, value: 2, to: tomorrow)!)
            try check(store.dueReminder?.id == id, "未确认的过期事项应补提醒")
            store.closeFolder()
            try check(store.dueReminder == nil, "关闭资料库清空提醒")
        }
    }

    static func taskNotices() throws {
        try withStore { store, folder in
            try check(store.send(text: "普通消息", taskID: nil, newTaskTitle: nil, drafts: []), "普通消息保存")
            try check(store.taskNotice == nil, "普通消息不弹待办提示")
            try check(store.createTask(title: "提示事项", dueDate: Date()), "创建待办")
            let first = store.taskNotice!
            try check(first.title == "提示事项" && first.dueDate != nil, "提示应包含标题日期")
            try check(store.createTask(title: "另一个事项"), "创建第二项")
            store.dismissTaskNotice(first.id)
            try check(store.taskNotice != nil && store.taskNotice?.id != first.id, "旧提示的计时不能关闭新提示")
            store.dismissTaskNotice(store.taskNotice!.id)
            let bad = DraftAttachment(name: "missing.txt", sourceURL: folder.appendingPathComponent("missing.txt"), data: nil, isImage: false)
            try check(!store.send(text: "失败", taskID: nil, newTaskTitle: "不能提示成功", drafts: [bad]), "坏附件必须失败")
            try check(store.taskNotice == nil, "保存失败不能提示成功")
            try check(store.send(text: "成功", taskID: nil, newTaskTitle: "真正保存", drafts: []), "消息创建待办")
            try check(store.taskNotice?.title == "真正保存", "消息关联提示")
        }
    }

    static func withStore(_ run: (LedgerStore, URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ChatLedgerTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "chatledger.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: folder)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = LedgerStore(defaults: defaults, restore: false)
        try store.openFolder(folder)
        try run(store, folder)
    }

    static func completion() throws {
        try withStore { store, _ in
            try check(store.send(text: "主文档", taskID: nil, newTaskTitle: "审核方案", drafts: []), "发送失败")
            let id = store.library.tasks[0].id
            try check(store.send(text: "补充材料", taskID: id, newTaskTitle: nil, drafts: []), "第二条发送失败")
            let first = store.library.messages[0].id
            let second = store.library.messages[1].id
            store.toggle(first)
            try check(!store.library.isComplete(id) && store.library.progress(for: id).done == 1, "不能提前完成")
            store.toggle(second)
            try check(store.library.isComplete(id), "全部处理应完成")
            store.toggle(first)
            try check(!store.library.isComplete(id), "撤销应重新打开")
            store.toggle(first)
            try check(store.library.isComplete(id), "再次处理应完成")
            try check(store.send(text: "新材料", taskID: id, newTaskTitle: nil, drafts: []), "新材料发送失败")
            try check(!store.library.isComplete(id), "新增气泡应重新打开")
            try check(store.library.progress(for: id).total == 3 && store.library.tasks.count == 1, "计数错误")
        }
    }

    static func persistence() throws {
        try withStore { store, folder in
            let source = folder.appendingPathComponent("原文档.txt")
            try Data("附件测试".utf8).write(to: source)
            try check(store.send(text: "普通记录", taskID: nil, newTaskTitle: nil, drafts: [LedgerStore.draft(for: source)]), "发送失败")
            let message = store.library.messages[0]
            store.toggle(message.id)
            try FileManager.default.removeItem(at: source)
            let copied = try String(contentsOf: store.attachmentURL(message.attachments[0])!, encoding: .utf8)
            try check(copied == "附件测试", "原文件删除影响了副本")
            let before = store.library
            store.closeFolder()
            try check(store.folder == nil && store.library.messages.isEmpty, "关闭资料库应清空视图")
            try store.openFolder(folder)
            try check(store.library == before, "重新打开记录不一致")
            try check(store.library.messages[0].isProcessed && store.library.messages[0].taskID == nil, "普通气泡状态不正确")
        }
    }

    static func rollback() throws {
        try withStore { store, folder in
            let good = DraftAttachment(name: "图片.png", sourceURL: nil, data: Data([1, 2, 3]), isImage: true)
            let bad = LedgerStore.draft(for: folder.appendingPathComponent("missing.pdf"))
            try check(!store.send(text: "内容", taskID: nil, newTaskTitle: "不应保存", drafts: [good, bad]), "缺失附件应该报错")
            try check(store.library.tasks.isEmpty && store.library.messages.isEmpty, "失败不应产生记录")
            try check(store.errorMessage != nil, "应向用户显示错误")
            let files = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("Attachments").path)
            try check(files.isEmpty, "未回滚附件")
            let saved = try JSONDecoder().decode(Library.self, from: Data(contentsOf: folder.appendingPathComponent(LedgerStore.manifestName)))
            try check(saved == Library(), "磁盘记录不应改变")
        }
    }

    static func filters() throws {
        try withStore { store, _ in
            try check(store.send(text: "一", taskID: nil, newTaskTitle: "审核", drafts: []), "发送失败")
            try check(store.send(text: "二", taskID: nil, newTaskTitle: " 审核 ", drafts: []), "发送失败")
            try check(store.send(text: "无关联", taskID: nil, newTaskTitle: nil, drafts: []), "发送失败")
            try check(store.library.tasks.count == 1, "相同标题应复用待办")
            store.filter = .task(store.library.tasks[0].id)
            try check(store.visibleMessages.count == 2, "任务筛选不正确")
            store.filter = .day(Date())
            try check(store.visibleMessages.count == 3, "当天筛选不正确")
            store.filter = .day(Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
            try check(store.visibleMessages.isEmpty, "昨天不应有记录")
        }
    }

    static func corruption() throws {
        try withStore { store, folder in
            try check(store.send(text: "保留记录", taskID: nil, newTaskTitle: nil, drafts: []), "发送失败")
            let before = store.library
            let badFolder = folder.appendingPathComponent("bad")
            try FileManager.default.createDirectory(at: badFolder, withIntermediateDirectories: true)
            let badData = Data("not json".utf8)
            let manifest = badFolder.appendingPathComponent(LedgerStore.manifestName)
            try badData.write(to: manifest)
            var rejected = false
            do { try store.openFolder(badFolder) } catch { rejected = true }
            try check(rejected && store.library == before && store.folder == folder, "损坏资料库不能替换当前状态")
            do {
                try ArchiveService.create(library: store.library, source: folder, destination: folder.appendingPathComponent("wrong.zip"), kind: .backup)
                throw TestFailure(description: "禁止向资料库内写入备份")
            } catch is LedgerError { }
            let after = try Data(contentsOf: manifest)
            try check(after == badData, "损坏文件不应被覆盖")
        }
    }

    static func validation() throws {
        try check(TaskMention.parse("name@example.com") == nil, "邮箱不是待办")
        try check(TaskMention.parse("@标题\n后续正文") == nil, "不能跨行捕获")
        try check(TaskMention.parse("说明文字 @审核方案")?.query == "审核方案", "标题解析错误")
        try check(TaskMention.parse("请看看@审核方案")?.query == "审核方案", "中文后无需空格")
        try check(TaskMention.parse("@")?.query == "", "单独 @ 应弹出列表")
        var library = Library()
        library.messages = [Message(text: "坏关联", taskID: UUID())]
        var rejected = false
        do { try library.validate() } catch { rejected = true }
        try check(rejected, "应拒绝无效关联")
        library.messages = [Message(text: "路径", attachments: [Attachment(name: "坏附件", filename: "../secret", isImage: false)])]
        rejected = false
        do { try library.validate() } catch { rejected = true }
        try check(rejected, "应拒绝越界路径")
        try check(!Library().isComplete(UUID()), "空任务不能视为完成")
    }

    static func failedToggle() throws {
        try withStore { store, folder in
            try check(store.send(text: "正文", taskID: nil, newTaskTitle: "待办", drafts: []), "发送失败")
            let before = store.library
            let moved = folder.appendingPathExtension("moved")
            try FileManager.default.moveItem(at: folder, to: moved)
            defer { try? FileManager.default.moveItem(at: moved, to: folder) }
            store.toggle(store.library.messages[0].id)
            try check(store.library == before && store.errorMessage != nil, "保存失败不能改变完成状态")
        }
    }
    static func calendarFixture(_ year: Int = 2026, _ month: Int = 10, _ day: Int = 27) -> (Calendar, Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return (calendar, calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 15))!)
    }
    static func dateRange() throws {
        let (cal, now) = calendarFixture()
        let jan = DateMention.date("0104", now: now, calendar: cal)!
        try check(cal.component(.year, from: jan) == 2027 && cal.component(.month, from: jan) == 1, "一月应落到明年")
        let nov = DateMention.date("1113", now: now, calendar: cal)!
        try check(cal.component(.year, from: nov) == 2026, "十一月应落到今年")
        let today = DateMention.date("1027", now: now, calendar: cal)!
        try check(cal.isDate(today, inSameDayAs: now), "支持今天")
        let sep = DateMention.date("0903", now: now, calendar: cal)!
        try check(cal.component(.year, from: sep) == 2027, "九月应落到明年")
        try check(!DateMention.isAllowed(cal.date(byAdding: .day, value: -1, to: now)!, now: now, calendar: cal), "不能选过去日期")
        let limit = cal.date(byAdding: .year, value: 1, to: cal.startOfDay(for: now))!
        try check(DateMention.isAllowed(limit, now: now, calendar: cal), "一年边界可选")
        try check(!DateMention.isAllowed(cal.date(byAdding: .day, value: 1, to: limit)!, now: now, calendar: cal), "不能超过一年")
    }
    static func leapDates() throws {
        let (cal, now) = calendarFixture()
        for value in ["0230", "1331", "0000", "111", "11/13", "明天", "20270104", "０１０４", "0229"] {
            try check(DateMention.date(value, now: now, calendar: cal) == nil, "应拒绝无效日期 \(value)")
        }
        let (_, leapNow) = calendarFixture(2027, 10, 27)
        let leap = DateMention.date("0229", now: leapNow, calendar: cal)!
        try check(cal.component(.year, from: leap) == 2028, "应支持下一年闰日")
    }
    static func dateCommands() throws {
        try check(DateMention.parse("https://example.com") == nil, "网址不能触发日历")
        try check(DateMention.parse("https://example.com/a//0104") == nil, "网址路径不能触发日历")
        try check(DateMention.parse("/")?.query == "", "单斜杠应打开日历")
        try check(DateMention.parse("/0104")?.query == "0104", "行首日期命令")
        try check(DateMention.parse("正文\n/0104")?.query == "0104", "新行日期命令")
        for value in ["a/0104", "https://example.com/0104", "/Users/test", "正文 /说明", "//0104"] {
            try check(DateMention.parse(value) == nil, "普通路径和文本不能触发日期: \(value)")
        }
        try check(DateMention.parse("@审核 /0104")?.query == "0104", "待办后可直接输入日期")
        try check(DateMention.parse("正文 /1113")?.query == "1113", "应识别日期命令")
    }
    static func standalone() throws {
        try withStore { store, folder in
            try check(store.createTask(title: "独立事项"), "独立创建失败")
            let id = store.library.tasks[0].id
            try check(store.library.messages.isEmpty && !store.library.isComplete(id), "独立待办不产生气泡")
            store.toggleTask(id)
            try check(store.library.isComplete(id), "独立待办可完成")
            try check(store.send(text: "资料一", taskID: id, newTaskTitle: nil, drafts: []), "关联消息失败")
            try check(!store.library.isComplete(id), "新气泡应重新打开事项")
            try check(store.send(text: "资料二", taskID: id, newTaskTitle: nil, drafts: []), "关联消息失败")
            store.toggleTask(id)
            try check(store.library.messages.allSatisfy(\.isProcessed), "事项完成应同步全部气泡")
            store.toggle(store.library.messages[0].id)
            try check(!store.library.isComplete(id), "气泡撤销应同步事项")
            let before = store.library
            store.closeFolder(); try store.openFolder(folder)
            try check(store.library == before, "独立和关联状态必须持久化")
        }
    }
    static func scheduling() throws {
        try withStore { store, _ in
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
            try check(store.send(text: "内容", taskID: nil, newTaskTitle: "有日期", drafts: [], dueDate: tomorrow), "日期保存失败")
            try check(store.tasks(on: tomorrow).count == 1 && store.tasks(on: Date()).isEmpty, "日历应按计划日期查询")
            let before = store.library
            let invalid = Calendar.current.date(byAdding: .year, value: 2, to: tomorrow)!
            try check(!store.createTask(title: "越界", dueDate: invalid), "拒绝超范围独立待办")
            try check(!store.send(text: "错误", taskID: nil, newTaskTitle: "越界", drafts: [], dueDate: invalid), "拒绝超范围关联待办")
            try check(store.library == before, "无效日期不能产生任务或消息")
            try check(store.send(text: "开会", taskID: nil, newTaskTitle: nil, drafts: [], dueDate: tomorrow), "选日期后正文应自动创建待办")
            let task = store.library.tasks.last!
            try check(task.title == "开会" && task.dueDate == tomorrow && store.library.messages.last?.taskID == task.id, "自动待办的标题、日期和消息关联必须正确")
            try check(store.send(text: "开会", taskID: nil, newTaskTitle: nil, drafts: [], dueDate: tomorrow), "同名事项合并")
            try check(store.library.tasks.filter { $0.title == "开会" }.count == 1 && store.library.progress(for: task.id).total == 2, "同名自动待办应合并关联气泡")
            let saved = store.library
            try check(!store.send(text: "  ", taskID: nil, newTaskTitle: nil, drafts: [], dueDate: tomorrow) && store.library == saved, "只选日期不能产生空待办")
            try check(store.send(text: "标题行\n详细内容", taskID: nil, newTaskTitle: nil, drafts: [], dueDate: tomorrow), "多行内容自动待办")
            try check(store.library.tasks.last?.title == "标题行" && store.library.messages.last?.text == "标题行\n详细内容", "第一行作为标题，完整正文保留")
        }
    }
    static func migration() throws {
        try withStore { store, folder in
            let id = UUID(), messageID = UUID()
            let old = "{\"version\":1,\"tasks\":[{\"id\":\"\(id.uuidString)\",\"title\":\"旧待办\",\"createdAt\":0}],\"messages\":[{\"id\":\"\(messageID.uuidString)\",\"createdAt\":0,\"text\":\"原记录\",\"taskID\":\"\(id.uuidString)\",\"attachments\":[],\"isProcessed\":false}]}"
            let data = Data(old.utf8)
            try data.write(to: folder.appendingPathComponent(LedgerStore.manifestName))
            try store.openFolder(folder)
            try check(store.library.tasks[0].dueDate == nil && !store.library.isComplete(id), "v1 默认值错误")
            store.toggleTask(id)
            try check(store.library.version == 4 && store.library.isComplete(id), "应升级并保留关联")
            let backup = try Data(contentsOf: folder.appendingPathComponent("ChatLedger.v1-backup.json"))
            try check(backup == data, "应保留未修改的旧文件备份")
            store.closeFolder(); try store.openFolder(folder)
            try check(store.library.messages[0].text == "原记录" && store.library.isComplete(id), "迁移后持久化错误")
        }
    }

    static func completionIdempotency() throws {
        try withStore { store, folder in
            try check(store.send(text: "第一条", taskID: nil, newTaskTitle: "阅读", drafts: []), "发送失败")
            let id = store.library.tasks[0].id
            try check(store.send(text: "第二条", taskID: id, newTaskTitle: nil, drafts: []), "发送失败")
            let first = store.library.messages[0].id
            store.complete(first)
            store.complete(first)
            try check(store.library.progress(for: id).done == 1 && !store.library.isComplete(id), "重复双击不能撤销或提前完成")
            store.complete(store.library.messages[1].id)
            try check(store.library.isComplete(id), "全部气泡完成应汇总")
            store.toggle(first)
            try check(!store.library.isComplete(id), "底部按钮仍可撤销")
            let before = store.library
            store.closeFolder(); try store.openFolder(folder)
            try check(store.library == before, "完成和撤销必须保存")
        }
    }

}
