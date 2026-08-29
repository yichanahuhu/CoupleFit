import Foundation

// MARK: - 每日汇总

/// 某人在某一天的运动汇总，由记录列表聚合而来。
struct DailySummary {
    var durationSeconds: Int = 0
    var count: Int = 0
    var calories: Double = 0
    var recordCount: Int = 0

    init() {}

    init(records: [ExerciseRecord]) {
        durationSeconds = records.reduce(0) { $0 + $1.durationSeconds }
        count = records.reduce(0) { $0 + $1.count }
        calories = records.reduce(0) { $0 + ($1.calories ?? 0) }
        recordCount = records.count
    }

    /// 相对目标的时长完成度（0...1，可超过 1）
    func durationProgress(goal: Goal?) -> Double {
        guard let goal, goal.dailyDurationSeconds > 0 else { return 0 }
        return min(1, Double(durationSeconds) / Double(goal.dailyDurationSeconds))
    }

    /// 相对目标的次数完成度
    func countProgress(goal: Goal?) -> Double {
        guard let goal, goal.dailyCount > 0 else { return 0 }
        return min(1, Double(count) / Double(goal.dailyCount))
    }

    /// 综合完成度：时长与次数各占一半，用于进度环
    func overallProgress(goal: Goal?) -> Double {
        guard goal != nil else { return 0 }
        return (durationProgress(goal: goal) + countProgress(goal: goal)) / 2
    }

    /// 是否已达成目标（时长和次数都达标）
    func isGoalReached(goal: Goal?) -> Bool {
        guard let goal else { return false }
        return durationSeconds >= goal.dailyDurationSeconds && count >= goal.dailyCount
    }

    var durationText: String { durationSeconds.formattedDuration }
}

// MARK: - 连续打卡

/// 连续打卡天数计算结果
struct StreakResult {
    /// 连续天数（含今天则含今天）
    let days: Int
    /// 今天是否已打卡
    let includesToday: Bool
}
