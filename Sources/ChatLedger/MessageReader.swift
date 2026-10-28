import SwiftUI
import AppKit

struct FileAttachmentCard: View {
    @EnvironmentObject var store: LedgerStore
    let attachment: Attachment
    var width: CGFloat = 250
    var action: (() -> Void)?
    @State private var size: String?
    private var ext: String { (attachment.name as NSString).pathExtension.uppercased() }
    private var symbol: String {
        switch ext {
        case "PDF": return "doc.richtext"
        case "ZIP", "RAR", "7Z": return "archivebox"
        case "XLS", "XLSX", "CSV": return "tablecells"
        case "PPT", "PPTX", "KEY": return "rectangle.on.rectangle"
        default: return "doc.text"
        }
    }
    var body: some View {
        Button { if let action { action() } else { store.openAttachment(attachment) } } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 25)).foregroundStyle(Palette.accent).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(attachment.name).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                    Text([ext.isEmpty ? "文件" : ext, size].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(9).frame(width: max(120, width), alignment: .leading)
                .background(Palette.fileCard, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.accent.opacity(0.20), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).help("打开文件：" + attachment.name).accessibilityLabel("文件：" + attachment.name)
            .task(id: store.attachmentURL(attachment)) {
                guard let url = store.attachmentURL(attachment) else { return }
                let bytes = await Task.detached(priority: .utility) { try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize }.value
                size = bytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
            }
    }
}

@MainActor enum MessageReaderWindow {
    private static var window: NSWindow?
    private static var currentID: UUID?
    static func show(_ id: UUID, store: LedgerStore) {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 680), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            panel.title = "消息阅读"; panel.minSize = NSSize(width: 400, height: 360); panel.isReleasedWhenClosed = false
            panel.center(); window = panel
        }
        if currentID != id || window?.contentView == nil {
            let host = NSHostingView(rootView: MessageDocument(messageID: id).environmentObject(store).appAppearance()); host.sizingOptions = []
            window?.contentView = host; currentID = id
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
}
struct MessageDocument: View {
    @EnvironmentObject var store: LedgerStore
    let messageID: UUID
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message = store.library.messages.first(where: { $0.id == messageID }), message.isActive {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.library.tasks.first { $0.id == message.taskID }?.title ?? "消息").font(.headline).lineLimit(2)
                        Text(message.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(message.isProcessed ? "撤销完成" : "标记完成") { store.toggle(message.id) }
                }
                Divider()
                DocumentText(text: message.text).frame(maxWidth: .infinity, maxHeight: .infinity)
                if !(message.tags ?? []).isEmpty { Text((message.tags ?? []).map { "# " + $0 }.joined(separator: "   ")).font(.caption).foregroundStyle(Palette.accent) }
                if !message.attachments.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 9) {
                            let images = message.attachments.filter(\.isImage)
                            if !images.isEmpty { ImageStack(attachments: images) }
                            ForEach(message.attachments.filter { !$0.isImage }) { FileAttachmentCard(attachment: $0) }
                        }.padding(3)
                    }.frame(maxHeight: message.attachments.contains(where: \.isImage) ? 140 : 74)
                }
            } else { Text("这条消息已撤回、删除，或资料库已切换。").foregroundStyle(.secondary); Spacer() }
        }.padding(22).background(Palette.canvas)
    }
}
struct DocumentText: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.scrollerStyle = .overlay; scroll.drawsBackground = false
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.isEditable = false; view.isSelectable = true; view.isRichText = true; view.drawsBackground = false
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false; view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true; view.textContainer?.containerSize.height = .greatestFiniteMagnitude
        view.textContainerInset = NSSize(width: 2, height: 8); view.setAccessibilityLabel("消息全文")
        scroll.documentView = view; return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 6; paragraph.paragraphSpacing = 9
        let value = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: text, range: NSRange(location: 0, length: value.length)) {
                if let url = match.url { value.addAttribute(.link, value: url, range: match.range) }
            }
        }
        view.textStorage?.setAttributedString(value)
        view.linkTextAttributes = [.foregroundColor: NSColor.linkColor]
    }
}
