import FirebaseFirestore
import Foundation
import SwiftUI

// MARK: - 编辑模式

/// 三种使用场景：计时结束后保存 / 手动补录 / 编辑已有记录。
/// 遵循 Identifiable，便于用 `.sheet(item:)` 呈现。
enum RecordEditMode: Identifiable {
    case create(startTime: Date, endTime: Date, durationSeconds: Int, count: Int, exerciseType: ExerciseType)
    case manual(exerciseType: ExerciseType)
    case edit(ExerciseRecord)

    var id: String {
        switch self {
        case .create(let startTime, _, let durationSeconds, let count, let exerciseType):
            return "create-\(startTime.timeIntervalSince1970)-\(durationSeconds)-\(count)-\(exerciseType.rawValue)"
        case .manual(let exerciseType):
            return "manual-\(exerciseType.rawValue)"
        case .edit(let record):
            return "edit-\(record.id ?? UUID().uuidString)"
        }
    }

    /// 计时模式下时长由计时器给出，只读展示
    var isDurationEditable: Bool { !isCreate }

    /// 计时模式记录的开始时间同样来自计时器，只读展示
    var isDateEditable: Bool { !isCreate }

    var isCreate: Bool {
        if case .create = self { return true }
        return false
    }

    var navigationTitle: String {
        switch self {
        case .create: return "保存本次运动"
        case .manual: return "手动补录"
        case .edit: return "编辑记录"
        }
    }
}

// MARK: - 记录编辑表单

