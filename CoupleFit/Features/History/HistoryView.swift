import SwiftUI

// MARK: - 历史记录
//
// 跨文件依赖（由 Record 模块并行编写，本文件只引用、不定义）：
//   CoupleFit/Features/Record/RecordEditSheet.swift
//     · enum RecordEditMode: Identifiable —— 含 .edit(ExerciseRecord) case
//     · struct RecordEditSheet: View —— 构造方式 RecordEditSheet(mode: RecordEditMode)
//   本文件统一以 RecordEditSheet(mode: .edit(record)) 这一最简形式引用，
//   通过 .sheet(item:) 传入具体的 ExerciseRecord（ExerciseRecord 本身也是 Identifiable）。

struct HistoryView: View {

    @Environment(AppState.self) private var appState

    @State private var selection: PersonTab = .me
    @State private var pendingDelete: ExerciseRecord?
    @State private var editingRecord: ExerciseRecord?
    @State private var isDeleting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                content
            }
            .navigationTitle("历史")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await appState.refreshAll()
            }
            .overlay {
                if isDeleting {
                    ProgressView()
                        .padding(20)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 8)
                }
            }
            // 编辑：item 为具体的记录，构造 sheet 时使用最简形式
            .sheet(item: $editingRecord) { record in
                RecordEditSheet(mode: .edit(record))
            }
            // 删除：二次确认
            .confirmationDialog("删除记录",
                                isPresented: isConfirmingDelete,
                                presenting: pendingDelete) { record in
                Button("删除", role: .destructive) {
                    Task { await delete(record) }
                }
                Button("取消", role: .cancel) {
                    pendingDelete = nil
                }
            } message: { record in
                Text("将删除 \(record.startDate.historyTimeText) 的\(record.exerciseType.displayName)记录，删除后无法恢复。")
            }
            .toast(toastBinding)
            .alert("出错了", isPresented: isShowingError) {
                Button("知道了", role: .cancel) {
                    appState.errorMessage = nil
                }
            } message: {
                Text(appState.errorMessage ?? "")
            }
        }
    }

    // MARK: - 顶部汇总

    private var header: some View {
        VStack(spacing: 12) {
            PersonSegmentedPicker(selection: $selection,
                                  partnerName: appState.partnerProfile?.displayName ?? "对方")
            HStack(spacing: 12) {
                DataPill(title: "本周总时长",
                         value: weekTotalSeconds.formattedDuration,
                         tint: currentExerciseType.accentColor)
                DataPill(title: "本周总次数",
                         value: "\(weekTotalCount) \(currentExerciseType.unitName)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 列表

    @ViewBuilder
    private var content: some View {
        if groups.isEmpty {
            List {
                EmptyStateView(
                    systemImage: "clock.arrow.circlepath",
                    title: selection == .me ? "还没有运动记录" : "\(partnerName)还没有记录",
                    subtitle: selection == .me ? "完成一次运动后，记录会出现在这里" : "等 TA 完成第一次打卡吧"
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
        } else {
            List {
                ForEach(groups, id: \.dateString) { group in
                    Section {
                        ForEach(group.records) { record in
                            row(for: record)
                        }
                    } header: {
                        Text(DateHelper.groupTitle(for: group.dateString))
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private func row(for record: ExerciseRecord) -> some View {
        if selection == .me {
            recordRow(record)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDelete = record
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    Button {
                        editingRecord = record
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
        } else {
            // 查看对方记录时不可编辑 / 删除
            recordRow(record)
        }
    }

    private func recordRow(_ record: ExerciseRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: record.exerciseType.systemImage)
                    .foregroundStyle(record.exerciseType.accentColor)
                Text(timeRangeText(record))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Spacer(minLength: 8)
                Text(record.durationText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                Label("\(record.count) \(record.exerciseType.unitName)", systemImage: "repeat")
                if let calories = record.calories, calories > 0 {
                    Label(String(format: "%.0f kcal", calories), systemImage: "flame")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let note = record.note, !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 数据派生

    private var groups: [(dateString: String, records: [ExerciseRecord])] {
        selection == .me ? appState.myGroupedHistory : appState.partnerGroupedHistory
    }

    private var weekSummaries: [DailySummary] {
        selection == .me ? appState.myWeekSummaries : appState.partnerWeekSummaries
    }

    private var weekTotalSeconds: Int {
        weekSummaries.reduce(0) { $0 + $1.durationSeconds }
    }

    private var weekTotalCount: Int {
        weekSummaries.reduce(0) { $0 + $1.count }
    }

    private var currentExerciseType: ExerciseType {
        (selection == .me ? appState.myProfile : appState.partnerProfile)?.exerciseType ?? .hulaHoop
    }

    private var partnerName: String {
        appState.partnerProfile?.displayName ?? "对方"
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )
    }

    private var toastBinding: Binding<String?> {
        Binding(
            get: { appState.toastMessage },
            set: { appState.toastMessage = $0 }
        )
    }

    // MARK: - 操作

    @MainActor
    private func delete(_ record: ExerciseRecord) async {
        withAnimation {
            pendingDelete = nil
            isDeleting = true
        }
        defer { isDeleting = false }

        do {
            try await FirestoreService.shared.deleteRecord(record)
            withAnimation {
                appState.myRecentRecords.removeAll { $0.id == record.id }
                appState.myTodayRecords.removeAll { $0.id == record.id }
            }
            appState.toastMessage = "已删除记录"
        } catch {
            appState.errorMessage = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func timeRangeText(_ record: ExerciseRecord) -> String {
        let start = DateHelper.timeFormatter.string(from: record.startDate)
        let end = DateHelper.timeFormatter.string(from: record.endDate)
        return "\(start)~\(end)"
    }
}

// MARK: - 小工具

private extension Date {
    /// "14:05"，用于删除确认文案
    var historyTimeText: String {
        DateHelper.timeFormatter.string(from: self)
    }
}

#Preview {
    HistoryView()
        .environment(AppState())
}
