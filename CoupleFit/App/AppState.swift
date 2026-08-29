import FirebaseAuth
import FirebaseFirestore
import Foundation
import Observation

// MARK: - 全局应用状态

/// 持有当前用户、情侣、今日记录、目标与点赞数据，
/// 并统一管理所有 Firestore 快照监听器。
///
/// 生命周期：
/// - 登录状态变化 → `bindSession()`
/// - 自己的 users 文档变化（含 partnerId）→ 重建对方相关监听器
/// - 跨天 → `refreshDayBoundaryIfNeeded()`，由 HomeView 进入前台时调用
@MainActor
@Observable
final class AppState {

    // MARK: 会话

    private(set) var uid: String?
    var isSessionReady = false      // 用户文档已加载完成
    var isLoading = false

    // MARK: 资料

    var myProfile: UserProfile?
    var partnerProfile: UserProfile?

    // MARK: 记录

    var myTodayRecords: [ExerciseRecord] = []
    var partnerTodayRecords: [ExerciseRecord] = []
    /// 最近 90 天记录，用于历史与统计
    var myRecentRecords: [ExerciseRecord] = []
    var partnerRecentRecords: [ExerciseRecord] = []

    // MARK: 目标

    var myGoal: Goal?
    var partnerGoal: Goal?

    // MARK: 点赞

    /// 我今天收到的赞（对方给我点的）
    var likesReceivedToday: [Like] = []
    /// 我今天给对方点的赞（用于按钮点亮态）
    var myLikeToPartnerToday: Like?

    // MARK: 提示

    var errorMessage: String?
    var toastMessage: String?
    var dayBoundaryString: String = DateHelper.todayString

    // MARK: 监听器

    private var myUserListener: ListenerRegistration?
    private var partnerUserListener: ListenerRegistration?
    private var myTodayListener: ListenerRegistration?
    private var partnerTodayListener: ListenerRegistration?
    private var myRecentListener: ListenerRegistration?
    private var partnerRecentListener: ListenerRegistration?
    private var myGoalListener: ListenerRegistration?
    private var partnerGoalListener: ListenerRegistration?
    private var likesReceivedListener: ListenerRegistration?
    private var likeSentListener: ListenerRegistration?

    // 惰性访问：AppState 由 SwiftUI 在 App 属性初始化阶段创建，
    // 早于 AppDelegate 里的 FirebaseApp.configure()。
    // 若在此处直接持有 FirestoreService.shared，会提前触发 Firestore.firestore() 导致崩溃。
    private var firestore: FirestoreService { FirestoreService.shared }

    private var currentPartnerId: String?

    // MARK: - 派生态

    var hasPartner: Bool { partnerProfile != nil && myProfile?.isPaired == true }

    /// 是否需要先完成资料设置（昵称 + 运动类型）
    var needsProfileSetup: Bool {
        guard let profile = myProfile else { return false }
        return profile.displayName.isEmpty
    }

    var mySummary: DailySummary { DailySummary(records: myTodayRecords) }
    var partnerSummary: DailySummary { DailySummary(records: partnerTodayRecords) }

    var myStreak: StreakResult { Self.calculateStreak(records: myRecentRecords, reference: Date()) }
    var partnerStreak: StreakResult { Self.calculateStreak(records: partnerRecentRecords, reference: Date()) }

    /// 本周每日汇总（周一 → 周日），用于统计页柱状图
    var myWeekSummaries: [DailySummary] { Self.weekSummaries(records: myRecentRecords) }
    var partnerWeekSummaries: [DailySummary] { Self.weekSummaries(records: partnerRecentRecords) }

    /// 按日期分组的历史记录（倒序：最近的日期在前）
    var myGroupedHistory: [(dateString: String, records: [ExerciseRecord])] {
        Self.groupByDate(records: myRecentRecords)
    }

    var partnerGroupedHistory: [(dateString: String, records: [ExerciseRecord])] {
        Self.groupByDate(records: partnerRecentRecords)
    }

    // MARK: - 会话绑定

    /// 登录成功后调用：创建/读取 users 文档并启动监听
    func bindSession(uid: String, fallbackEmail: String?, fallbackName: String?) async {
        self.uid = uid
        isLoading = true
        defer { isLoading = false }

        do {
            if let existing = try await firestore.fetchUser(uid) {
                myProfile = existing
            } else {
                // 首次登录：写入 users 文档，运动类型默认呼啦圈，由 ProfileSetupView 引导修改
                let profile = UserProfile(
                    id: uid,
                    email: fallbackEmail ?? "",
                    displayName: fallbackName ?? "",
                    exerciseType: .hulaHoop,
                    createdAt: Timestamp()
                )
                try await firestore.createUser(profile)
                myProfile = profile
            }

            await MessagingService.shared.uploadTokenIfNeeded(uid: uid)
            startListening()
            isSessionReady = true
        } catch {
            errorMessage = (error as NSError).friendlyAuthMessage
        }
    }

