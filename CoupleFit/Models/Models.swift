import Foundation

// MARK: - users 业务资料（LeanCloud class: UserProfile）

/// UserProfile/{objectId}，ownerId 对应 LeanCloud _User 的 objectId
struct UserProfile: Codable, Identifiable, Equatable {
    /// LeanCloud objectId
    var id: String?
    /// 对应 _User.objectId（即本 App 的 uid）
    var ownerId: String
    var email: String
    var displayName: String
    /// 对方的 ownerId；nil 表示尚未绑定
    var partnerId: String?
    var exerciseType: ExerciseType
    /// 创建时间（秒，since1970）。映射到 LeanCloud 字段 `createdTs`，避开系统保留字 createdAt
    var createdTs: TimeInterval

    enum CodingKeys: String, CodingKey {
        case id = "objectId"
        case ownerId
        case email
        case displayName
        case partnerId
        case exerciseType
        case createdTs
    }

    init(id: String? = nil,
         ownerId: String,
         email: String,
         displayName: String,
         partnerId: String? = nil,
         exerciseType: ExerciseType,
         createdTs: TimeInterval = Date().timeIntervalSince1970) {
        self.id = id
        self.ownerId = ownerId
        self.email = email
        self.displayName = displayName
        self.partnerId = partnerId
        self.exerciseType = exerciseType
        self.createdTs = createdTs
    }

    var isPaired: Bool {
        guard let partnerId, !partnerId.isEmpty else { return false }
        return true
    }
}

// MARK: - pairCodes（LeanCloud class: PairCode）

/// PairCode/{objectId}，有效期 10 分钟，绑定成功后删除
struct PairCode: Codable, Identifiable, Equatable {
    var id: String?
    var code: String
    var creatorUserId: String
    var expiresAt: TimeInterval

    enum CodingKeys: String, CodingKey {
        case id = "objectId"
        case code
        case creatorUserId
        case expiresAt
    }

    init(id: String? = nil, code: String, creatorUserId: String, expiresAt: TimeInterval) {
        self.id = id
        self.code = code
        self.creatorUserId = creatorUserId
        self.expiresAt = expiresAt
    }

    var isExpired: Bool { Date(timeIntervalSince1970: expiresAt) < Date() }
}

// MARK: - exerciseRecords（LeanCloud class: ExerciseRecord）

/// ExerciseRecord/{objectId}
/// dateString 使用用户本地时区的 "yyyy-MM-dd"，便于按天查询与分组
struct ExerciseRecord: Codable, Identifiable, Equatable {
    var id: String?
    var userId: String
    var exerciseType: ExerciseType
    var dateString: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var durationSeconds: Int
    var count: Int
    var calories: Double?
    var note: String?
    var createdTs: TimeInterval

    enum CodingKeys: String, CodingKey {
        case id = "objectId"
        case userId
        case exerciseType
        case dateString
        case startTime
        case endTime
        case durationSeconds
        case count
        case calories
        case note
        case createdTs
    }

    init(id: String? = nil,
         userId: String,
         exerciseType: ExerciseType,
         dateString: String,
         startTime: Date,
         endTime: Date,
         durationSeconds: Int,
         count: Int,
         calories: Double? = nil,
         note: String? = nil,
         createdTs: Date = Date()) {
        self.id = id
        self.userId = userId
        self.exerciseType = exerciseType
        self.dateString = dateString
        self.startTime = startTime.timeIntervalSince1970
        self.endTime = endTime.timeIntervalSince1970
        self.durationSeconds = durationSeconds
        self.count = count
        self.calories = calories
        self.note = note
        self.createdTs = createdTs.timeIntervalSince1970
    }

    /// 展示用时间
    var startDate: Date { Date(timeIntervalSince1970: startTime) }
    var endDate: Date { Date(timeIntervalSince1970: endTime) }

    /// 展示用时长，如 "12:34" 或 "1:02:03"
    var durationText: String {
        durationSeconds.formattedDuration
    }
}

// MARK: - goals（LeanCloud class: Goal）

/// Goal/{objectId}，每人一份，objectId 即 userId 方便定位
struct Goal: Codable, Identifiable, Equatable {
    var id: String?
    var userId: String
    /// 每日时长目标（秒）
    var dailyDurationSeconds: Int
    /// 每日圈数/次数目标
    var dailyCount: Int
    var reminderEnabled: Bool
    /// 提醒时间（本地时间，24 小时制）
    var reminderHour: Int
    var reminderMinute: Int
    /// 提醒时是否同时推送给对方
    var remindPartner: Bool

    enum CodingKeys: String, CodingKey {
        case id = "objectId"
        case userId
        case dailyDurationSeconds
        case dailyCount
        case reminderEnabled
        case reminderHour
        case reminderMinute
        case remindPartner
    }

    init(id: String? = nil,
         userId: String,
         dailyDurationSeconds: Int = Constants.defaultDailyDurationSeconds,
         dailyCount: Int = Constants.defaultDailyCount,
         reminderEnabled: Bool = true,
         reminderHour: Int = 20,
         reminderMinute: Int = 0,
         remindPartner: Bool = false) {
        self.id = id
        self.userId = userId
        self.dailyDurationSeconds = dailyDurationSeconds
        self.dailyCount = dailyCount
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.remindPartner = remindPartner
    }

    /// 20:00 → "20:00"
    var reminderTimeText: String {
        String(format: "%02d:%02d", reminderHour, reminderMinute)
    }
}

// MARK: - likes（LeanCloud class: Like）

/// Like/{objectId}
struct Like: Codable, Identifiable, Equatable {
    var id: String?
    var fromUserId: String
    var toUserId: String
    var dateString: String
    var createdTs: TimeInterval

    enum CodingKeys: String, CodingKey {
        case id = "objectId"
        case fromUserId
        case toUserId
        case dateString
        case createdTs
    }

    init(id: String? = nil,
         fromUserId: String,
         toUserId: String,
         dateString: String,
         createdTs: Date = Date()) {
        self.id = id
        self.fromUserId = fromUserId
        self.toUserId = toUserId
        self.dateString = dateString
        self.createdTs = createdTs.timeIntervalSince1970
    }
}
