import FirebaseCore
import FirebaseMessaging
import UIKit
import UserNotifications

// MARK: - AppDelegate

/// 负责 Firebase 初始化、推送注册与通知回调。
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()

        // 必须在 configure 之后才能触碰 Auth.auth()
        Task { @MainActor in
            AuthService.shared.start()
        }

        // 远程推送：FCM
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()

        return true
    }

    // MARK: APNs token → FCM

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // 模拟器或未配置推送证书时会走到这里，不影响主流程
        print("[CoupleFit] 注册远程通知失败（模拟器属正常现象）: \(error.localizedDescription)")
    }
}

// MARK: - MessagingDelegate

extension AppDelegate: MessagingDelegate {
    /// FCM token 刷新：写回当前用户的 users 文档
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in
            await MessagingService.shared.uploadTokenIfNeeded(uid: AuthService.shared.currentUID)
        }
        _ = fcmToken
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    /// 前台也展示通知横幅
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// 点击通知：若携带 dateString 可跳转到当天历史，预留扩展点
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
