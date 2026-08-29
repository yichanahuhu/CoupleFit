import AuthenticationServices
import CryptoKit
import FirebaseAuth
import UIKit

// MARK: - Sign in with Apple 协调器

/// 封装 ASAuthorizationController 的回调，产出 Firebase 需要的 OAuthCredential。
/// 用法：
/// ```
/// let credential = try await AppleSignInCoordinator.shared.signIn(presentationAnchor: window)
/// try await AuthService.shared.signInWithApple(credential: credential)
/// ```
final class AppleSignInCoordinator: NSObject {

    static let shared = AppleSignInCoordinator()

    private var continuation: CheckedContinuation<AuthCredential, Error>?
    private var currentNonce: String?

    func signIn(presentationAnchor: ASPresentationAnchor) async throws -> AuthCredential {
        let nonce = randomNonceString()
        currentNonce = nonce

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    // MARK: Nonce

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if status != errSecSuccess { break }
            if random < 58 || random > 126 { continue }
            result.append(charset[Int(random) % charset.count])
            remaining -= 1
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard
            let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let nonce = currentNonce,
            let identityToken = appleIDCredential.identityToken,
            let idTokenString = String(data: identityToken, encoding: .utf8)
        else {
            continuation?.resume(throwing: AppError.unknown("Apple 登录失败，请重试"))
            continuation = nil
            return
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )
        continuation?.resume(returning: credential)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let authorizationError = error as? ASAuthorizationError,
           authorizationError.code == .canceled {
            continuation?.resume(throwing: AppError.unknown("已取消 Apple 登录"))
        } else {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return UIWindow()
        }
        return window
    }
}
