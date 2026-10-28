import AppKit
import UniformTypeIdentifiers

struct ArchiveService {
    enum Kind: Sendable { case backup, export }
    static func dayString(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    static func create(library: Library, source: URL, destination: URL, kind: Kind) throws {
        try library.validate()
        let sourcePath = source.standardizedFileURL.resolvingSymlinksInPath().path
        let destinationPath = destination.standardizedFileURL.resolvingSymlinksInPath().path
        guard destinationPath != sourcePath, !destinationPath.hasPrefix(sourcePath + "/") else {
            throw LedgerError.invalidLibrary("请将备份或导出保存在资料库文件夹之外。")
        }
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory.appendingPathComponent("Qingsui-Archive-" + UUID().uuidString)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: temporary) }
        let package = temporary.appendingPathComponent(kind == .backup ? "轻随备份" : "轻随导出")
        try manager.createDirectory(at: package, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if kind == .backup {
            for item in try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                // Archives are outputs, never recursively included in future backups.
                guard item.pathExtension.lowercased() != "zip", item.lastPathComponent != LedgerStore.manifestName else { continue }
                try manager.copyItem(at: item, to: package.appendingPathComponent(item.lastPathComponent))
            }
            try encoder.encode(library).write(to: package.appendingPathComponent(LedgerStore.manifestName), options: .atomic)
            try "完整资料库备份。恢复时先解压，再在轻随中选择这个文件夹。包含消息、待办、标签、已删除记录与附件。\n".write(to: package.appendingPathComponent("恢复说明.txt"), atomically: true, encoding: .utf8)
        } else {
            let messages = library.messages.filter(\.isActive).sorted { $0.createdAt < $1.createdAt }
            var markdown = "# 轻随记录\n\n"
            for message in messages {
                markdown += "## " + message.createdAt.formatted(date: .numeric, time: .shortened) + "\n\n"
                if let task = library.tasks.first(where: { $0.id == message.taskID }) { markdown += "待办：" + task.title + "\n\n" }
                if let scheduled = message.scheduledDate { markdown += "安排日期：" + dayString(scheduled) + "\n\n" }
                markdown += (message.isProcessed ? "状态：已完成\n\n" : "状态：未完成\n\n") + message.text + "\n\n"
                if let tags = message.tags, !tags.isEmpty { markdown += tags.map { "#" + $0 }.joined(separator: " ") + "\n\n" }
                for attachment in message.attachments {
                    let folder = package.appendingPathComponent("Attachments")
                    try manager.createDirectory(at: folder, withIntermediateDirectories: true)
                    let target = folder.appendingPathComponent(attachment.filename)
                    if !manager.fileExists(atPath: target.path) { try manager.copyItem(at: source.appendingPathComponent("Attachments").appendingPathComponent(attachment.filename), to: target) }
                    markdown += "[" + attachment.name.replacingOccurrences(of: "]", with: "\\]") + "](Attachments/" + attachment.filename + ")\n\n"
                }
            }
            try markdown.write(to: package.appendingPathComponent("记录.md"), atomically: true, encoding: .utf8)
            try encoder.encode(messages).write(to: package.appendingPathComponent("消息.json"))
            func csv(_ value: String) -> String {
                let safe = ["=", "+", "-", "@"].contains(String(value.prefix(1))) ? "'" + value : value
                return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            var rows = ["标题,日期,完成状态"]
            rows += library.tasks.map { task in [task.title, task.dueDate.map { dayString($0) } ?? "", library.isComplete(task.id) ? "已完成" : "未完成"].map(csv).joined(separator: ",") }
            try ("\u{feff}" + rows.joined(separator: "\r\n")).write(to: package.appendingPathComponent("待办.csv"), atomically: true, encoding: .utf8)
            try "记录.md 可直接阅读；待办.csv 可用表格软件打开；消息.json 供其他工具使用。导出包含全部未删除、未撤回消息，不受筛选影响。要完整恢复资料库请使用备份。\n".write(to: package.appendingPathComponent("导出说明.txt"), atomically: true, encoding: .utf8)
        }
        let zip = temporary.appendingPathComponent("result.zip")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", package.path, zip.path]
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw LedgerError.invalidLibrary("压缩失败，原资料未被修改。") }
        // Atomic replacement of the finished archive; never touch the source library.
        let data = try Data(contentsOf: zip, options: .mappedIfSafe)
        try data.write(to: destination, options: .atomic)
    }
}

extension LedgerStore {
    func chooseArchive(_ kind: ArchiveService.Kind) {
        guard let folder, !archiveBusy else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.zip]
        panel.directoryURL = folder.deletingLastPathComponent()
        panel.title = kind == .backup ? "备份完整资料库" : "导出记录与附件"
        let stamp = ArchiveService.dayString(Date())
        panel.nameFieldStringValue = "轻随-" + (kind == .backup ? "备份-" : "导出-") + stamp + ".zip"
        guard let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.title == "轻随" }) else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let destination = panel.url else { return }
            let source = folder.standardizedFileURL.resolvingSymlinksInPath()
            let target = destination.standardizedFileURL.resolvingSymlinksInPath()
            guard !target.path.hasPrefix(source.path + "/") else { self.errorMessage = "请选择资料库文件夹之外的位置保存，避免备份重复包含自己。"; return }
            self.archiveBusy = true
            let snapshot = self.library
            Task {
                do {
                    try await Task.detached(priority: .utility) { try ArchiveService.create(library: snapshot, source: folder, destination: destination, kind: kind) }.value
                    self.archiveStatus = kind == .backup ? "备份已保存" : "导出已保存"
                    NSWorkspace.shared.activateFileViewerSelecting([destination])
                } catch { self.errorMessage = "未能完成：" + error.localizedDescription }
                self.archiveBusy = false
            }
        }
    }
}
