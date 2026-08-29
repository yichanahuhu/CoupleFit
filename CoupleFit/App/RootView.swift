import Combine
import SwiftUI
import UIKit

// MARK: - 根视图

/// 根据会话状态分发页面：
/// 未登录 → LoginView
/// 已登录但未设置昵称 → ProfileSetupView
/// 已登录但未绑定 → PairingView
/// 均完成 → 主 Tab
struct RootView: View {

    @Environment(AppState.self) private var appState
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @State private var authService = AuthService.shared
    @State private var isRestoringSession = true

    var body: some View {
        ZStack(alignment: .top) {
            content
                .animation(.easeInOut(duration: 0.25), value: destination)

            if !networkMonitor.isConnected {
                OfflineBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            await restoreSessionIfNeeded()
        }
        .onChange(of: authService.currentUser?.uid) { _, newUID in
            Task { await handleAuthChange(uid: newUID) }
        }
    }

    // MARK: 页面分发

    @ViewBuilder
    private var content: some View {
        if isRestoringSession {
            LaunchPlaceholder()
        } else {
            switch destination {
            case .login:
                LoginView()
            case .profileSetup:
                ProfileSetupView(isFirstTimeSetup: true)
            case .pairing:
                PairingView(isBlocking: true)
            case .main:
                MainTabView()
            }
        }
    }

    private enum Destination {
        case login, profileSetup, pairing, main
    }

    private var destination: Destination {
        guard authService.currentUser != nil else { return .login }
        guard appState.isSessionReady else { return .login }
        guard let profile = appState.myProfile else { return .login }

        if profile.displayName.isEmpty { return .profileSetup }
        if profile.partnerId == nil || profile.partnerId?.isEmpty == true { return .pairing }
        return .main
    }

    // MARK: 会话恢复

    @MainActor
    private func restoreSessionIfNeeded() async {
        defer { isRestoringSession = false }
        // 幂等：确保 Firebase configure 之后再读取 Auth 状态
        authService.start()
        await handleAuthChange(uid: authService.currentUser?.uid)
    }

    private func handleAuthChange(uid: String?) async {
        guard let uid else {
            await MainActor.run { appState.reset() }
            return
        }
        // 已经绑定过同一个用户则跳过
        if appState.uid == uid, appState.isSessionReady { return }

        await appState.bindSession(
            uid: uid,
            fallbackEmail: authService.currentUser?.email,
            fallbackName: authService.currentUser?.displayName
        )
    }
}

// MARK: - 主 Tab

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var selection: Tab = .home

    enum Tab: String, CaseIterable, Identifiable {
        case home, history, stats, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .home: return "今日"
            case .history: return "历史"
            case .stats: return "统计"
            case .settings: return "设置"
            }
        }
        var systemImage: String {
            switch self {
            case .home: return "flame.fill"
            case .history: return "clock.arrow.circlepath"
            case .stats: return "chart.bar.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            HomeView(selectedTab: $selection)
                .tabItem { Label(Tab.home.title, systemImage: Tab.home.systemImage) }
                .tag(Tab.home)

            HistoryView()
                .tabItem { Label(Tab.history.title, systemImage: Tab.history.systemImage) }
                .tag(Tab.history)

            StatsView()
                .tabItem { Label(Tab.stats.title, systemImage: Tab.stats.systemImage) }
                .tag(Tab.stats)

            SettingsView()
                .tabItem { Label(Tab.settings.title, systemImage: Tab.settings.systemImage) }
                .tag(Tab.settings)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            appState.refreshDayBoundaryIfNeeded()
        }
    }
}

// MARK: - 启动占位

private struct LaunchPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("载入中…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - 断网提示条

/// 验收标准要求断网时给出明确提示。
struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
            Text("当前离线，数据将在恢复网络后同步")
                .font(.footnote)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.orange, in: Capsule())
        .padding(.top, 8)
    }
}

#Preview {
    RootView()
        .environment(AppState())
        .environmentObject(NetworkMonitor.shared)
}
