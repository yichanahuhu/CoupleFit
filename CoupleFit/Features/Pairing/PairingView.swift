import Combine
import SwiftUI
import UIKit

// MARK: - 情侣配对

/// 两种形态：
/// - `isBlocking = true`：未绑定时由 RootView 强制展示，提供「退出登录」出口
/// - `isBlocking = false`：从设置页进入，展示绑定状态并支持解绑
struct PairingView: View {

    let isBlocking: Bool

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var generatedCode: PairCode?
    @State private var isGenerating = false
    @State private var remainingSeconds = 0
    @State private var isCodeExpired = false

    @State private var inputCode = ""
    @State private var isBinding = false

    @State private var errorMessage: String?
    @State private var toastMessage: String?
    @State private var showUnbindConfirm = false
    @State private var isUnbinding = false
    @State private var isSigningOut = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isPaired: Bool { appState.myProfile?.isPaired == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isBlocking {
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            Task { await signOut() }
                        } label: {
                            if isSigningOut {
                                ProgressView()
                            } else {
                                Text("退出登录").font(.footnote)
                            }
                        }
                    }
                }

                header

                if isPaired {
                    partnerSection
                } else {
                    guideSection
                    generateSection
                    inputSection
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .readableWidth()
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("情侣配对")
        .navigationBarTitleDisplayMode(.inline)
        .toast($toastMessage)
        .onReceive(timer) { _ in
            refreshRemainingTime()
        }
        .confirmationDialog("确定解除绑定吗？",
                            isPresented: $showUnbindConfirm,
                            titleVisibility: .visible) {
            Button("解除绑定", role: .destructive) {
                Task { await unbind() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("解绑后双方将无法看到对方的运动数据，需要重新配对才能恢复。")
        }
    }

    // MARK: 界面

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(colors: [.pink, .orange], startPoint: .top, endPoint: .bottom)
                )
            Text("找到你的另一半")
                .font(.title2.weight(.bold))
            Text("绑定后，双方可以看到彼此每天的运动记录、目标完成度，并互相点赞。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var guideSection: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text("配对流程")
                    .font(.headline)
                guideRow(index: "1", text: "一方点击「生成配对码」，把 6 位数字发给对方")
                guideRow(index: "2", text: "另一方在下方输入这 6 位数字，点击「绑定」")
                guideRow(index: "3", text: "双方自动完成绑定，即可开始一起打卡")
                Text("配对码 10 分钟内有效，过期后重新生成即可；不能使用自己生成的配对码。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
    }

    private func guideRow(index: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(index)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(.pink, in: Circle())
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 生成配对码

    private var generateSection: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("我的配对码")
                        .font(.headline)
                    Spacer()
                    if let generatedCode {
                        Button {
                            Task { await generateCode() }
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                                .font(.footnote)
                        }
                        .disabled(isGenerating)
                    }
                }

                if let pairCode = generatedCode {
                    Button {
                        copyToPasteboard(pairCode.code)
                    } label: {
                        VStack(spacing: 8) {
                            Text(pairCode.code)
                                .font(.system(.largeTitle, design: .monospaced))
                                .tracking(10)
                                .foregroundStyle(isCodeExpired ? .tertiary : .primary)

                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc")
                                Text(isCodeExpired ? "已过期，请重新生成" : "点击复制")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Color(.tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isCodeExpired)

                    HStack(spacing: 6) {
                        Image(systemName: isCodeExpired ? "clock.badge.exclamationmark" : "clock")
                        Text(isCodeExpired ? "配对码已失效" : "剩余 \(countdownText)")
                    }
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(isCodeExpired ? Color.red : Color.secondary)
                } else {
                    Button {
                        Task { await generateCode() }
                    } label: {
                        HStack(spacing: 8) {
                            if isGenerating {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("生成配对码")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(.white)
                        .background(
                            (isGenerating ? Color.pink.opacity(0.45) : Color.pink),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }
                    .disabled(isGenerating)
                }
            }
        }
    }

    // MARK: 输入配对码

    private var inputSection: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("输入对方的配对码")
                    .font(.headline)

                TextField("6 位数字", text: $inputCode)
                    .keyboardType(.numberPad)
                    .font(.system(.title3, design: .monospaced))
                    .tracking(6)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
                    .background(
                        Color(.tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .onChange(of: inputCode) { _, newValue in
                        let digits = newValue.filter { $0.isNumber }
                        let limited = String(digits.prefix(Constants.pairCodeLength))
                        if limited != newValue {
                            inputCode = limited
                        }
                    }

                Button {
                    Task { await bind() }
                } label: {
                    HStack(spacing: 8) {
                        if isBinding {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("绑定")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundStyle(.white)
                    .background(
                        (isBinding || inputCode.count < Constants.pairCodeLength
                         ? Color.pink.opacity(0.45) : Color.pink),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
                .disabled(isBinding || inputCode.count < Constants.pairCodeLength)
            }
        }
    }

    // MARK: 已绑定

    private var partnerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardContainer {
                VStack(alignment: .leading, spacing: 14) {
                    Label("已绑定", systemImage: "heart.fill")
                        .font(.headline)
                        .foregroundStyle(.pink)

                    if let partner = appState.partnerProfile {
                        HStack(spacing: 14) {
                            Image(systemName: partner.exerciseType.systemImage)
                                .font(.title)
                                .foregroundStyle(partner.exerciseType.accentColor)
                                .frame(width: 44)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(partner.displayName)
                                    .font(.title3.weight(.semibold))
                                Text("运动类型：\(partner.exerciseType.displayName)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在同步对方资料…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !isBlocking {
                Button(role: .destructive) {
                    showUnbindConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        if isUnbinding {
                            ProgressView()
                        }
                        Text("解除绑定")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
                .disabled(isUnbinding)
            }
        }
    }

    // MARK: 动作

    @MainActor
    private func generateCode() async {
        guard let uid = appState.uid else {
            errorMessage = AppError.notSignedIn.errorDescription
            return
        }

        errorMessage = nil
        isGenerating = true
        defer { isGenerating = false }

        do {
            let pairCode = try await PairingService().generateCode(for: uid)
            generatedCode = pairCode
            isCodeExpired = pairCode.isExpired
            remainingSeconds = max(0, Int(Date(timeIntervalSince1970: pairCode.expiresAt).timeIntervalSinceNow))
        } catch {
            errorMessage = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func bind() async {
        guard let uid = appState.uid else {
            errorMessage = AppError.notSignedIn.errorDescription
            return
        }

        let code = inputCode
        guard code.count == Constants.pairCodeLength else {
            errorMessage = AppError.pairCodeNotFound.errorDescription
            return
        }

        errorMessage = nil
        isBinding = true
        defer { isBinding = false }

        do {
            _ = try await PairingService().bind(using: code, currentUID: uid)
            inputCode = ""
            generatedCode = nil
            appState.refreshAll()
            toastMessage = "配对成功 💗"
        } catch {
            // 已绑定彼此：服务端删除配对码后抛出，视为成功
            if let appError = error as? AppError, case .alreadyPaired = appError {
                inputCode = ""
                generatedCode = nil
                appState.refreshAll()
                toastMessage = appError.errorDescription
                return
            }
            errorMessage = localizedMessage(for: error)
        }
    }

    @MainActor
    private func unbind() async {
        errorMessage = nil
        isUnbinding = true
        defer { isUnbinding = false }

        do {
            try await appState.unbind()
            generatedCode = nil
            inputCode = ""
            toastMessage = "已解除绑定"
        } catch {
            errorMessage = localizedMessage(for: error)
        }
    }

    @MainActor
    private func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        try? AuthService.shared.signOut()
    }

    // MARK: 辅助

    private var countdownText: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    private func refreshRemainingTime() {
        guard let pairCode = generatedCode else { return }
        let remaining = Int(Date(timeIntervalSince1970: pairCode.expiresAt).timeIntervalSinceNow)
        remainingSeconds = max(0, remaining)
        isCodeExpired = remaining <= 0
    }

    private func copyToPasteboard(_ text: String) {
        UIPasteboard.general.string = text
        toastMessage = "配对码已复制"
    }

    /// 把 AppError / Firebase 错误转成准确的中文提示
    private func localizedMessage(for error: Error) -> String {
        if let appError = error as? AppError {
            return appError.errorDescription ?? "配对失败，请重试"
        }
        let nsError = error as NSError
        // FirestoreService.bindPartners 以 domain = "CoupleFit" 的 NSError 抛出绑定冲突
        if nsError.domain == "CoupleFit" {
            return nsError.localizedDescription
        }
        return (nsError as? AppError)?.errorDescription ?? nsError.localizedDescription
    }
}

#Preview("未配对") {
    PairingView(isBlocking: true)
        .environment(AppState())
}

#Preview("设置页入口") {
    PairingView(isBlocking: false)
        .environment(AppState())
}