    /// 退出登录 / 解绑后重置
    func reset() {
        teardownListeners()
        uid = nil
        isSessionReady = false
        myProfile = nil
        partnerProfile = nil
        myTodayRecords = []
        partnerTodayRecords = []
        myRecentRecords = []
        partnerRecentRecords = []
        myGoal = nil
        partnerGoal = nil
        likesReceivedToday = []
        myLikeToPartnerToday = nil
        currentPartnerId = nil
        dayBoundaryString = DateHelper.todayString
    }

    // MARK: - 监听器管理

    func startListening() {
        guard let uid else { return }
        teardownListeners()

        // 自己的资料（partnerId 变化会触发后续监听重建）
        myUserListener = firestore.listenUser(uid) { [weak self] profile in
            Task { @MainActor in
                guard let self else { return }
                self.myProfile = profile
                self.refreshPartnerListenersIfNeeded()
            }
        }

        let today = dayBoundaryString
        let since = DateHelper.dateString(from: Calendar.current.date(byAdding: .day, value: -89, to: Date()) ?? Date())

        myTodayListener = firestore.listenRecords(userId: uid, dateString: today) { [weak self] records in
            Task { @MainActor in self?.myTodayRecords = records }
        }

        myRecentListener = firestore.listenRecentRecords(userId: uid, sinceDateString: since) { [weak self] records in
            Task { @MainActor in self?.myRecentRecords = records }
        }

        myGoalListener = firestore.listenGoal(userId: uid) { [weak self] goal in
            Task { @MainActor in self?.myGoal = goal }
        }

        refreshPartnerListenersIfNeeded()
    }

    private func refreshPartnerListenersIfNeeded() {
        guard let uid else { return }
        let partnerId = myProfile?.partnerId

        // partnerId 未变化则无需重建
        guard partnerId != currentPartnerId else { return }
        currentPartnerId = partnerId

        partnerUserListener?.remove(); partnerUserListener = nil
        partnerTodayListener?.remove(); partnerTodayListener = nil
        partnerRecentListener?.remove(); partnerRecentListener = nil
        partnerGoalListener?.remove(); partnerGoalListener = nil
        likesReceivedListener?.remove(); likesReceivedListener = nil
        likeSentListener?.remove(); likeSentListener = nil

        partnerProfile = nil
        partnerTodayRecords = []
        partnerRecentRecords = []
        partnerGoal = nil
        likesReceivedToday = []
        myLikeToPartnerToday = nil

        guard let partnerId, !partnerId.isEmpty else { return }

        let today = dayBoundaryString
        let since = DateHelper.dateString(from: Calendar.current.date(byAdding: .day, value: -89, to: Date()) ?? Date())

        partnerUserListener = firestore.listenUser(partnerId) { [weak self] profile in
            Task { @MainActor in self?.partnerProfile = profile }
        }
        partnerTodayListener = firestore.listenRecords(userId: partnerId, dateString: today) { [weak self] records in
            Task { @MainActor in self?.partnerTodayRecords = records }
        }
        partnerRecentListener = firestore.listenRecentRecords(userId: partnerId, sinceDateString: since) { [weak self] records in
            Task { @MainActor in self?.partnerRecentRecords = records }
        }
        partnerGoalListener = firestore.listenGoal(userId: partnerId) { [weak self] goal in
            Task { @MainActor in self?.partnerGoal = goal }
        }
        startLikeListeners(uid: uid, partnerId: partnerId)
    }

    private func startLikeListeners(uid: String, partnerId: String) {
        let today = dayBoundaryString

        // 我收到的赞
        likesReceivedListener = firestore.listenLikes(toUserId: uid, dateString: today) { [weak self] likes in
            Task { @MainActor in self?.likesReceivedToday = likes }
        }

        // 我给对方点的赞：用查询 myself → partner 的监听器模拟"我的点赞状态"
        likeSentListener = firestore.listenLikes(toUserId: partnerId, dateString: today) { [weak self] likes in
            guard let self else { return }
            Task { @MainActor in
                self.myLikeToPartnerToday = likes.first { $0.fromUserId == uid }
            }
        }
    }

    private func teardownListeners() {
        myUserListener?.remove()
        partnerUserListener?.remove()
        myTodayListener?.remove()
        partnerTodayListener?.remove()
        myRecentListener?.remove()
        partnerRecentListener?.remove()
        myGoalListener?.remove()
        partnerGoalListener?.remove()
        likesReceivedListener?.remove()
        likeSentListener?.remove()

        myUserListener = nil
        partnerUserListener = nil
        myTodayListener = nil
        partnerTodayListener = nil
        myRecentListener = nil
        partnerRecentListener = nil
        myGoalListener = nil
        partnerGoalListener = nil
        likesReceivedListener = nil
        likeSentListener = nil
        currentPartnerId = nil
    }

