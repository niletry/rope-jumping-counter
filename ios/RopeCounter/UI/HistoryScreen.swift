import SwiftUI
import RopeCore

struct HistoryScreen: View {
    @Bindable var store: WorkoutStore
    @State private var confirmClear = false

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if store.history.isEmpty {
                    Text("还没有训练记录").foregroundStyle(.secondary)
                } else {
                    List(store.history) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(record.mode.title).fontWeight(.bold)
                                Spacer()
                                Text("\(record.totalCount) 次").font(.title3).fontWeight(.bold).foregroundStyle(Color.accentColor)
                            }
                            Text(Self.formatter.string(from: Date(timeIntervalSince1970: Double(record.startedAtEpochMs) / 1_000)))
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Text("时长 \(formatClock(record.activeDurationMs))")
                                if record.mode != .free { Text("\(record.completedGroups)/\(record.plannedGroups) 组") }
                                Spacer()
                                Text(record.completed ? "已完成" : "提前结束").foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("训练记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: store.closeHistory) { Image(systemName: "chevron.left") }.accessibilityLabel("返回")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { confirmClear = true } label: { Image(systemName: "trash") }
                        .accessibilityLabel("清空记录").disabled(store.history.isEmpty)
                }
            }
            .alert("清空训练记录？", isPresented: $confirmClear) {
                Button("清空", role: .destructive) { store.clearHistory() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作无法撤销。")
            }
        }
    }
}
