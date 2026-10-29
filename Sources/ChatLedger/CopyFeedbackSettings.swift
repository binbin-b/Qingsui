import AppKit
import SwiftUI

struct CopyFeedbackSettings: View {
    @ObservedObject private var feedback = CopyFeedback.shared
    @State private var draft = ""
    @State private var emojiError: String?
    var body: some View {
        Section("复制反馈") {
            Toggle("开启复制反馈", isOn: $feedback.enabled)
            Toggle("在其他 App 中也生效", isOn: $feedback.globalEnabled).disabled(!feedback.enabled)
            if feedback.enabled {
                Text(feedback.globalListening ? "全局监听已开启" : "当前仅在轻随内生效")
                    .font(.caption).foregroundStyle(.secondary)
                if feedback.globalEnabled && !feedback.trusted {
                    Button("授权辅助功能…") { feedback.openPermissionSettings() }
                    Text("在系统设置中允许轻随后，返回这里即可。未授权时仍可在轻随内使用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Picker("反馈方式", selection: $feedback.effect) {
                ForEach(CopyFeedbackEffect.allCases) { Text($0.title).tag($0) }
            }
            if feedback.effect == .confetti {
                Picker("礼花内容", selection: $feedback.content) {
                    ForEach(CopyConfettiContent.allCases) { Text($0.title).tag($0) }
                }
                if feedback.content == .emoji {
                    HStack {
                        TextField("选择 1～5 个表情", text: $draft).autocorrectionDisabled(true)
                            .onSubmit(saveEmoji).accessibilityLabel("礼花表情，最多五个")
                        Button { NSApp.orderFrontCharacterPalette(nil) } label: { Image(systemName: "face.smiling") }
                            .help("打开 Mac 表情与符号面板").accessibilityLabel("选择 Mac 表情")
                        Button("保存") { saveEmoji() }.disabled(EmojiSelection.error(draft) != nil)
                    }
                    Text(emojiError ?? "最多 5 个，选 1 个也可以；修改后点击保存。")
                        .font(.caption).foregroundStyle(emojiError == nil ? Color.secondary : .red)
                }
            }
            HStack {
                Text("鼠标所在屏幕左下角").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("预览效果") { feedback.preview() }
            }
            Text("按下 ⌘C 后检测剪贴板更新，不读取或保存复制内容。连续复制会限制动画频率；系统开启“减少动态效果”时使用简洁提示。")
                .font(.caption).foregroundStyle(.secondary)
        }.onAppear { draft = feedback.emoji }
            .onChange(of: draft) { _, value in emojiError = EmojiSelection.error(value) }
    }
    private func saveEmoji() {
        emojiError = EmojiSelection.error(draft)
        if emojiError == nil, feedback.saveEmoji(draft) { draft = feedback.emoji }
    }
}
