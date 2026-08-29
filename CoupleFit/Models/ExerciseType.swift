import SwiftUI

// MARK: - 运动类型

/// 情侣双方各自固定的运动类型。
/// 男方：呼啦圈；女方：跳跃运动。注册后在 ProfileSetupView 中选择，并写入 users 文档。
enum ExerciseType: String, Codable, CaseIterable, Identifiable, Equatable {
    case hulaHoop = "hula_hoop"
    case jump = "jump"

    var id: String { rawValue }

    /// 展示名称
    var displayName: String {
        switch self {
        case .hulaHoop: return "呼啦圈"
        case .jump: return "跳跃运动"
        }
    }

    /// 计数单位（呼啦圈记"圈"，跳跃记"次"）
    var unitName: String {
        switch self {
        case .hulaHoop: return "圈"
        case .jump: return "次"
        }
    }

    /// 卡路里估算系数（kcal / 分钟）
    var kcalPerMinute: Double {
        switch self {
        case .hulaHoop: return 5
        case .jump: return 10
        }
    }

    var systemImage: String {
        switch self {
        case .hulaHoop: return "circle.dashed"
        case .jump: return "figure.jumprope"
        }
    }

    /// 主题色，用于卡片、进度环、图表的视觉区分
    var accentColor: Color {
        switch self {
        case .hulaHoop: return .orange
        case .jump: return .pink
        }
    }

    /// Firestore 中未识别的类型回退到呼啦圈，避免新增枚举值时旧数据解析失败
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try? container.decode(String.self)
        self = ExerciseType(rawValue: raw ?? "") ?? .hulaHoop
    }
}
