import Foundation

// MARK: - 集合名与默认值

enum Constants {
    // Firestore 集合
    static let colUsers = "users"
    static let colPairCodes = "pairCodes"
    static let colExerciseRecords = "exerciseRecords"
    static let colGoals = "goals"
    static let colLikes = "likes"

    // 默认值
    static let defaultDailyDurationSeconds = 20 * 60   // 20 分钟
    static let defaultDailyCount = 300                 // 300 圈 / 次

    // 配对码
    static let pairCodeLength = 6
    static let pairCodeTTL: TimeInterval = 10 * 60     // 10 分钟

    // 通知
    static let dailyReminderIdentifier = "couplefit.dailyReminder"

    // 目标上下限（SettingsView 步进器用）
    static let durationRange = 5...180                 // 分钟
    static let durationStep = 5
    static let countRange = 50...5000
    static let countStep = 50
}

// MARK: - 错误信息

enum AppError: LocalizedError {
    case notSignedIn
    case userDocumentMissing
    case noPartner
    case pairCodeExpired
    case pairCodeNotFound
    case pairCodeSelfUse
    case alreadyPaired
    case alreadyPairedWithOther
    case networkUnavailable
    case notificationDenied
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "尚未登录，请重新登录后再试"
        case .userDocumentMissing:
            return "用户资料不存在，请重新登录"
        case .noPartner:
            return "还没有绑定情侣，先去完成配对吧"
        case .pairCodeExpired:
            return "配对码已过期，请重新生成"
        case .pairCodeNotFound:
            return "配对码不存在，请检查后重试"
        case .pairCodeSelfUse:
            return "不能使用自己生成的配对码"
        case .alreadyPaired:
            return "你们已经是绑定的情侣了"
        case .alreadyPairedWithOther:
            return "该用户已与其他人绑定"
        case .networkUnavailable:
            return "当前网络不可用，请检查网络连接后重试"
        case .notificationDenied:
            return "通知权限未开启，可在系统设置中打开"
        case .unknown(let message):
            return message
        }
    }
}
