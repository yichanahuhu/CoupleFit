import Foundation
import UIKit
import UserNotifications

// MARK: - 本地通知服务

/// 每日运动提醒（本地触发，不依赖网络）。
final class NotificationService: @unchecked Sendable {

    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: 授权

    func requestAuthorization() async throws -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        case .denied:
            throw AppError.notificationDenied
        @unknown default:
            return false
        }
    }

    func currentSettings() async -> UNNotificationSettings {
        await center.notificationSettings()
    }

    /// 打开系统设置页
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        Task { @MainActor in
            await UIApplication.shared.open(url)
        }
    }

    // MARK: 每日提醒

    /// 按 goal 重新排程每日提醒；关闭提醒时清除已有排程。
    /// - Parameters:
    ///   - goal: 目标配置；nil 表示清除
    ///   - displayName: 提醒文案中使用的昵称
    func scheduleDailyReminder(goal: Goal?, exerciseType: ExerciseType, displayName: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [Constants.dailyReminderIdentifier])

        guard let goal, goal.reminderEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "该运动啦 💪"
        content.body = "\(displayName)，今天的\(exerciseType.displayName)还没打卡哦"
        content.sound = .default
        content.badge = 1

        var dateComponents = DateComponents()
        dateComponents.hour = goal.reminderHour
        dateComponents.minute = goal.reminderMinute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: Constants.dailyReminderIdentifier,
                                            content: content,
                                            trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            // 排程失败不阻塞主流程，交由上层记录日志
            print("[CoupleFit] 排程每日提醒失败: \(error.localizedDescription)")
        }
    }

    func cancelDailyReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [Constants.dailyReminderIdentifier])
    }

    // MARK: 即时反馈（本地模拟"对方已收到提醒"）

    /// 用于在 Cloud Function 未部署时，本地给出一次反馈通知。
    func scheduleLocalEcho(title: String, body: String, delay: TimeInterval = 2) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        try? await center.add(request)
    }
}
