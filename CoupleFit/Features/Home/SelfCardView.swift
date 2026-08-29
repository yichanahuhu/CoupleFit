import SwiftUI

// MARK: - 我的今日卡片

/// 展示我今天的运动汇总与目标完成度，并提供「开始运动」「手动补录」两个入口。
struct SelfCardView: View {

    @Environment(AppState.self) private var appState
    /// 由 HomeView 传入，用于跳到设置页；未接入时为 nil，退化成文字提示
    @Binding var selectedTab: MainTabView.Tab

    @State private var showTimer = false
    @State private var editMode: RecordEditMode?

    init(selectedTab: Binding<MainTabView.Tab>) {
        self._selectedTab = selectedTab
    }

    private var exerciseType: ExerciseType { appState.myProfile?.exerciseType ?? .hulaHoop }

    private var displayName: String {
        let name = appState.myProfile?.displayName ?? ""
        return name.isEmpty ? "我" : name
    }

    private var summary: DailySummary { appState.mySummary }
    private var goal: Goal? { appState.myGoal }
    private var progress: Double { summary.overallProgress(goal: goal) }
    private var hasRecords: Bool { summary.recordCount > 0 }

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                header
                ringSection
                if hasRecords {
                    pillsSection
                } else {
                    emptySection
                }
                actionButtons
            }
        }
        .fullScreenCover(isPresented: $showTimer) {
            TimerView(exerciseType: exerciseType)
        }
        .sheet(item: $editMode) { mode in
            RecordEditSheet(mode: mode)
        }
    }

    // MARK: 分区

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.headline)
                Text("今天也要动起来")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            typeTag
        }
    }

    private var typeTag: some View {
        Label(exerciseType.displayName, systemImage: exerciseType.systemImage)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(exerciseType.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(exerciseType.accentColor)
    }

    private var ringSection: some View {
        VStack(spacing: 10) {
            ProgressRingView(
                progress: progress,
                lineWidth: 14,
                tint: exerciseType.accentColor,
                label: "\(Int((progress * 100).rounded()))%",
                sublabel: goal == nil ? "未设目标" : "今日完成度"
            )
            .frame(maxWidth: 150)
            .frame(maxWidth: .infinity)

            if let goal {
                Text("目标 \(goal.dailyDurationSeconds.minutesText) · \(goal.dailyCount) \(exerciseType.unitName)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button("去设置目标") { openSettings() }
                    .font(.footnote)
                    .buttonStyle(.borderedProminent)
                    .tint(exerciseType.accentColor)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var pillsSection: some View {
        HStack(alignment: .top, spacing: 8) {
            DataPill(title: "时长", value: summary.durationText, tint: exerciseType.accentColor)
            DataPill(title: exerciseType.unitName + "数",
                     value: "\(summary.count) \(exerciseType.unitName)")
            DataPill(title: "消耗", value: "\(Int(summary.calories.rounded())) kcal")
        }
    }

    private var emptySection: some View {
        EmptyStateView(
            systemImage: exerciseType.systemImage,
            title: "今天还没有记录",
            subtitle: "动起来就是胜利，点下面的按钮开始吧"
        )
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                showTimer = true
            } label: {
                Label("开始运动", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(exerciseType.accentColor)

            Button {
                editMode = .manual(exerciseType: exerciseType)
            } label: {
                Label("手动补录", systemImage: "square.and.pencil")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(.bordered)
            .tint(exerciseType.accentColor)
        }
    }

    // MARK: 跳转

    /// 直接切换到底部「设置」标签页
    private func openSettings() {
        selectedTab = .settings
    }
}

#Preview {
    ScrollView {
        SelfCardView(selectedTab: .constant(.home))
            .padding()
    }
    .background(Color(.systemGroupedBackground))
    .environment(AppState())
}
