import Combine
import SwiftUI
import UIKit
import UserNotifications

// MARK: - 设置
//
// 跨文件依赖（由 Profile / Pairing 模块并行编写，本文件只引用、不定义）：
//   ProfileSetupView(isFirstTimeSetup: Bool)
//   PairingView(isBlocking: Bool)

struct SettingsView: View {

    @Environment(AppState.self) private var appState

    // 目标草稿
    @State private var durationMinutes: Int = Constants.defaultDailyDurationSeconds / 60
    @State private var countTarget: Int = Constants.defaultDailyCount
    @State private var reminderEnabled: Bool = true
    @State private var reminderDate: Date = Date()
    @State private var remindPartner: Bool = false

    // 通知
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isNotificationDenied = false

    // 弹层
    @State private var showUnbindConfirm = false
    @State private var showPairing = false
    @State private var showSignOutConfirm = false

    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                goalSection
                reminderSection
                relationshipSection
                accountSection
                aboutSection
            }
            .navigationTitle("设置")
            .task { @MainActor in
                syncFromGoal()
                await refreshAuthorizationStatus()
            }
            .onChange(of: appState.myGoal) { _, _ in
                syncFromGoal()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { @MainActor in await refreshAuthorizationStatus() }
            }
            .sheet(isPresented: $showPairing) {
                PairingView(isBlocking: false)
            }
            .confirmationDialog("解除绑定", isPresented: $showUnbindConfirm) {
                Button("解除绑定", role: .destructive) {
                    Task { await unbind() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("解绑后双方将不再看到彼此的数据，历史记录会保留。")
            }
            .confirmationDialog("退出登录", isPresented: $showSignOutConfirm) {
                Button("退出登录", role: .destructive) {
                    Task { await signOut() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("退出后需要重新登录才能查看数据。")
            }
            .toast(toastBinding)
            .alert("出错了", isPresented: isShowingError) {
                Button("知道了", role: .cancel) {
                    appState.errorMessage = nil
                }
            } message: {
                Text(appState.errorMessage ?? "")
            }
        }
    }

    // MARK: - 我的资料

    private var profileSection: some View {
        Section {
            NavigationLink {
                ProfileSetupView(isFirstTimeSetup: false)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: exerciseType.systemImage)
                        .foregroundStyle(exerciseType.accentColor)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.body)
                        Text(email.isEmpty ? "未绑定邮箱" : email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(exerciseType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("我的资料")
        } footer: {
            Text("点击修改昵称与运动类型。运动类型决定了计数单位（\(exerciseType.unitName)）与卡路里估算方式。")
        }
    }

    // MARK: - 目标设置

    private var goalSection: some View {
        Section {
            Stepper(value: $durationMinutes,
                    in: Constants.durationRange,
                    step: Constants.durationStep) {
                HStack {
                    Text("每日时长")
                    Spacer()
                    Text("\(durationMinutes) 分钟")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .onChange(of: durationMinutes) { _, _ in
                scheduleSave()
            }

            Stepper(value: $countTarget,
                    in: Constants.countRange,
                    step: Constants.countStep) {
                HStack {
                    Text("每日\(exerciseType.unitName)数")
                    Spacer()
                    Text("\(countTarget) \(exerciseType.unitName)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .onChange(of: countTarget) { _, _ in
                scheduleSave()
            }
        } header: {
            Text("每日目标")
        } footer: {
            Text("目标用于首页进度环与每日提醒文案，改动后会自动保存。")
        }
    }

    // MARK: - 提醒设置

    private var reminderSection: some View {
        Section {
            Toggle("每日提醒", isOn: reminderToggle)

            if reminderEnabled {
                DatePicker("提醒时间",
                           selection: $reminderDate,
                           displayedComponents: .hourAndMinute)
                    .onChange(of: reminderDate) { _, _ in
                        scheduleSave()
                    }

                Toggle("提醒时同时通知对方", isOn: Binding(
                    get: { remindPartner },
                    set: { newValue in
                        remindPartner = newValue
                        scheduleSave()
                    }
                ))
            }

            HStack {
                Text("通知权限")
                Spacer()
                Text(authorizationStatusText)
                    .font(.footnote)
                    .foregroundStyle(authorizationStatusColor)
            }

            if isNotificationDenied {
                HStack(spacing: 12) {
                    Text(AppError.notificationDenied.errorDescription ?? "通知权限未开启")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("去设置") {
                        NotificationService.shared.openSystemSettings()
                    }
                    .font(.footnote)
                }
            }
        } header: {
            Text("每日提醒")
        } footer: {
            Text("提醒会在本地按时触发，无需联网。开启「同时通知对方」后，对方也会收到一次推送。")
        }
    }

    // MARK: - 情侣关系

    private var relationshipSection: some View {
        Section {
            if appState.hasPartner {
                HStack {
                    Text("对方")
                    Spacer()
                    Text(partnerName)
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    showUnbindConfirm = true
                } label: {
                    Text("解除绑定")
                }
            } else {
                Button {
                    showPairing = true
                } label: {
                    Label("去配对", systemImage: "heart.fill")
                }
            }
        } header: {
            Text("情侣关系")
        } footer: {
            Text(appState.hasPartner ? "解绑后需要重新配对才能再次查看对方的数据。" : "完成配对后，你们就能看到彼此的运动记录与统计。")
        }
    }

    // MARK: - 账号

    private var accountSection: some View {
        Section {
            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                Text("退出登录")
            }
        } header: {
            Text("账号")
        } footer: {
            Text(email.isEmpty ? "" : "当前登录：\(email)")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("版本")
                Spacer()
                Text(appVersionText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("CoupleFit · 一起运动，一起坚持")
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 数据派生

    private var exerciseType: ExerciseType {
        appState.myProfile?.exerciseType ?? .hulaHoop
    }

    private var displayName: String {
        let name = appState.myProfile?.displayName ?? ""
        return name.isEmpty ? "未设置昵称" : name
    }

    private var email: String {
        appState.myProfile?.email ?? ""
    }

    private var partnerName: String {
        appState.partnerProfile?.displayName ?? "对方"
    }

    private var appVersionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private var reminderToggle: Binding<Bool> {
        Binding(
            get: { reminderEnabled },
            set: { newValue in
                Task { await handleReminderToggle(newValue) }
            }
        )
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )
    }

    private var toastBinding: Binding<String?> {
        Binding(
            get: { appState.toastMessage },
            set: { appState.toastMessage = $0 }
        )
    }

    private var authorizationStatusText: String {
        switch authorizationStatus {
        case .authorized: return "已开启"
        case .provisional: return "临时授权"
        case .ephemeral: return "临时授权"
        case .notDetermined: return "未选择"
        case .denied: return "已关闭"
        @unknown default: return "未知"
        }
    }

    private var authorizationStatusColor: Color {
        switch authorizationStatus {
        case .authorized: return .green
        case .provisional, .ephemeral: return .orange
        case .notDetermined: return .secondary
        case .denied: return .red
        @unknown default: return .secondary
        }
    }

    // MARK: - 同步与保存

    @MainActor
    private func syncFromGoal() {
        let goal = appState.myGoal
        let goalMinutes = (goal?.dailyDurationSeconds ?? Constants.defaultDailyDurationSeconds) / 60
        durationMinutes = min(max(goalMinutes, Constants.durationRange.lowerBound), Constants.durationRange.upperBound)
        countTarget = min(max(goal?.dailyCount ?? Constants.defaultDailyCount,
                              Constants.countRange.lowerBound),
                          Constants.countRange.upperBound)
        reminderEnabled = goal?.reminderEnabled ?? true
        remindPartner = goal?.remindPartner ?? false
        reminderDate = DateHelper.nextDate(hour: goal?.reminderHour ?? 20,
                                           minute: goal?.reminderMinute ?? 0) ?? Date()
    }

    /// 目标与提醒改动后防抖保存，避免拖动 Stepper 时高频写入
    @MainActor
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 600_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await saveGoal()
        }
    }

    @MainActor
    private func saveGoal() async {
        guard let uid = appState.uid else {
            appState.errorMessage = AppError.notSignedIn.errorDescription
            return
        }

        // goals 的文档 id 就是 userId：已有目标沿用其 id，新建时随初始化写入
        var goal = appState.myGoal ?? Goal(id: uid, userId: uid)
        goal.userId = uid
        goal.dailyDurationSeconds = durationMinutes * 60
        goal.dailyCount = countTarget
        goal.reminderEnabled = reminderEnabled
        goal.remindPartner = remindPartner
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderDate)
        goal.reminderHour = components.hour ?? 20
        goal.reminderMinute = components.minute ?? 0

        do {
            try await appState.saveGoal(goal)
        } catch {
            appState.errorMessage = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 打开提醒开关时先申请通知权限；被拒绝则回退开关并给出提示
    @MainActor
    private func handleReminderToggle(_ isOn: Bool) async {
        if isOn {
            do {
                let granted = try await NotificationService.shared.requestAuthorization()
                guard granted else {
                    isNotificationDenied = true
                    reminderEnabled = false
                    return
                }
                isNotificationDenied = false
            } catch {
                isNotificationDenied = true
                reminderEnabled = false
                appState.errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? ((error as? AppError)?.errorDescription ?? error.localizedDescription)
                return
            }
        }
        reminderEnabled = isOn
        scheduleSave()
    }

    @MainActor
    private func refreshAuthorizationStatus() async {
        let settings = await NotificationService.shared.currentSettings()
        authorizationStatus = settings.authorizationStatus
        isNotificationDenied = settings.authorizationStatus == .denied
    }

    // MARK: - 账号操作

    @MainActor
    private func unbind() async {
        do {
            try await appState.unbind()
            appState.toastMessage = "已解除绑定"
        } catch {
            appState.errorMessage = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func signOut() async {
        do {
            try await AuthService.shared.signOut()
            appState.reset()
        } catch {
            appState.errorMessage = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