    // MARK: - 跨天处理

    /// App 回到前台或首页出现时调用；若已跨天，重建"今日"监听器
    func refreshDayBoundaryIfNeeded() {
        let today = DateHelper.todayString
        guard today != dayBoundaryString else { return }
        dayBoundaryString = today
        guard let uid else { return }

        myTodayListener?.remove()
        partnerTodayListener?.remove()
        likesReceivedListener?.remove()
        likeSentListener?.remove()

        myTodayListener = firestore.listenRecords(userId: uid, dateString: today) { [weak self] records in
            Task { @MainActor in self?.myTodayRecords = records }
        }
        if let partnerId = myProfile?.partnerId, !partnerId.isEmpty {
            partnerTodayListener = firestore.listenRecords(userId: partnerId, dateString: today) { [weak self] records in
                Task { @MainActor in self?.partnerTodayRecords = records }
            }
            startLikeListeners(uid: uid, partnerId: partnerId)
        }
    }

    // MARK: - 操作

    func saveProfile(displayName: String, exerciseType: ExerciseType) async throws {
        guard let uid else { throw AppError.notSignedIn }
        try await firestore.updateUserFields(uid: uid, fields: [
            "displayName": displayName,
            "exerciseType": exerciseType.rawValue
        ])
        myProfile?.displayName = displayName
        myProfile?.exerciseType = exerciseType
    }

    func saveGoal(_ goal: Goal) async throws {
        try await firestore.saveGoal(goal)
        myGoal = goal
        await NotificationService.shared.scheduleDailyReminder(
            goal: goal,
            exerciseType: myProfile?.exerciseType ?? .hulaHoop,
            displayName: myProfile?.displayName ?? "你"
        )
    }

    func toggleLikeToPartner() async {
        guard let uid, let partnerId = myProfile?.partnerId, !partnerId.isEmpty else {
            errorMessage = AppError.noPartner.errorDescription
            return
        }
        do {
            if let existing = myLikeToPartnerToday {
                try await firestore.removeLike(existing)
                myLikeToPartnerToday = nil
            } else {
                let like = Like(fromUserId: uid, toUserId: partnerId, dateString: dayBoundaryString)
                try await firestore.addLike(like)
                toastMessage = "已给对方点赞 💗"
            }
        } catch {
            errorMessage = (error as NSError).friendlyAuthMessage
        }
    }

    func unbind() async throws {
        guard let uid, let partnerId = myProfile?.partnerId else { return }
        try await PairingService().unbind(myUID: uid, partnerUID: partnerId)
        myProfile?.partnerId = nil
    }

    // MARK: - 纯计算

    /// 连续打卡天数：从今天（或昨天）往回数，只要当天有记录就累加
    static func calculateStreak(records: [ExerciseRecord], reference: Date = Date()) -> StreakResult {
        let daysWithRecords = Set(records.filter { $0.durationSeconds > 0 }.map(\.dateString))
        if daysWithRecords.isEmpty { return StreakResult(days: 0, includesToday: false) }

        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: reference)
        var streak = 0
        var includesToday = false

        // 若今天还没打卡，从昨天开始算，避免"断签"误判
        if !daysWithRecords.contains(DateHelper.dateString(from: cursor)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                return StreakResult(days: 0, includesToday: false)
            }
            guard daysWithRecords.contains(DateHelper.dateString(from: yesterday)) else {
                return StreakResult(days: 0, includesToday: false)
            }
            cursor = yesterday
        } else {
            includesToday = true
        }

        while daysWithRecords.contains(DateHelper.dateString(from: cursor)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return StreakResult(days: streak, includesToday: includesToday)
    }

    /// 本周（周一 → 周日）每天的汇总
    static func weekSummaries(records: [ExerciseRecord], reference: Date = Date()) -> [DailySummary] {
        let weekDays = DateHelper.currentWeekDateStrings(reference: reference)
        let grouped = Dictionary(grouping: records, by: \.dateString)
        return weekDays.map { DailySummary(records: grouped[$0] ?? []) }
    }

    /// 按日期字符串倒序分组
    static func groupByDate(records: [ExerciseRecord]) -> [(dateString: String, records: [ExerciseRecord])] {
        let grouped = Dictionary(grouping: records, by: \.dateString)
        return grouped
            .map { (dateString: $0.key, records: $0.value.sorted { $0.startTime.dateValue() > $1.startTime.dateValue() }) }
            .sorted { $0.dateString > $1.dateString }
    }
}
