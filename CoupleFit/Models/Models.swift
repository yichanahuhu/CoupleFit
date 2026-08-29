import FirebaseFirestore
import FirebaseFirestoreSwift

// MARK: - users 集合

/// users/{userId}
struct UserProfile: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var email: String
    var displayName: String
    /// 对方的 userId；nil 表示尚未绑定
    var partnerId: String?
    var exerciseType: ExerciseType
    /// 用于「提醒对方」的 FCM 推送，每次 App 启动刷新。
    /// 之所以是数组：一个账号可能同时登录多台设备（iPhone + iPad），
    /// 单值字段会导致后登录的设备顶掉先登录的，只剩一台能收到推送。
    /// 声明为 Optional 是为了兼容早期不含该字段的文档，读取时一律用 `?? []`。
    var fcmTokens: [String]?
    var createdAt: Timestamp

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName
        case partnerId
        case exerciseType
        case fcmTokens
        case createdAt
    }

    init(id: String? = nil,
         email: String,
         displayName: String,
         partnerId: String? = nil,
         exerciseType: ExerciseType,
         fcmTokens: [String]? = [],
         createdAt: Timestamp = Timestamp()) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.partnerId = partnerId
        self.exerciseType = exerciseType
        self.fcmTokens = fcmTokens
        self.createdAt = createdAt
    }

    var isPaired: Bool {
        guard let partnerId, !partnerId.isEmpty else { return false }
        return true
    }
}

// MARK: - pairCodes 集合

/// pairCodes/{code}，有效期 10 分钟，绑定成功后删除
struct PairCode: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var code: String
    var creatorUserId: String
    var expiresAt: Timestamp

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case creatorUserId
        case expiresAt
    }

    init(code: String, creatorUserId: String, expiresAt: Timestamp) {
        self.id = code
        self.code = code
        self.creatorUserId = creatorUserId
        self.expiresAt = expiresAt
    }

    var isExpired: Bool { expiresAt.dateValue() < Date() }
}

// MARK: - exerciseRecords 集合

/// exerciseRecords/{autoId}
/// dateString 使用用户本地时区的 "yyyy-MM-dd"，便于按天查询与分组
struct ExerciseRecord: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var userId: String
    var exerciseType: ExerciseType
    var dateString: String
    var startTime: Timestamp
    var endTime: Timestamp
    var durationSeconds: Int
    var count: Int
    var calories: Double?
    var note: String?
    var createdAt: Timestamp

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case exerciseType
        case dateString
        case startTime
        case endTime
        case durationSeconds
        case count
        case calories
        case note
        case createdAt
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
         createdAt: Date = Date()) {
        self.id = id
        self.userId = userId
        self.exerciseType = exerciseType
        self.dateString = dateString
        self.startTime = Timestamp(date: startTime)
        self.endTime = Timestamp(date: endTime)
        self.durationSeconds = durationSeconds
        self.count = count
        self.calories = calories
        self.note = note
        self.createdAt = Timestamp(date: createdAt)
    }

    /// 展示用时长，如 "12:34" 或 "1:02:03"
    var durationText: String {
        durationSeconds.formattedDuration
    }
}

// MARK: - goals 集合

/// goals/{userId}，每人一份
struct Goal: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
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
        case id
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

// MARK: - likes 集合

/// likes/{autoId}
struct Like: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var fromUserId: String
    var toUserId: String
    var dateString: String
    var createdAt: Timestamp

    enum CodingKeys: String, CodingKey {
        case id
        case fromUserId
        case toUserId
        case dateString
        case createdAt
    }

    init(fromUserId: String, toUserId: String, dateString: String, createdAt: Date = Date()) {
        self.fromUserId = fromUserId
        self.toUserId = toUserId
        self.dateString = dateString
        self.createdAt = Timestamp(date: createdAt)
    }
}
