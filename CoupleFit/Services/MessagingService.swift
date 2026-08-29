import FirebaseAuth
import FirebaseMessaging
import Foundation
import UIKit

// MARK: - 远程推送服务（提醒对方）

/// "提醒对方"通过 Firebase Cloud Messaging 下发。
/// 客户端不持有 Server Key，统一由 Cloud Function 代为发送，
/// 因此这里只需要把请求 POST 到 `remindEndpoint`。
///
/// 未部署 Cloud Function 时，MessagingService 自动降级为本地模拟通知（见 fallback 分支），
/// 保证功能在第 4 周不依赖后端即可验证。
final class MessagingService: @unchecked Sendable {

    static let shared = MessagingService()

    /// 在 Firebase 控制台 / Cloud Functions 部署后，把这里换成你的 HTTPS 端点。
    /// 形如：https://<region>-<project-id>.cloudfunctions.net/remindPartner
    var remindEndpoint: String? {
        // 也可以在 Info.plist 中配置 RemindEndpoint，避免改动代码
        if let configured = Bundle.main.object(forInfoDictionaryKey: "RemindEndpoint") as? String,
           !configured.isEmpty, !configured.hasPrefix("__") {
            return configured
        }
        return nil
    }

    private init() {}

    // MARK: 注册远程通知

    func registerForRemoteNotifications() {
        Task { @MainActor in
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// FCM token 刷新后写回 users 文档（多设备累加）
    func uploadTokenIfNeeded(uid: String?) async {
        guard let uid else { return }
        do {
            let token = try await Messaging.messaging().token()
            try await FirestoreService.shared.addFCMToken(uid: uid, token: token)
        } catch {
            print("[CoupleFit] 上传 FCM token 失败: \(error.localizedDescription)")
        }
    }

    // MARK: 提醒对方

    /// 发送提醒给对方。
    /// - Parameters:
    ///   - partnerUID: 对方的用户 ID
    ///   - senderName: 我的昵称，用于推送文案
    ///   - exerciseType: 对方的运动类型
    func remindPartner(partnerUID: String,
                       senderName: String,
                       exerciseType: ExerciseType) async throws {
        guard let endpointString = remindEndpoint, let url = URL(string: endpointString) else {
            // 降级：本地模拟一条"已提醒对方"的通知
            await NotificationService.shared.scheduleLocalEcho(
                title: "已提醒对方（本地模拟）",
                body: "部署 Cloud Function 后，对方会收到真实推送"
            )
            return
        }

        // Cloud Function 会校验调用者身份，并确认双方确实是情侣关系
        guard let user = Auth.auth().currentUser else {
            throw AppError.notSignedIn
        }
        let idToken = try await user.getIDToken()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let payload: [String: Any] = [
            "partnerUID": partnerUID,
            "title": "\(senderName) 喊你运动啦 💪",
            "body": "今天的\(exerciseType.displayName)还没打卡哦",
            "exerciseType": exerciseType.rawValue
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AppError.unknown("提醒发送失败，请稍后重试")
        }
    }
}
