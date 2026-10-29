import Foundation

/// Metadata only: the detector never receives or stores pasteboard contents.
struct CopyAttemptTracker {
    private(set) var pending = false
    private var baseline: Int = 0
    private var deadline: TimeInterval = 0
    private var lastCount: Int
    private var lastObservedAt: TimeInterval
    private var recentChange: (before: Int, after: Int, time: TimeInterval)?
    private var lastFeedback: TimeInterval = -.infinity
    init(count: Int, now: TimeInterval) { lastCount = count; lastObservedAt = now }

    mutating func arm(count: Int, eventTime: TimeInterval, now: TimeInterval, global: Bool) {
        baseline = count
        // Global NSEvent delivery is asynchronous; clipboard ownership may already have changed.
        if global, let change = recentChange, change.after == count,
           change.time >= eventTime, now - change.time <= 0.3 {
            baseline = change.before
        } else if global, lastCount != count, now - lastObservedAt <= 0.3 {
            baseline = lastCount
        }
        deadline = now + 0.95
        pending = true
    }
    mutating func observe(count: Int, hasTypes: Bool, now: TimeInterval) -> Bool {
        if count != lastCount { recentChange = (lastCount, count, now) }
        lastCount = count; lastObservedAt = now
        guard pending else { return false }
        guard now <= deadline else { pending = false; return false }
        guard count != baseline, hasTypes else { return false }
        pending = false
        guard now - lastFeedback >= 0.7 else { return false }
        lastFeedback = now
        return true
    }
}

enum EmojiSelection {
    static func values(_ input: String) -> [String] { input.filter { !$0.isWhitespace }.map(String.init) }
    static func error(_ input: String) -> String? {
        let characters = input.filter { !$0.isWhitespace }
        guard !characters.isEmpty else { return "请选择 1～5 个表情。" }
        guard characters.count <= 5 else { return "最多只能选择 5 个表情。" }
        guard characters.allSatisfy({ character in
            character.unicodeScalars.contains { scalar in
                scalar.properties.isEmojiPresentation || (scalar.value > 127 && scalar.properties.isEmoji)
            } || (character.unicodeScalars.contains { $0.value == 0x20E3 } && "0123456789#*".contains(character.unicodeScalars.first.map(String.init) ?? "!"))
        }) else { return "请只输入表情，可点击笑脸打开 Mac 表情面板。" }
        return nil
    }
}

enum CopyFeedbackEffect: String, CaseIterable, Identifiable {
    case confetti, brief
    var id: String { rawValue }
    var title: String { self == .confetti ? "小礼花" : "简洁提示" }
}
enum CopyConfettiContent: String, CaseIterable, Identifiable {
    case ribbons, emoji
    var id: String { rawValue }
    var title: String { self == .ribbons ? "默认彩带" : "自选表情" }
}
