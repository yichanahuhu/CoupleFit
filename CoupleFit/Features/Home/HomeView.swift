import Foundation
import SwiftUI

// MARK: - 首页

/// 今日页：问候语 + 连续打卡 + 我的卡片 + 对方卡片。
struct HomeView: View {

    @Environment(AppState.self) private var appState
    /// 由 MainTabView 注入时可直接切换到设置页；未注入时退化成文字提示
    @Binding var selectedTab: MainTabView.Tab

    init(selectedTab: Binding<MainTabView.Tab>) {
        self._selectedTab = selectedTab
    }

    /// 超过此宽度改为双栏并排。iPad mini 6 竖屏 744pt、iPhone 横屏均会触发；
    /// iPhone 竖屏（393–430pt）保持单栏。
    private static let wideThreshold: CGFloat = 680
    /// 超宽屏（iPad 横屏 1133pt）下的内容宽度上限，避免卡片被拉成横幅
    private static let maxContentWidth: CGFloat = 900

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 16) {
                        headerSection

                        if geo.size.width >= Self.wideThreshold {
                            HStack(alignment: .top, spacing: 16) {
                                SelfCardView(selectedTab: $selectedTab)
                                PartnerCardView()
                            }
                        } else {
                            SelfCardView(selectedTab: $selectedTab)
                            PartnerCardView()
                        }
                    }
                    // 先限宽再撑满，实现「超宽屏时居中」
                    .frame(maxWidth: Self.maxContentWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("今日")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            openSettings()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                .refreshable {
                    await appState.refreshDayBoundaryIfNeeded()
                    await appState.startListening()
                }
                .onAppear {
                    appState.refreshDayBoundaryIfNeeded()
                }
                .toast(toastBinding)
                .alert("出错了", isPresented: errorBinding) {
                    Button("知道了", role: .cancel) { appState.errorMessage = nil }
                } message: {
                    Text(appState.errorMessage ?? "")
                }
            }
        }
    }

    // MARK: 顶部

    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            streakBadge
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var streakBadge: some View {
        VStack(spacing: 2) {
            Image(systemName: "flame.fill")
                .foregroundStyle(appState.myStreak.days > 0 ? .orange : .secondary)
            Text("连续 \(appState.myStreak.days) 天")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "早上好"
        case 12..<18: return "下午好"
        default: return "晚上好"
        }
    }

    private var subtitle: String {
        let dateText = DateHelper.monthDayFormatter.string(from: Date())
        if appState.hasPartner {
            let name = appState.partnerProfile?.displayName ?? ""
            let partnerName = name.isEmpty ? "TA" : name
            return "\(dateText) · 和 \(partnerName) 一起加油"
        }
        return dateText
    }

    // MARK: 绑定

    // @Environment 不提供 $ 投影，这里手动构造 Binding 读写 AppState
    private var toastBinding: Binding<String?> {
        Binding(
            get: { appState.toastMessage },
            set: { appState.toastMessage = $0 }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )
    }

    /// 直接切换到底部「设置」标签页
    private func openSettings() {
        selectedTab = .settings
    }
}

#Preview {
    HomeView(selectedTab: .constant(.home))
        .environment(AppState())
}
