import Foundation

// MARK: - 卡路里估算

/// 简单线性估算：呼啦圈 5 kcal/分钟，跳跃运动 10 kcal/分钟。
/// 时长不足 1 分钟按实际秒数按比例折算。
enum CalorieEstimator {
    static func estimate(exerciseType: ExerciseType, durationSeconds: Int) -> Double {
        guard durationSeconds > 0 else { return 0 }
        let minutes = Double(durationSeconds) / 60.0
        let kcal = minutes * exerciseType.kcalPerMinute
        return (kcal * 10).rounded() / 10 // 保留 1 位小数
    }

    /// 展示文本，如 "≈ 75 kcal"
    static func text(exerciseType: ExerciseType, durationSeconds: Int) -> String {
        let kcal = estimate(exerciseType: exerciseType, durationSeconds: durationSeconds)
        return "≈ \(String(format: "%.0f", kcal)) kcal"
    }
}
