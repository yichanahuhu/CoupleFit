import SwiftUI

// MARK: - 资料设置

/// 设置昵称与运动类型。
/// `isFirstTimeSetup = true` 时由 RootView 强制展示，隐藏返回按钮且不允许跳过。
struct ProfileSetupView: View {

    let isFirstTimeSetup: Bool

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var exerciseType: ExerciseType = .hulaHoop
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var toastMessage: String?
    @FocusState private var isNameFocused: Bool

    private let nameLimit = 12

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                nameSection
                exerciseTypeSection
                hintSection

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                saveButton
            }
            .readableWidth()
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(isFirstTimeSetup ? "完善资料" : "个人资料")
        .navigationBarBackButtonHidden(isFirstTimeSetup)
        .toast($toastMessage)
        .task {
            if let profile = appState.myProfile {
                displayName = profile.displayName
                exerciseType = profile.exerciseType
            }
            if isFirstTimeSetup {
                isNameFocused = true
            }
        }
    }

    // MARK: 界面

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(colors: [.pink, .orange], startPoint: .top, endPoint: .bottom)
                )
            Text(isFirstTimeSetup ? "先认识一下你" : "修改个人资料")
                .font(.title2.weight(.bold))
            Text("昵称会展示给对方，运动类型决定你的记录方式与卡路里估算。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nameSection: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("昵称")
                        .font(.headline)
                    Spacer()
                    Text("\(displayName.count)/\(nameLimit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                TextField("请输入昵称", text: $displayName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                    .background(
                        Color(.tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .onChange(of: displayName) { _, newValue in
                        if newValue.count > nameLimit {
                            displayName = String(newValue.prefix(nameLimit))
                        }
                    }
            }
        }
    }

    private var exerciseTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("我的运动类型")
                .font(.headline)

            ForEach(ExerciseType.allCases) { type in
                Button {
                    withAnimation(.spring(duration: 0.2)) {
                        exerciseType = type
                    }
                } label: {
                    typeCard(type)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func typeCard(_ type: ExerciseType) -> some View {
        let isSelected = type == exerciseType

        return HStack(spacing: 14) {
            Image(systemName: type.systemImage)
                .font(.title)
                .foregroundStyle(type.accentColor)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(type.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("计数单位：\(type.unitName)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("约 \(Int(type.kcalPerMinute)) kcal/分钟")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(type.accentColor)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? type.accentColor.opacity(0.10) : Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? type.accentColor : Color.clear, lineWidth: 2)
        }
    }

    private var hintSection: some View {
        Text("运动类型选定后主要用于卡路里估算和首页展示，之后也可以在设置里修改。")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                }
                Text("保存")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(.white)
            .background(
                (isSaving ? Color.pink.opacity(0.45) : Color.pink),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .disabled(isSaving)
    }

    // MARK: 动作

    @MainActor
    private func save() async {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "请填写昵称"
            return
        }

        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        do {
            try await appState.saveProfile(displayName: name, exerciseType: exerciseType)
            if isFirstTimeSetup {
                toastMessage = "资料已保存"
            } else {
                dismiss()
            }
        } catch {
            errorMessage = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("首次设置") {
    ProfileSetupView(isFirstTimeSetup: true)
        .environment(AppState())
}

#Preview("设置页修改") {
    ProfileSetupView(isFirstTimeSetup: false)
        .environment(AppState())
}
