import Foundation
import Observation

// MARK: - 全局应用状态

/// 持有当前用户、情侣、今日记录、目标与点赞数据。
///
/// 数据同步策略：登录后启动一个后台轮询任务（每 12 秒一次 `refreshAll`），
/// 拉取自己与对方的最新数据。相比 Firebase 的快照监听，轮询实现简单、不依赖第三方 SDK，
/// 两人数据量极小，12 秒延迟在运动打卡场景完全可接受。
///
/// 生命周期：
/// - 登录状态变化 → `bindSession()`（创建/读取 UserProfile 并启动轮询）
/// - 跨天 → `refreshDayBoundaryIfNeeded()`，由 MainTabView 进入前台时调用
@MainActor
@Observable
final class AppState {

    // MARK: 会话

    private(set) var uid: String?
    var isSessionReady = false      // 用户资料已加载完成
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

    // MARK: 轮询

    private var pollTask: Task<Void, Never>?

    private var firestore: FirestoreService { FirestoreService.shared }

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

    /// 登录成功后调用：创建/读取 UserProfile 并启动轮询
    func bindSession(uid: String, fallbackEmail: String?, fallbackName: String?) async {
        self.uid = uid
        isLoading = true
        defer { isLoading = false }

        do {
            if let existing = try await firestore.fetchUser(ownerId: uid) {
                myProfile = existing
            } else {
                // 首次登录：写入 UserProfile 文档，运动类型默认呼啦圈，由 ProfileSetupView 引导修改
                let profile = UserProfile(
                    ownerId: uid,
                    email: fallbackEmail ?? "",
                    displayName: fallbackName ?? "",
                    exerciseType: .hulaHoop
                )
                let oid = try await firestore.createUser(profile)
                var p = profile
                p.id = oid
                myProfile = p
            }

            startPolling()
            isSessionReady = true
        } catch {
            errorMessage = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 退出登录 / 解绑后重置
    func reset() {
        stopPolling()
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
        dayBoundaryString = DateHelper.todayString
    }

    // MARK: - 轮询

    func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                try? await Task.sleep(nanoseconds: 12_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// 一次性拉取自己与对方的全部数据
    func refreshAll() async {
        guard let uid else { return }
        let today = dayBoundaryString
        let since = DateHelper.dateString(from: Calendar.current.date(byAdding: .day, value: -89, to: Date()) ?? Date())

        do {
            async let me = firestore.fetchUser(ownerId: uid)
            async let myToday = firestore.fetchRecords(userId: uid, dateString: today)
            async let myRecent = firestore.fetchRecentRecords(userId: uid, sinceDateString: since)
            async let myGoal = firestore.fetchGoal(userId: uid)

            let (fetchedMe, mt, mr, mg) = await (try me, try myToday, try myRecent, try myGoal)
            self.myProfile = fetchedMe
            self.myTodayRecords = mt
            self.myRecentRecords = mr
            self.myGoal = mg

            guard let partnerId = fetchedMe?.partnerId, !partnerId.isEmpty else {
                self.partnerProfile = nil
                self.partnerTodayRecords = []
                self.partnerRecentRecords = []
                self.partnerGoal = nil
                self.likesReceivedToday = []
                self.myLikeToPartnerToday = nil
                return
            }

            async let pProf = firestore.fetchUser(ownerId: partnerId)
            async let pToday = firestore.fetchRecords(userId: partnerId, dateString: today)
            async let pRecent = firestore.fetchRecentRecords(userId: partnerId, sinceDateString: since)
            async let pGoal = firestore.fetchGoal(userId: partnerId)
            async let likesR = firestore.fetchLikes(toUserId: uid, dateString: today)
            async let likeS = firestore.fetchMyLike(fromUserId: uid, toUserId: partnerId, dateString: today)

            let (pp, pt, pr, pg, lr, ls) = await (try pProf, try pToday, try pRecent, try pGoal, try likesR, try likeS)
            self.partnerProfile = pp
            self.partnerTodayRecords = pt
            self.partnerRecentRecords = pr
            self.partnerGoal = pg
            self.likesReceivedToday = lr
            self.myLikeToPartnerToday = ls
        } catch {
            self.errorMessage = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - 跨天处理

    /// App 回到前台或首页出现时调用；若已跨天，重置"今日"缓存并立即刷新
    func refreshDayBoundaryIfNeeded() {
        let today = DateHelper.todayString
        guard today != dayBoundaryString else { return }
        dayBoundaryString = today
        Task { await refreshAll() }
    }

    // MARK: - 操作

    func saveProfile(displayName: String, exerciseType: ExerciseType) async throws {
        guard let profileId = myProfile?.id else { throw AppError.notSignedIn }
        try await firestore.updateUserFields(objectId: profileId, fields: [
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
            errorMessage = (error as? AppError)?.errorDescription ?? error.localizedDescription
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
            .map { (dateString: $0.key, records: $0.value.sorted { $0.startTime > $1.startTime }) }
            .sorted { $0.dateString > $1.dateString }
    }
}
