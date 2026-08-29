import Combine
import Foundation
import SwiftUI

// MARK: - 运动计时器

/// 全屏计时器。支持开始 / 暂停 / 继续 / 结束，并在运动中实时累加圈数（次数）。
/// 计时采用"每秒累加"的方式，暂停与恢复都能精确累计；
/// 进入后台时记录时间戳，回到前台后一次性补上差值，保证后台期间也计入。
struct TimerView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let presetType: ExerciseType?

    @State private var phase: Phase = .idle
    @State private var elapsedSeconds = 0
    @State private var liveCount = 0
    @State private var startDate = Date()
    @State private var endDate = Date()

    /// 进入后台的时间戳；回到前台时据此补时
    @State private var backgroundedAt: Date?
    @State private var showShortConfirm = false
    @State private var showExitConfirm = false
    @State private var editMode: RecordEditMode?
    @State private var countPulse = false

    private let shortRecordThreshold = 10

    init(exerciseType: ExerciseType? = nil) {
        self.presetType = exerciseType
    }

    enum Phase {
        case idle, running, paused, finished
    }

    private var exerciseType: ExerciseType {
        presetType ?? appState.myProfile?.exerciseType ?? .hulaHoop
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundLayer

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    timeDisplay
                    calorieLine
                    Spacer(minLength: 0)
                    counterSection
                    Spacer(minLength: 0)
                    controlButtons
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .navigationTitle(exerciseType.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        requestClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
        // 每秒累加（暂停/结束时直接跳过，不做任何重活）
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard phase == .running else { return }
            elapsedSeconds += 1
        }
        // 后台 → 前台补时
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhase(newPhase)
        }
        .confirmationDialog("时长太短，是否放弃这次记录？",
                            isPresented: $showShortConfirm,
                            titleVisibility: .visible) {
            Button("放弃这次记录", role: .destructive) { dismiss() }
            Button("仍然保存") { presentEditSheet() }
            Button("继续运动", role: .cancel) { phase = .paused }
        } message: {
            Text("本次只有 \(elapsedSeconds) 秒，可能是一次误触。")
        }
        .confirmationDialog("结束并放弃这次记录？",
                            isPresented: $showExitConfirm,
                            titleVisibility: .visible) {
            Button("放弃并退出", role: .destructive) { dismiss() }
            Button("继续计时", role: .cancel) { }
        } message: {
            Text("已计时 \(elapsedSeconds.formattedDuration)，退出后不会保存。")
        }
        .sheet(item: $editMode) { mode in
            RecordEditSheet(mode: mode) { dismiss() }
        }
    }

    // MARK: 界面

    private var backgroundLayer: some View {
        LinearGradient(
            colors: [exerciseType.accentColor.opacity(0.22), Color(.systemGroupedBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var timeDisplay: some View {
        VStack(spacing: 8) {
            Text(phase == .idle ? "准备好了吗？" : statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(elapsedSeconds.formattedDuration)
                // iPad 全屏时放大，避免大屏上数字显得局促
                .font(.system(size: sizeClass == .regular ? 112 : 72,
                              weight: .bold,
                              design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: elapsedSeconds)
                .foregroundStyle(exerciseType.accentColor)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }

    private var statusText: String {
        switch phase {
        case .idle: return "准备好就开始"
        case .running: return "运动中"
        case .paused: return "已暂停"
        case .finished: return "已完成"
        }
    }

    private var calorieLine: some View {
        Label(CalorieEstimator.text(exerciseType: exerciseType, durationSeconds: elapsedSeconds),
              systemImage: "flame.fill")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 12)
            .contentTransition(.numericText())
    }

    /// 运动中每点一次 +1，结束后作为次数默认值传给编辑表单
    private var counterSection: some View {
        VStack(spacing: 12) {
            Text("本次\(exerciseType.unitName)数")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                addCount()
            } label: {
                VStack(spacing: 2) {
                    Text("\(liveCount)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("点一下 +1 \(exerciseType.unitName)")
                        .font(.caption2)
                }
                .foregroundStyle(.white)
                .frame(width: 170, height: 170)
                .background(
                    Circle()
                        .fill(exerciseType.accentColor.gradient)
                        .shadow(color: exerciseType.accentColor.opacity(0.35), radius: 14, y: 6)
                )
            }
            .buttonStyle(.plain)
            .scaleEffect(countPulse ? 0.93 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: countPulse)
            .disabled(phase != .running && phase != .paused)
            .opacity(phase == .running || phase == .paused ? 1 : 0.45)
            // 每点一次给一个"弹一下"的反馈
            .onChange(of: liveCount) { _, _ in
                withAnimation(.spring(response: 0.18, dampingFraction: 0.35)) { countPulse = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { countPulse = false }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var controlButtons: some View {
        HStack(spacing: 16) {
            switch phase {
            case .idle:
                primaryButton("开始", systemImage: "play.fill", tint: exerciseType.accentColor) { start() }
            case .running:
                secondaryButton("暂停", systemImage: "pause.fill") { pause() }
                primaryButton("结束", systemImage: "stop.fill", tint: .red) { finish() }
            case .paused:
                secondaryButton("继续", systemImage: "play.fill") { resume() }
                primaryButton("结束", systemImage: "stop.fill", tint: .red) { finish() }
            case .finished:
                primaryButton("重新计时", systemImage: "arrow.counterclockwise", tint: exerciseType.accentColor) { reset() }
            }
        }
        .frame(maxWidth: 320)
        .padding(.bottom, 8)
    }

    private func primaryButton(_ title: String,
                               systemImage: String,
                               tint: Color,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(tint, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(_ title: String,
                                 systemImage: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(exerciseType.accentColor.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: 逻辑

    private func start() {
        startDate = Date()
        elapsedSeconds = 0
        liveCount = 0
        phase = .running
    }

    private func pause() {
        phase = .paused
    }

    private func resume() {
        phase = .running
    }

    private func reset() {
        phase = .idle
        elapsedSeconds = 0
        liveCount = 0
        backgroundedAt = nil
    }

    private func finish() {
        endDate = Date()
        phase = .finished
        guard elapsedSeconds >= shortRecordThreshold else {
            showShortConfirm = true
            return
        }
        presentEditSheet()
    }

    private func presentEditSheet() {
        editMode = .create(
            startTime: startDate,
            endTime: endDate,
            durationSeconds: elapsedSeconds,
            count: liveCount,
            exerciseType: exerciseType
        )
    }

    private func addCount() {
        liveCount += 1
    }

    private func requestClose() {
        guard elapsedSeconds > 0, (phase == .running || phase == .paused) else {
            dismiss()
            return
        }
        pause()
        showExitConfirm = true
    }

    /// 进入后台记录时间戳，回到前台时把这段真实耗时补进 elapsedSeconds
    private func handleScenePhase(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            guard phase == .running else { return }
            backgroundedAt = Date()
        case .active:
            guard let enteredBackgroundAt = backgroundedAt else { return }
            backgroundedAt = nil
            guard phase == .running else { return }
            let gap = Int(Date().timeIntervalSince(enteredBackgroundAt))
            if gap > 0 { elapsedSeconds += gap }
        default:
            break
        }
    }
}

#Preview {
    TimerView(exerciseType: .hulaHoop)
        .environment(AppState())
}

#Preview {
    TimerView(exerciseType: .jump)
        .environment(AppState())
        .preferredColorScheme(.dark)
}
