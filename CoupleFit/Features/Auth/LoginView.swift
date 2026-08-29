import SwiftUI
import UIKit

// MARK: - 登录 / 注册

/// 邮箱密码登录注册 + Sign in with Apple。
/// 登录成功后由 RootView 监听 Auth 状态变化并调用 AppState.bindSession 创建 users 文档。
struct LoginView: View {

    enum Mode: String, CaseIterable, Identifiable {
        case signIn
        case signUp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .signIn: return "登录"
            case .signUp: return "注册"
            }
        }

        var submitTitle: String {
            switch self {
            case .signIn: return "登录"
            case .signUp: return "注册并开始"
            }
        }
    }

    @Environment(AppState.self) private var appState
    @State private var authService = AuthService.shared

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var nickname = ""
    @State private var isSubmitting = false
    /// 提交过一次后才展示内联校验提示，避免刚进页面就飘红
    @State private var showValidation = false
    @State private var toastMessage: String?

    var body: some View {
        ZStack {
            backgroundGradient

            ScrollView {
                VStack(spacing: 24) {
                    header
                    form
                    slogan
                }
                .readableWidth()
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toast($toastMessage)
    }

    // MARK: 界面

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.pink.opacity(0.20),
                Color.orange.opacity(0.14),
                Color(.systemGroupedBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(colors: [.pink, .orange], startPoint: .top, endPoint: .bottom)
                )

            Text("CoupleFit")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))

            Text("一起打卡，把坚持变成两个人的事")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
    }

    private var form: some View {
        CardContainer {
            VStack(spacing: 16) {
                Picker("模式", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, _ in
                    showValidation = false
                    appState.errorMessage = nil
                }

                VStack(alignment: .leading, spacing: 6) {
                    fieldTitle("邮箱")
                    TextField("you@example.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                        .textFieldStyle(.roundedBorder)
                    if let text = emailErrorText {
                        fieldError(text)
                    }
                }

                if mode == .signUp {
                    VStack(alignment: .leading, spacing: 6) {
                        fieldTitle("昵称")
                        TextField("对方将看到这个名字", text: $nickname)
                            .textInputAutocapitalization(.never)
                            .textContentType(.nickname)
                            .textFieldStyle(.roundedBorder)
                        if let text = nicknameErrorText {
                            fieldError(text)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    fieldTitle("密码")
                    SecureField("至少 6 位", text: $password)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                        .textFieldStyle(.roundedBorder)
                    if let text = passwordErrorText {
                        fieldError(text)
                    }
                }

                HStack {
                    Spacer()
                    Button("忘记密码？") {
                        Task { await sendPasswordReset() }
                    }
                    .font(.footnote)
                    .disabled(isSubmitting)
                }

                if let message = appState.errorMessage {
                    fieldError(message)
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(mode.submitTitle)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(.white)
                    .background(
                        (isSubmitting ? Color.pink.opacity(0.45) : Color.pink),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
                .disabled(isSubmitting)
            }
        }
    }

    private var slogan: some View {
        Text("每天 20 分钟，和 TA 一起变得更健康")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }

    private func fieldTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func fieldError(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 校验

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var emailErrorText: String? {
        guard showValidation else { return nil }
        if trimmedEmail.isEmpty { return "请输入邮箱" }
        if !Self.isValidEmail(trimmedEmail) { return "邮箱格式不正确" }
        return nil
    }

    private var passwordErrorText: String? {
        guard showValidation else { return nil }
        if password.isEmpty { return "请输入密码" }
        if password.count < 6 { return "密码至少 6 位" }
        return nil
    }

    private var nicknameErrorText: String? {
        guard showValidation, mode == .signUp else { return nil }
        if trimmedNickname.isEmpty { return "请输入昵称" }
        return nil
    }

    private static func isValidEmail(_ text: String) -> Bool {
        let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: text)
    }

    // MARK: 动作

    @MainActor
    private func submit() async {
        showValidation = true
        appState.errorMessage = nil
        toastMessage = nil

        guard emailErrorText == nil,
              passwordErrorText == nil,
              nicknameErrorText == nil else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            switch mode {
            case .signIn:
                try await authService.signIn(email: trimmedEmail, password: password)
            case .signUp:
                try await authService.signUp(email: trimmedEmail,
                                             password: password,
                                             displayName: trimmedNickname)
            }
        } catch {
            appState.errorMessage = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func sendPasswordReset() async {
        appState.errorMessage = nil

        guard Self.isValidEmail(trimmedEmail) else {
            appState.errorMessage = "请先在上方填写正确的邮箱"
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await authService.sendPasswordReset(email: trimmedEmail)
            toastMessage = "重置密码邮件已发送，请查收"
        } catch {
            appState.errorMessage = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: 窗口

    /// 从 connectedScenes 里取当前 keyWindow，避免使用已废弃的 UIApplication.shared.keyWindow
    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}

#Preview {
    LoginView()
        .environment(AppState())
}
