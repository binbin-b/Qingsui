import AppKit
import SwiftUI

@MainActor
enum UserGuideWindow {
    private static var window: NSWindow?
    static func show() {
        if window == nil {
            let guide = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 510, height: 610),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            guide.title = "使用说明"
            guide.isReleasedWhenClosed = false
            guide.minSize = NSSize(width: 430, height: 450)
            let hosting = NSHostingView(rootView: UserGuideView())
            hosting.sizingOptions = []
            guide.contentView = hosting
            guide.center()
            window = guide
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct UserGuideView: View {
    @ObservedObject private var shortcuts = KeyboardShortcuts.shared
    private let sections: [(String, String, String)] = [
        ("bubble.left", "记录内容", "像聊天一样发送文字、图片、文件和链接。Enter 发送，Shift＋Enter 换行。"),
        ("at", "创建待办", "输入 @标题，按 Enter / Tab 选择已有待办或新建，再发送。一条消息最多关联一个待办。点击左侧待办或气泡内的 @待办名称进入后，新消息自动关联它；点“退出待办”恢复普通记录。"),
        ("checklist", "批量关联", "右键气泡选择“多选”，勾选多条后点“关联…”，选择待办、日期或标签。每次只关联一个日期或一个共同标签，原有标签保留。"),
        ("calendar", "安排日期", "选好日期后写下事情并发送，自动成为待办。也可输入 /1113，按 Enter 确认日期，再写内容。"),
        ("checkmark.circle", "标记完成", "双击气泡完成，绿色变灰；右键可以撤销。同一待办关联的消息全部完成后，待办自动完成；清单中的事项变绿、划线后散开，在“已完成”中可撤销。"),
        ("number", "标签输入", "输入 # 查看已有标签，输入 # 加空格后在小框内写标签。Tab 切换候选，Enter 确认标签，再写正文；可添加多个标签。"),
        ("line.3.horizontal.decrease.circle", "筛选与隐藏", "点击左侧标签或气泡内的 #标签进入合集，此时发送的消息自动带上该标签，输入框旁点“退出标签”恢复普通记录。右键标签可从全部消息中隐藏它。顶部筛选按钮管理隐藏项，点击“恢复显示”取消隐藏。"),
        ("sidebar.left", "展开待办", "左侧待办在固定区域内滚动，点击“展开全部”占满左栏。点击“收起”恢复标签和日历。"),
        ("pin", "置顶消息", "右键选择“置顶”，消息摘要会留在聊天顶部。点击摘要跳回原消息，右键可取消置顶。"),
        ("arrow.uturn.backward", "撤回与删除", "右键可撤回消息，点“重新编辑”将内容放回输入框。删除后可点“撤销”，也可从文件夹右键菜单打开“已删除消息”恢复。"),
        ("text.cursor", "选字复制", "用鼠标拖选气泡中的部分文字，也可继续拖到其他气泡，按 ⌘C 复制。较早消息需先加载。"),
        ("sparkles", "复制反馈", "在设置中开启，按 ⌘C 后检测到剪贴板更新，会在鼠标所在屏幕左下角显示反馈。礼花可选默认彩带，或从 Mac 表情面板选择 1～5 个表情并保存；可预览，支持简洁提示。全局生效需辅助功能授权，轻随需保持运行，不读取或保存复制内容。"),
        ("doc.text", "长消息与文件", "长消息自动折叠，点“展开阅读”在独立窗口查看、选字和复制全文。文件显示为卡片，点击打开；拖入或粘贴即可添加文件。"),
        ("magnifyingglass", "搜索", "点击顶部放大镜或使用搜索快捷键，搜索正文、待办、标签和文件名。搜索在当前筛选范围内进行，点小叉退出。"),
        ("gearshape", "主题与模式", "点击齿轮打开设置，当前主题为液态玻璃。在“主题”中可选择四种悬浮球样式，立即生效并记住。可切换日间或夜间模式；在“键盘快捷键”中点击组合键即可修改，Esc 取消，支持恢复默认。"),
        ("photo", "查看图片", "点击叠放图片打开预览，用左右箭头切换，外开图标打开原图，右上角小叉关闭。"),
        ("magnifyingglass", "查看记录", "点击待办查看相关消息，点击日历查看当天内容和安排。"),
        ("circle", "桌面悬浮球", "单击或停留展开待办，底部“快速记事”按 Enter 发送到主页面，不加入待办。按住球拖动，双击清单空白处收起。"),
        ("bell", "到期提醒", "到期事项会弹出提醒，点击后关闭。请保持应用运行。"),
        ("folder", "备份与导出", "点击左下角“备份”保存完整 ZIP，可解压后选作资料库恢复。“导出”生成可阅读记录、待办表格及附件；菜单“资料库”也可操作。"),
        ("rectangle.portrait", "侧边窄条", "右上角按钮将窗口收成窄条，保留输入框。手动调整的位置和大小会记住；再次展开时回到当前显示器中央。主窗口不会自动置顶。")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("轻随使用说明").font(.system(size: 21, weight: .semibold)).padding(22)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(sections, id: \.1) { icon, title, body in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Palette.accent).frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(title).font(.system(size: 13, weight: .semibold))
                                Text(body).font(.system(size: 12)).foregroundStyle(.secondary)
                                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("键盘快捷键").font(.system(size: 13, weight: .semibold))
                        Text("应用在前台时生效；可在设置中修改。新建待办／记事会展开悬浮清单并定位输入框。")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        ForEach(ShortcutAction.allCases) { action in
                            HStack {
                                Text(action.title)
                                Spacer()
                                Text(shortcuts.binding(action).display).monospaced()
                            }.font(.system(size: 12))
                        }
                    }
                }.padding(22)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
            .appAppearance()
    }
}
