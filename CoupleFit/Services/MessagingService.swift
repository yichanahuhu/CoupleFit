import Foundation
import UserNotifications

// MARK: - 提醒服务（本地兜底）

/// 免费 Apple ID 没有远程推送权限，因此"提醒对方"无法走 APNs/FCM 真实下发。
/// 这里降级为：本地给当前设备一条确认通知，提示已提醒对方。
/// 对方打开 App 时，轮询会刷新数据，自然看到你的最新进度（真正的"提醒"靠 App 内可见性）。
///
/// 若日后购买开发者账号并部署云函数，可在此接入真实推送。
final class MessagingService: @unchecked Sendable {

    static let shared = MessagingService()

    private init() {}

    /// 提醒对方：当前阶段本地反馈即可
    func remindPartner(partnerUID: String,
                       senderName: String,
                       exerciseType: ExerciseType) async {
        await NotificationService.shared.scheduleLocalEcho(
            title: "已提醒对方 💪",
            body: "对方打开 App 就能看到你的进度啦"
        )
    }
}
