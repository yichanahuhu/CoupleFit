import Foundation
import SwiftUI

// MARK: - 对方的今日卡片

/// 展示对方今天的进度，并提供点赞与提醒两个互动入口。
/// 未绑定情侣时整块替换为配对引导。
struct PartnerCardView: View {

    @Environment(AppState.self) private var appState

    @State private var isReminding = false
    @State private var isLikeBouncing = false
    @State private var showPairing = false

    private var partner: UserProfile? { appState.partnerProfile }
    private var partnerName: String {
        let name = partner?.displayName ?? ""
        return name.isEmpty ? "TA" : name
    }
    private var exerciseType: ExerciseType { partner?.exerciseType ?? .jump }
    private var summary: DailySummary { appState.partnerSummary }
    private var goal: Goal? { appState.partnerGoal }
    private var progress: Double { summary.overallProgress(goal: goal) }
    private var isLiked: Bool { appState.myLikeToPartnerToday != nil }
    private var isGoalReached: Bool { summary.isGoalReached(goal: goal) }

    var body: some View {
        Group {
            if appState.hasPartner {
                partnerCard
            } else {
                pairingCard
            }
        }
        .sheet(isPresented: $showPairing) {
            PairingView(isBlocking: false)
        }
    }

    // MARK: 已绑定

    private var partnerCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                header
                ringSection
                pillsSection
                if isGoalReached {
                    celebrateBadge
                }
                interactionRow
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(partnerName)
                    .font(.headline)
                Text(isGoalReached ? "今天已经达标啦" : "今天还没完成目标")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            typeTag
        }
    }

    private var typeTag: some View {
        Label(exerciseType.displayName, systemImage: exerciseType.systemImage)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(exerciseType.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(exerciseType.accentColor)
    }

    private var ringSection: some View {
        VStack(spacing: 10) {
            ProgressRingView(
                progress: progress,
                lineWidth: 14,
                tint: exerciseType.accentColor,
                label: "\(Int((progress * 100).rounded()))%",
                sublabel: goal == nil ? "未设目标" : "TA 的完成度"
            )
            .frame(maxWidth: 150)
            .frame(maxWidth: .infinity)

            if let goal {
                Text("目标 \(goal.dailyDurationSeconds.minutesText) · \(goal.dailyCount) \(exerciseType.unitName)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("TA 还没有设置目标")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var pillsSection: some View {
        HStack(alignment: .top, spacing: 8) {
            DataPill(title: "时长", value: summary.durationText, tint: exerciseType.accentColor)
            DataPill(title: exerciseType.unitName + "数",
                     value: "\(summary.count) \(exerciseType.unitName)")
            DataPill(title: "记录", value: "\(summary.recordCount) 次")
        }
    }

    private var celebrateBadge: some View {
        HStack(spacing: 6) {
            Text("🎉")
            Text("TA 今天达标啦，快去夸夸 TA")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var interactionRow: some View {
        HStack(spacing: 12) {
            likeButton
            remindButton
        }
    }

    private var likeButton: some View {
        Button {
            Task {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) { isLikeBouncing = true }
                await appState.toggleLikeToPartner()
                try? await Task.sleep(nanoseconds: 220_000_000)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { isLikeBouncing = false }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .foregroundStyle(isLiked ? .pink : .secondary)
                    .scaleEffect(isLikeBouncing ? 1.35 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.4), value: isLikeBouncing)
                VStack(alignment: .leading, spacing: 1) {
                    Text(isLiked ? "已点赞" : "点赞")
                        .font(.subheadline.weight(.medium))
                    Text("今天收到 \(appState.likesReceivedToday.count) 个赞")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(Color.pink.opacity(isLiked ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var remindButton: some View {
        Button {
            Task { await remindPartner() }
        } label: {
            HStack(spacing: 6) {
                if isReminding {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "bell.badge")
                }
                Text(isReminding ? "发送中…" : "提醒 TA")
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isReminding)
    }

    // MARK: 未绑定

    private var pairingCard: some View {
        CardContainer {
            VStack(spacing: 14) {
                EmptyStateView(
                    systemImage: "person.2.badge.gearshape",
                    title: "还没有绑定情侣",
                    subtitle: "绑定后就能看到对方的今日进度，互相督促"
                )
                Button {
                    showPairing = true
                } label: {
                    Label("去配对", systemImage: "link")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: 动作

    @MainActor
    private func remindPartner() async {
        guard let partnerUID = appState.myProfile?.partnerId, !partnerUID.isEmpty else {
            appState.errorMessage = AppError.noPartner.errorDescription
            return
        }
        isReminding = true
        defer { isReminding = false }
        do {
            try await MessagingService.shared.remindPartner(
                partnerUID: partnerUID,
                senderName: appState.myProfile?.displayName ?? "你的另一半",
                exerciseType: exerciseType
            )
            appState.toastMessage = "已提醒 TA 🔔"
        } catch {
            appState.errorMessage = (error as NSError).friendlyAuthMessage
        }
    }
}

#Preview {
    ScrollView {
        PartnerCardView()
            .padding()
    }
    .background(Color(.systemGroupedBackground))
    .environment(AppState())
}
