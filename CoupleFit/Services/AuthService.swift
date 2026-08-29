import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseMessaging
import UIKit

// MARK: - 认证服务

@MainActor
final class AuthService: ObservableObject {

    static let shared = AuthService()

    /// 当前登录用户；nil 表示未登录
    @Published private(set) var currentUser: FirebaseAuth.User?

    private var listenerHandle: AuthStateDidChangeListenerHandle?
    private var isStarted = false

    /// 注意：构造器中**不能**触碰 `Auth.auth()`。
    /// AppState / RootView 的属性初始化会早于 `FirebaseApp.configure()`，
    /// 此时调用 `Auth.auth()` 会直接崩溃，因此真正的初始化推迟到 `start()`。
    private init() {}

    /// 在 `FirebaseApp.configure()` 之后调用，幂等。
    func start() {
        guard !isStarted, FirebaseApp.app() != nil else { return }
        isStarted = true
        currentUser = Auth.auth().currentUser
        listenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
            }
        }
    }

    deinit {
        if let listenerHandle {
            Auth.auth().removeStateDidChangeListener(listenerHandle)
        }
    }

    var currentUID: String? { currentUser?.uid }

    var isSignedIn: Bool { currentUser != nil }

    // MARK: 邮箱注册

    @discardableResult
    func signUp(email: String, password: String, displayName: String) async throws -> FirebaseAuth.User {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let changeRequest = result.user.createProfileChangeRequest()
        changeRequest.displayName = displayName
        try await changeRequest.commitChanges()
        return result.user
    }

    // MARK: 邮箱登录

    @discardableResult
    func signIn(email: String, password: String) async throws -> FirebaseAuth.User {
        try await Auth.auth().signIn(withEmail: email, password: password).user
    }

    // MARK: Sign in with Apple

    /// 由 AppleSignInCoordinator 拿到 credential 后调用
    @discardableResult
    func signInWithApple(credential: AuthCredential) async throws -> FirebaseAuth.User {
        try await Auth.auth().signIn(with: credential).user
    }

    // MARK: 密码重置

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    // MARK: 退出登录

    func signOut() throws {
        // 退出前移除「本设备」的 token。
        // 注意：fcmTokens 是数组，一个人的账号可能同时登录 iPhone 和 iPad，
        // 因此只能移除当前设备这一个，不能整个删掉，否则会连累其他设备收不到推送。
        if let uid = currentUID {
            Task.detached(priority: .utility) {
                guard let token = try? await Messaging.messaging().token() else { return }
                try? await FirestoreService.shared.removeFCMToken(uid: uid, token: token)
            }
        }
        try Auth.auth().signOut()
    }
}

// MARK: - Firebase 错误本地化

extension AuthErrorCode.Code {
    var localizedMessage: String {
        switch self {
        case .emailAlreadyInUse: return "该邮箱已注册，请直接登录"
        case .invalidEmail: return "邮箱格式不正确"
        case .weakPassword: return "密码强度不足，至少需要 6 位"
        case .wrongPassword: return "密码错误，请重试"
        case .userNotFound: return "该邮箱尚未注册"
        case .userDisabled: return "该账号已被禁用"
        case .tooManyRequests: return "操作过于频繁，请稍后再试"
        case .networkError: return "网络不可用，请检查网络连接"
        case .userTokenExpired: return "登录状态已过期，请重新登录"
        case .invalidCredential: return "邮箱或密码不正确"
        case .operationNotAllowed: return "该登录方式未开启，请检查 Firebase 控制台配置"
        default: return "操作失败，请稍后重试"
        }
    }
}

extension NSError {
    /// 把 Firebase Auth / Firestore 的错误转成中文提示
    var friendlyAuthMessage: String {
        if let code = AuthErrorCode.Code(rawValue: code) {
            return code.localizedMessage
        }
        if code == FirestoreErrorCode.unavailable.rawValue {
            return AppError.networkUnavailable.errorDescription ?? "网络不可用"
        }
        if code == FirestoreErrorCode.permissionDenied.rawValue {
            return "没有权限执行该操作，请检查 Firestore 安全规则"
        }
        return localizedDescription
    }
}
