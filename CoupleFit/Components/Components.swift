import SwiftUI

// MARK: - 通用空状态

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let subtitle: String?

    init(systemImage: String, title: String, subtitle: String? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - 卡片容器

struct CardContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 数据项

struct DataPill: View {
    let title: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 分段选择器（我 / TA）

struct PersonSegmentedPicker: View {
    @Binding var selection: PersonTab
    let partnerName: String

    var body: some View {
        Picker("查看对象", selection: $selection) {
            Text("我").tag(PersonTab.me)
            Text(partnerName).tag(PersonTab.partner)
        }
        .pickerStyle(.segmented)
    }
}

enum PersonTab: String, CaseIterable, Identifiable {
    case me
    case partner
    var id: String { rawValue }
}

// MARK: - 错误/成功提示

/// 挂在视图底部的安全区之上的轻提示
struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.8), in: Capsule())
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { self.message = nil }
                            }
                        }
                }
            }
            .animation(.spring(duration: 0.3), value: message)
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

// MARK: - iPad 适配

/// 表单类页面在 iPad 上限制最大宽度并居中。
/// 否则 iPad mini 6（744pt 宽）上的输入框会被拉成一条长横幅，难用也难看。
/// iPhone 宽度不足 560pt，此修饰器不产生任何影响。
struct ReadableWidthModifier: ViewModifier {
    var maxWidth: CGFloat = 560

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func readableWidth(_ maxWidth: CGFloat = 560) -> some View {
        modifier(ReadableWidthModifier(maxWidth: maxWidth))
    }
}

#Preview {
    VStack(spacing: 16) {
        EmptyStateView(systemImage: "figure.walk", title: "今天还没有记录", subtitle: "点下方按钮开始运动吧")
        CardContainer {
            HStack {
                DataPill(title: "时长", value: "12:30", tint: .orange)
                DataPill(title: "圈数", value: "320")
            }
        }
    }
    .padding()
}
