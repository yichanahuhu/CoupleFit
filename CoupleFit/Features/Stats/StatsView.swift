import Charts
import SwiftUI

// MARK: - 统计

struct StatsView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var selection: PersonTab = .me
    @State private var metric: Metric = .duration

    /// iPad 上给图表更多垂直空间；iPhone 保持紧凑
    private var chartHeight: CGFloat { sizeClass == .regular ? 300 : 220 }
    private var compareChartHeight: CGFloat { sizeClass == .regular ? 200 : 140 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PersonSegmentedPicker(selection: $selection,
                                          partnerName: appState.partnerProfile?.displayName ?? "对方")
                    metricCards
                    weeklyChartCard
                    if appState.hasPartner {
                        compareCard
                    }
                }
                // 先限宽再撑满：iPad 横屏下内容居中，不被拉成横幅
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await appState.startListening()
            }
        }
    }

    // MARK: - 关键指标卡片

    private var metricCards: some View {
        HStack(alignment: .top, spacing: 12) {
            CardContainer {
                DataPill(title: "本周时长",
                         value: weekDurationSeconds.minutesText,
                         tint: currentExerciseType.accentColor)
            }
            CardContainer {
                DataPill(title: "本周\(currentExerciseType.unitName)数",
                         value: "\(weekCount) \(currentExerciseType.unitName)")
            }
            CardContainer {
                VStack(alignment: .leading, spacing: 4) {
                    Label("连续打卡", systemImage: "flame.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(streak.days)")
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                        Text("天")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !streak.includesToday {
                        Text("今天还没打卡")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 本周柱状图

    private var weeklyChartCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("本周趋势")
                        .font(.headline)
                    Spacer()
                    Text("周一 → 周日")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Picker("统计指标", selection: $metric) {
                    ForEach(Metric.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                if weekTotal(of: metric) > 0 {
                    weeklyChart
                        .frame(height: chartHeight)
                        .animation(.easeInOut(duration: 0.3), value: metric)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("本周还没有数据")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("哪怕 5 分钟也是好的开始，现在就去动一动吧 💪")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(height: chartHeight)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var weeklyChart: some View {
        Chart {
            ForEach(bars) { bar in
                let value = metric.value(of: bar.summary)
                BarMark(
                    x: .value("星期", bar.weekday),
                    y: .value(metric.title, value)
                )
                .foregroundStyle(bar.index == todayIndex ? highlightColor : barColor)
                .cornerRadius(6)
                .annotation(position: .top) {
                    if value > 0 {
                        Text(metric.text(for: bar.summary))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 7)) { value in
                if let label = value.as(String.self) {
                    AxisValueLabel {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(label == todayWeekday ? highlightColor : .secondary)
                    }
                }
            }
        }
    }

    // MARK: - 双方对比

    private var compareCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("本周时长对比")
                    .font(.headline)

                if compareItems.allSatisfy({ $0.minutes <= 0 }) {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2")
                            .font(.system(size: 30))
                            .foregroundStyle(.tertiary)
                        Text("本周双方都还没有记录")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("约 TA 一起打卡，看看谁先完成目标")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(height: compareChartHeight)
                    .frame(maxWidth: .infinity)
                } else {
                    Chart {
                        ForEach(compareItems) { item in
                            BarMark(
                                x: .value("成员", item.name),
                                y: .value("时长（分钟）", item.minutes)
                            )
                            .foregroundStyle(item.color)
                            .cornerRadius(8)
                            .annotation(position: .top) {
                                Text(String(format: "%.0f 分钟", item.minutes))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(height: compareChartHeight)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 2)) { value in
                            if let label = value.as(String.self) {
                                AxisValueLabel {
                                    Text(label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 16) {
                    ForEach(compareItems) { item in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 8, height: 8)
                            Text(item.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - 数据派生

    /// 7 天柱子：weekdaySymbols() 与 weekSummaries 都是周一 → 周日，索引一一对应
    private var bars: [WeekBar] {
        let weekdays = DateHelper.weekdaySymbols()
        let summaries = weekSummaries
        guard weekdays.count == summaries.count else { return [] }
        return Array(zip(weekdays, summaries).enumerated()).map { item in
            WeekBar(index: item.offset, weekday: item.element.0, summary: item.element.1)
        }
    }

    private var weekdays: [String] {
        DateHelper.weekdaySymbols()
    }

    /// 今天在本周中的索引（0 = 周一）
    private var todayIndex: Int {
        DateHelper.currentWeekDateStrings().firstIndex(of: DateHelper.todayString) ?? -1
    }

    private var todayWeekday: String {
        guard todayIndex >= 0, todayIndex < weekdays.count else { return "" }
        return weekdays[todayIndex]
    }

    private var weekSummaries: [DailySummary] {
        selection == .me ? appState.myWeekSummaries : appState.partnerWeekSummaries
    }

    private var weekDurationSeconds: Int {
        weekSummaries.reduce(0) { $0 + $1.durationSeconds }
    }

    private var weekCount: Int {
        weekSummaries.reduce(0) { $0 + $1.count }
    }

    private func weekTotal(of metric: Metric) -> Double {
        weekSummaries.reduce(0) { $0 + metric.value(of: $1) }
    }

    private var streak: StreakResult {
        selection == .me ? appState.myStreak : appState.partnerStreak
    }

    private var currentExerciseType: ExerciseType {
        (selection == .me ? appState.myProfile : appState.partnerProfile)?.exerciseType ?? .hulaHoop
    }

    /// 今日柱子的高亮色
    private var highlightColor: Color { currentExerciseType.accentColor }

    /// 其余柱子的次要色
    private var barColor: Color { currentExerciseType.accentColor.opacity(0.35) }

    private var compareItems: [CompareBar] {
        let myMinutes = Double(appState.myWeekSummaries.reduce(0) { $0 + $1.durationSeconds }) / 60
        let partnerMinutes = Double(appState.partnerWeekSummaries.reduce(0) { $0 + $1.durationSeconds }) / 60
        let myName = appState.myProfile?.displayName.isEmpty == true ? "我" : (appState.myProfile?.displayName ?? "我")
        let partnerName = appState.partnerProfile?.displayName.isEmpty == true ? "对方" : (appState.partnerProfile?.displayName ?? "对方")
        return [
            CompareBar(id: 0,
                       name: myName,
                       minutes: myMinutes,
                       color: (appState.myProfile?.exerciseType ?? .hulaHoop).accentColor),
            CompareBar(id: 1,
                       name: partnerName,
                       minutes: partnerMinutes,
                       color: (appState.partnerProfile?.exerciseType ?? .jump).accentColor)
        ]
    }

    // MARK: - 子类型

    /// 图表用的一根柱子
    private struct WeekBar: Identifiable {
        let index: Int
        let weekday: String
        let summary: DailySummary
        var id: Int { index }
    }

    /// 双方对比的一根柱子
    private struct CompareBar: Identifiable {
        let id: Int
        let name: String
        let minutes: Double
        let color: Color
    }

    /// Y 轴可切换的指标
    private enum Metric: String, CaseIterable, Identifiable, Hashable {
        case duration
        case count
        case calories

        var id: String { rawValue }

        var title: String {
            switch self {
            case .duration: return "时长（分钟）"
            case .count: return "次数"
            case .calories: return "卡路里"
            }
        }

        func value(of summary: DailySummary) -> Double {
            switch self {
            case .duration: return Double(summary.durationSeconds) / 60
            case .count: return Double(summary.count)
            case .calories: return summary.calories
            }
        }

        func text(for summary: DailySummary) -> String {
            switch self {
            case .duration: return String(format: "%.0f", value(of: summary))
            case .count: return "\(summary.count)"
            case .calories: return String(format: "%.0f", summary.calories)
            }
        }
    }
}

#Preview {
    StatsView()
        .environment(AppState())
}
