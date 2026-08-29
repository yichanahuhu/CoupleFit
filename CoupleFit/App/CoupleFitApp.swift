import SwiftUI

@main
struct CoupleFitApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// 全局状态（iOS 17 @Observable）
    @State private var appState = AppState()
    @StateObject private var networkMonitor = NetworkMonitor.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environmentObject(networkMonitor)
                .tint(.pink)
                .preferredColorScheme(nil) // 跟随系统，支持深色模式
        }
    }
}
