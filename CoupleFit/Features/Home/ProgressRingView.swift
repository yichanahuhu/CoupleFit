import SwiftUI

// MARK: - 环形进度条

/// 用于展示"今日目标完成度"的环形进度条。
/// - progress 可超过 1，超过表示超额完成，环会变成金色并填满一圈。
/// - 尺寸自适应父容器（aspectRatio 1:1），小屏也不会被撑破。
struct ProgressRingView: View {

    let progress: Double
    var lineWidth: CGFloat = 14
    var tint: Color = .accentColor
    var label: String
    var sublabel: String?

    /// 上限高度，避免在 iPad / 大屏上被拉得过大
    private let maxSide: CGFloat = 190

    private var clamped: Double {
        guard progress.isFinite else { return 0 }
        return min(max(progress, 0), 1)
    }

    private var isOverAchieved: Bool { progress > 1.0001 }

    private var ringColor: Color { isOverAchieved ? .yellow : tint }

    var body: some View {
        ZStack {
            // 底环
            Circle()
                .stroke(.quaternary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            // 进度环：从 12 点方向开始
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.6), value: clamped)

            // 中心文字
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                VStack(spacing: side * 0.03) {
                    Text(label)
                        .font(.system(size: side * 0.26, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                    if let sublabel {
                        Text(sublabel)
                            .font(.system(size: side * 0.1))
                            .foregroundStyle(.secondary)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                }
                .multilineTextAlignment(.center)
                // 留出环的厚度，避免文字压到环上
                .padding(side * 0.16)
                .frame(width: side, height: side)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: maxSide, maxHeight: maxSide)
        .animation(.spring(duration: 0.4), value: isOverAchieved)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let sublabel else { return "完成度 \(label)" }
        return "完成度 \(label)，\(sublabel)"
    }
}

#Preview {
    VStack(spacing: 24) {
        HStack(spacing: 20) {
            ProgressRingView(progress: 0.35,
                             tint: .orange,
                             label: "35%",
                             sublabel: "今日完成度")
            ProgressRingView(progress: 1.4,
                             lineWidth: 10,
                             tint: .pink,
                             label: "140%",
                             sublabel: "超额完成")
        }
        ProgressRingView(progress: 0.82,
                         lineWidth: 18,
                         tint: .pink,
                         label: "82%",
                         sublabel: "今日完成度")
            .frame(width: 120)
    }
    .padding()
    .environment(AppState())
}
