import Foundation

struct LedgerTask: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var createdAt = Date()
    var dueDate: Date?
    var standaloneCompleted: Bool?
}

struct Attachment: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var filename: String
    var isImage: Bool
}

struct Message: Identifiable, Codable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var text: String
    var taskID: UUID?
    var attachments: [Attachment] = []
    var isProcessed = false
    var tags: [String]?
    var deletedAt: Date?
    var retractedAt: Date?
    var scheduledDate: Date?
    var pinnedAt: Date?
    var isActive: Bool { deletedAt == nil && retractedAt == nil }

}

struct Library: Codable, Equatable {
    var version = 4
    var tasks: [LedgerTask] = []
    var messages: [Message] = []

    func progress(for taskID: UUID) -> (done: Int, total: Int) {
        let related = messages.filter { $0.taskID == taskID && $0.isActive }
        return (related.filter(\.isProcessed).count, related.count)
    }

    func isComplete(_ taskID: UUID) -> Bool {
        let count = progress(for: taskID)
        return count.total > 0 ? count.done == count.total : tasks.first { $0.id == taskID }?.standaloneCompleted == true
    }

    func validate() throws {
        guard (1...4).contains(version) else { throw LedgerError.invalidLibrary("这个资料库的版本暂不支持。") }
        let ids = Set(tasks.map(\.id))
        guard ids.count == tasks.count, Set(messages.map(\.id)).count == messages.count,
              tasks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              messages.allSatisfy({ $0.taskID == nil || ids.contains($0.taskID!) }) else {
            throw LedgerError.invalidLibrary("记录或待办关联不完整，原文件未被修改。")
        }
        guard messages.flatMap(\.attachments).allSatisfy({
            !$0.filename.isEmpty && $0.filename != "." && $0.filename != ".." &&
            !$0.filename.contains("/") && !$0.filename.contains("\\")
        }) else { throw LedgerError.invalidLibrary("附件路径无效，原文件未被修改。") }
    }
}

enum LedgerError: LocalizedError {
    case invalidLibrary(String)
    case noFolder
    var errorDescription: String? {
        switch self {
        case .invalidLibrary(let detail): return detail
        case .noFolder: return "请先选择保存记录的文件夹。"
        }
    }
}

struct DraftAttachment: Identifiable {
    let id = UUID()
    let name: String
    let sourceURL: URL?
    let data: Data?
    let isImage: Bool
}

enum TimelineFilter: Equatable {
    case all
    case deleted
    case day(Date)
    case task(UUID)
    case tag(String)
}

struct TaskMention {
    let range: Range<String.Index>
    let query: String

    static func parse(_ text: String) -> TaskMention? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        let after = text.index(after: at)
        let tagStart = text[after...].indices.first { i in text[i] == "#" && i > after && text[text.index(before: i)].isWhitespace }
        let end = tagStart ?? text.endIndex
        let suffix = String(text[after..<end])
        if at != text.startIndex {
            let previous = text[text.index(before: at)]
            // Ignore conventional email addresses, but allow Chinese text directly before @.
            if previous.isASCII && (previous.isLetter || previous.isNumber || "._%+-".contains(previous)),
               suffix.contains("."), !suffix.contains(where: \.isWhitespace) { return nil }
        }
        guard !suffix.contains("\n") else { return nil }
        return TaskMention(range: at..<end,
                           query: suffix.trimmingCharacters(in: .whitespaces))
    }
}

struct DateMention {
    let range: Range<String.Index>
    let query: String
    static func parse(_ text: String) -> DateMention? {
        guard let slash = text.lastIndex(of: "/") else { return nil }
        if slash != text.startIndex && !text[text.index(before: slash)].isWhitespace { return nil }
        let suffix = text[text.index(after: slash)...]
        guard !suffix.contains("\n") else { return nil }
        let query = suffix.trimmingCharacters(in: .whitespaces)
        guard query.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        return DateMention(range: slash..<text.endIndex, query: query)
    }
    static func isAllowed(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        let limit = calendar.date(byAdding: .year, value: 1, to: today)!
        let day = calendar.startOfDay(for: date)
        return day >= today && day <= limit
    }

    static func date(_ digits: String, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard digits.count == 4, digits.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        let month = Int(digits.prefix(2))!, day = Int(digits.suffix(2))!
        let thisYear = calendar.component(.year, from: now)
        for year in thisYear...(thisYear + 1) {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  calendar.component(.year, from: date) == year,
                  calendar.component(.month, from: date) == month,
                  calendar.component(.day, from: date) == day,
                  isAllowed(date, now: now, calendar: calendar) else { continue }
            return date
        }
        return nil
    }
}

struct TaskSavedNotice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let dueDate: Date?
    let caption: String
    let taskID: UUID
    var messageID: UUID? = nil
}

struct TagMention {
    static func extract(_ text: String) -> (body: String, tags: [String]) {
        let regex = try! NSRegularExpression(pattern: "(?<!\\S)#[\\p{L}\\p{N}_-]+")
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let tags = matches.compactMap { Range($0.range, in: text).map { String(text[$0].dropFirst()) } }
        var body = text
        for match in matches.reversed() { if let range = Range(match.range, in: body) { body.removeSubrange(range) } }
        return (body.trimmingCharacters(in: .whitespacesAndNewlines), Array(Set(tags)).sorted())
    }
}

struct TagInputToken {
    let range: Range<String.Index>
    let query: String
    static func parse(_ text: String) -> TagInputToken? {
        guard let hash = text.lastIndex(of: "#"), hash == text.startIndex || text[text.index(before: hash)].isWhitespace else { return nil }
        let suffix = text[text.index(after: hash)...]
        guard !suffix.contains(where: \.isNewline) else { return nil }
        let query = suffix.trimmingCharacters(in: .whitespaces)
        guard !query.contains(where: \.isWhitespace) else { return nil }
        return TagInputToken(range: hash..<text.endIndex, query: query)
    }
}

struct MessagePresentation {
    static func isLong(_ text: String) -> Bool { text.count > 600 || text.lazy.filter { $0 == "\n" }.prefix(12).count >= 12 }
    static func preview(_ text: String) -> String {
        guard isLong(text) else { return text }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).prefix(8).joined(separator: "\n")
        return String(lines.prefix(320)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
struct MessageSearch {
    static func matches(_ message: Message, taskTitle: String?, query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return true }
        if message.retractedAt != nil { return terms.allSatisfy { "消息已撤回".localizedCaseInsensitiveContains($0) } }
        let fields = [message.text, taskTitle ?? ""] + (message.tags ?? []).map { "# " + $0 } + message.attachments.map(\.name)
        return terms.allSatisfy { term in fields.contains { $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil } }
    }
}
