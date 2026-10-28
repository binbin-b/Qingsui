import SwiftUI

enum BulkAction: String, Identifiable { case task, date, tag; var id: String { rawValue } }
struct BulkMetadataPicker: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let kind: BulkAction
    let messageIDs: Set<UUID>
    var finished: () -> Void
    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var tag = ""
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("为 \(messageIDs.count) 条消息关联\(kind == .date ? "日期" : "标签")").font(.headline)
                Spacer(); Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            if kind == .date {
                DatePicker("同一天", selection: $date, in: today...Calendar.current.date(byAdding: .year, value: 1, to: today)!, displayedComponents: [.date]).datePickerStyle(.graphical)
                Text("只修改选中的消息，原有待办日期保持不变。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("关联这个日期") { if store.assignDate(to: messageIDs, date: date) { finished() } }.frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                HStack {
                    TextField("一个标签名称", text: $tag).textFieldStyle(.roundedBorder).onSubmit { applyTag(tag) }
                    Button("添加并关联") { applyTag(tag) }.disabled(tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("每次添加一个共同标签，保留原有标签。").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(store.tags.filter { tag.isEmpty || $0.localizedCaseInsensitiveContains(tag) }, id: \.self) { value in
                            Button { applyTag(value) } label: { Text("# " + value).frame(maxWidth: .infinity, alignment: .leading).padding(7) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(18).frame(width: 370, height: 370)
    }
    private func applyTag(_ value: String) { if store.assignTag(to: messageIDs, tag: value) { finished() } }
}
