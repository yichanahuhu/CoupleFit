import Foundation

// MARK: - 当前登录用户

struct AuthUser {
    let uid: String
    let email: String
    let displayName: String
}

// MARK: - 认证服务（LeanCloud 邮箱密码）

/// 注册/登录/登出/密码重置全部走 LeanCloud REST。
/// 会话 token 持久化到 UserDefaults，启动时静默恢复（不联网校验，
/// 失效后下次请求自然返回 401 并由上层引导重新登录）。
@MainActor
final class AuthService: ObservableObject {

    static let shared = AuthService()

    @Published private(set) var currentUser: AuthUser?

    private let client = LeanCloudClient.shared
    private let sessionKey = "couplefit_lc_session"

    private init() {
        restoreSession()
    }

    var currentUID: String? { currentUser?.uid }
    var isSignedIn: Bool { currentUser != nil }

    /// 幂等；实际恢复已在 init 完成，这里保证 client.sessionToken 与内存状态一致
    func start() {
        // no-op：会话已在 init 中恢复
    }

    // MARK: 注册

    @discardableResult
    func signUp(email: String, password: String, displayName: String) async throws -> AuthUser {
        let body: [String: Any] = [
            "username": email,
            "password": password,
            "email": email,
            "displayName": displayName
        ]
        let json = try await client.requestJSON(path: "/users", method: "POST", body: body)
        guard let dict = json as? [String: Any],
              let uid = dict["objectId"] as? String,
              let session = dict["sessionToken"] as? String else {
            throw AppError.unknown("注册失败，请重试")
        }
        let user = AuthUser(uid: uid, email: email, displayName: displayName)
        persistSession(user: user, session: session)
        currentUser = user
        return user
    }

    // MARK: 登录

    @discardableResult
    func signIn(email: String, password: String) async throws -> AuthUser {
        let body: [String: Any] = [
            "username": email,
            "password": password
        ]
        let json = try await client.requestJSON(path: "/login", method: "POST", body: body)
        guard let dict = json as? [String: Any],
              let uid = dict["objectId"] as? String,
              let session = dict["sessionToken"] as? String else {
            throw AppError.unknown("登录失败，请重试")
        }
        let name = (dict["displayName"] as? String) ?? ""
        let mail = (dict["email"] as? String) ?? email
        let user = AuthUser(uid: uid, email: mail, displayName: name)
        persistSession(user: user, session: session)
        currentUser = user
        return user
    }

    // MARK: 密码重置

    func sendPasswordReset(email: String) async throws {
        let body: [String: Any] = ["email": email]
        _ = try await client.requestJSON(path: "/requestPasswordReset", method: "POST", body: body)
    }

    // MARK: 退出登录

    func signOut() throws {
        if client.sessionToken != nil {
            _ = try? await client.requestJSON(path: "/logout", method: "DELETE")
        }
        client.sessionToken = nil
        currentUser = nil
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    // MARK: - 会话持久化

    private func persistSession(user: AuthUser, session: String) {
        client.sessionToken = session
        let payload: [String: String] = [
            "uid": user.uid,
            "email": user.email,
            "displayName": user.displayName,
            "sessionToken": session
        ]
        UserDefaults.standard.set(payload, forKey: sessionKey)
    }

    private func restoreSession() {
        guard let payload = UserDefaults.standard.dictionary(forKey: sessionKey) as? [String: String],
              let uid = payload["uid"], let session = payload["sessionToken"] else { return }
        client.sessionToken = session
        currentUser = AuthUser(uid: uid,
                               email: payload["email"] ?? "",
                               displayName: payload["displayName"] ?? "")
    }
}