struct RecordEditSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let mode: RecordEditMode
    /// 保存成功后的回调（计时器页用它来一起关闭自己）
    var onSaved: (() -> Void)? = nil

    @State private var startTime: Date
    @State private var durationMinutes: Int
    @State private var durationSeconds: Int
    @State private var countText: String
    @State private var caloriesText: String
    @State private var manualCalories: Bool
    @State private var note: String
    @State private var exerciseType: ExerciseType

    @State private var isSaving = false
    @State private var errorMessage: String?

    private let noteLimit = 100

    init(mode: RecordEditMode, onSaved: (() -> Void)? = nil) {
        self.mode = mode
        self.onSaved = onSaved

        switch mode {
        case .create(let start, _, let duration, let count, let type):
            _startTime = State(initialValue: start)
            _durationMinutes = State(initialValue: duration / 60)
            _durationSeconds = State(initialValue: duration % 60)
            _countText = State(initialValue: count > 0 ? String(count) : "")
            _manualCalories = State(initialValue: false)
            _caloriesText = State(initialValue: Self.caloriesString(
                CalorieEstimator.estimate(exerciseType: type, durationSeconds: duration)))
            _exerciseType = State(initialValue: type)
            _note = State(initialValue: "")

        case .manual(let type):
            _startTime = State(initialValue: Date())
            _durationMinutes = State(initialValue: Constants.defaultDailyDurationSeconds / 60)
            _durationSeconds = State(initialValue: 0)
            _countText = State(initialValue: "")
            _manualCalories = State(initialValue: false)
            _caloriesText = State(initialValue: "")
            _exerciseType = State(initialValue: type)
            _note = State(initialValue: "")

        case .edit(let record):
            _startTime = State(initialValue: record.startTime.dateValue())
            _durationMinutes = State(initialValue: record.durationSeconds / 60)
            _durationSeconds = State(initialValue: record.durationSeconds % 60)
            _countText = State(initialValue: record.count > 0 ? String(record.count) : "")
            if let calories = record.calories {
                _manualCalories = State(initialValue: true)
                _caloriesText = State(initialValue: Self.caloriesString(calories))
            } else {
                _manualCalories = State(initialValue: false)
                _caloriesText = State(initialValue: "")
            }
            _exerciseType = State(initialValue: record.exerciseType)
            _note = State(initialValue: record.note ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                durationSection
                countSection
                dateSection
                calorieSection
                noteSection
            }
            .navigationTitle(mode.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .disabled(isSaving)
        }
        .interactiveDismissDisabled(isSaving)
        .alert("无法保存", isPresented: isShowingError) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: 表单分区

    private var durationSection: some View {
        Section("时长") {
            if mode.isDurationEditable {
                HStack(alignment: .center, spacing: 0) {
                    minutePicker
                    secondPicker
                }
                .frame(height: 130)
            } else {
                // 计时模式下时长来自计时器，只读
                LabeledContent("时长", value: totalDurationSeconds.formattedDuration)
            }
            LabeledContent("合计", value: "\(totalDurationSeconds.minutesText)\(durationSeconds > 0 ? " \(durationSeconds) 秒" : "")")
        }
    }

    private var minutePicker: some View {
        Picker("分钟", selection: $durationMinutes) {
            ForEach(0...180, id: \.self) { minute in
                Text("\(minute) 分").tag(minute)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var secondPicker: some View {
        Picker("秒", selection: $durationSeconds) {
            ForEach(0...59, id: \.self) { second in
                Text("\(second) 秒").tag(second)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var countSection: some View {
        Section {
            HStack {
                Text(exerciseType.unitName)
                    .foregroundStyle(.secondary)
                TextField("0", text: $countText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("次数 / \(exerciseType.unitName)数")
        } footer: {
            Text("留空按 0 计。运动类型是 \(exerciseType.displayName)。")
        }
    }

    private var dateSection: some View {
        // 注意：SwiftUI 没有 Section(标题) + content + footer 的重载，
        // 带 header/footer 时必须用 Section { } header: { } footer: { } 的写法
        Section {
            if mode.isDateEditable {
                DatePicker("开始时间",
                           selection: $startTime,
                           displayedComponents: [.date, .hourAndMinute])
            } else {
                LabeledContent("开始时间", value: DateHelper.timeFormatter.string(from: startTime))
            }
            LabeledContent("归属日期", value: resolvedDateString)
        } header: {
            Text("日期")
        } footer: {
            Text("记录归属到开始时间的本地日期（\(resolvedDateString)）。")
        }
    }

    private var calorieSection: some View {
        Section("卡路里") {
            Toggle("手动填写", isOn: $manualCalories)
            if manualCalories {
                HStack {
                    TextField("0", text: $caloriesText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("kcal").foregroundStyle(.secondary)
                }
            } else {
                LabeledContent("估算", value: CalorieEstimator.text(exerciseType: exerciseType,
                                                                   durationSeconds: totalDurationSeconds))
            }
        }
    }

    private var noteSection: some View {
        Section {
            TextField("今天感觉怎么样？（选填）", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .onChange(of: note) { _, newValue in
                    if newValue.count > noteLimit {
                        note = String(newValue.prefix(noteLimit))
                    }
                }
        } header: {
            Text("备注")
        } footer: {
            Text("\(note.count)/\(noteLimit)")
        }
    }

    // MARK: 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
                .disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView()
            } else {
                Button("保存") {
                    Task { await save() }
                }
                .disabled(!isValid)
            }
        }
    }

    // MARK: 派生数据

    private var totalDurationSeconds: Int { durationMinutes * 60 + durationSeconds }

    private var resolvedCount: Int { Int(countText.trimmingCharacters(in: .whitespaces)) ?? 0 }

    private var resolvedDateString: String { DateHelper.dateString(from: startTime) }

    private var isValid: Bool {
        guard totalDurationSeconds > 0 else { return false }
        guard resolvedCount >= 0 else { return false }
        return true
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    /// 手动填写时优先用输入值，解析失败或关闭开关时回退到估算值
    private var resolvedCalories: Double {
        if manualCalories {
            let parsed = Double(caloriesText.trimmingCharacters(in: .whitespaces))
            if let parsed { return parsed }
        }
        return CalorieEstimator.estimate(exerciseType: exerciseType,
                                         durationSeconds: totalDurationSeconds)
    }

    private static func caloriesString(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    // MARK: 保存

    @MainActor
    private func save() async {
        guard let uid = appState.uid else {
            errorMessage = AppError.notSignedIn.errorDescription
            return
        }
        guard totalDurationSeconds > 0 else {
            errorMessage = "时长需要大于 0"
            return
        }
        guard resolvedCount >= 0 else {
            errorMessage = "次数不能为负数"
            return
        }

        isSaving = true
        defer { isSaving = false }

        let dateString = resolvedDateString
        let endTime = startTime.addingTimeInterval(Double(totalDurationSeconds))
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let calories: Double? = resolvedCalories

        do {
            switch mode {
            case .create, .manual:
                let record = ExerciseRecord(
                    userId: uid,
                    exerciseType: exerciseType,
                    dateString: dateString,
                    startTime: startTime,
                    endTime: endTime,
                    durationSeconds: totalDurationSeconds,
                    count: resolvedCount,
                    calories: calories,
                    note: trimmedNote.isEmpty ? nil : trimmedNote
                )
                try await FirestoreService.shared.addRecord(record)
                appState.toastMessage = "记录已保存 🎉"

            case .edit(let original):
                var updated = original
                updated.exerciseType = exerciseType
                updated.dateString = dateString
                updated.startTime = Timestamp(date: startTime)
                updated.endTime = Timestamp(date: endTime)
                updated.durationSeconds = totalDurationSeconds
                updated.count = resolvedCount
                updated.calories = calories
                updated.note = trimmedNote.isEmpty ? nil : trimmedNote
                try await FirestoreService.shared.updateRecord(updated)
                appState.toastMessage = "修改已保存"
            }

            appState.refreshDayBoundaryIfNeeded()
            onSaved?()
            dismiss()
        } catch {
            errorMessage = (error as NSError).friendlyAuthMessage
        }
    }
}

#Preview {
    RecordEditSheet(mode: .manual(exerciseType: .hulaHoop))
        .environment(AppState())
}

#Preview {
    RecordEditSheet(
        mode: .create(startTime: Date().addingTimeInterval(-900),
                      endTime: Date(),
                      durationSeconds: 900,
                      count: 240,
                      exerciseType: .jump)
    )
    .environment(AppState())
}
