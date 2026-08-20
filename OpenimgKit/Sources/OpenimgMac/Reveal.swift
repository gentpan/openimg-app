import SwiftUI

/// 概览页那些图表的入场动画。
///
/// 统一在一个地方,而不是每张图各画各的:同一页上八个元素各用各的时长和曲线,
/// 看起来不是"一次入场",是八件事凑巧同时发生。这里只出一个 0→1 的进度和一套
/// 时长,各处拿它去乘自己的值。
///
/// 三条纪律:
///
///   1. **尊重系统的「减弱动态效果」。** 打开时直接给 1,一帧不动。这不是可选
///      的润色——对前庭功能敏感的人,大面积的运动会真的引起不适。
///   2. **只在首次出现时跑。** 统计每分钟在后台刷一次,每次刷新都重播一遍的话
///      页面会自己动个不停。
///   3. **数值变化走另一条更短的曲线。** 入场是"画出来",变化是"挪过去";用同
///      一条 0.6 秒的曲线,签到一下进度条会挪得像在放动画片。
struct Reveal: ViewModifier {
    @Binding var progress: Double
    var delay: Double = 0
    var duration: Double = Reveal.duration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 入场时长。折线单独长一点,见 `draw`。
    static let duration: Double = 0.6
    static let draw: Double = 0.85
    /// 数值变化时用的曲线。
    static let change: Animation = .easeOut(duration: 0.28)

    func body(content: Content) -> some View {
        content.onAppear {
            guard progress < 1 else { return }
            guard !reduceMotion else { progress = 1; return }
            withAnimation(.easeOut(duration: duration).delay(delay)) { progress = 1 }
        }
    }
}

extension View {
    /// 出现时把 `progress` 从 0 推到 1。
    func reveal(_ progress: Binding<Double>, delay: Double = 0,
                duration: Double = Reveal.duration) -> some View {
        modifier(Reveal(progress: progress, delay: delay, duration: duration))
    }

    /// 逐个点亮用的曲线:第 `index` 个(共 `count` 个)延迟多久开始。
    ///
    /// 延迟按**占比**算而不是每个固定几毫秒:固定值下,亮 3 格和亮 100 格的总
    /// 时长差 30 倍——前者快得看不见,后者慢得像卡住了。
    func stagger(_ index: Int, of count: Int, on value: some Equatable,
                 muted: Bool, span: Double = 0.45) -> some View {
        let ratio = count > 1 ? Double(index) / Double(count - 1) : 0
        return animation(muted ? nil : .easeOut(duration: 0.24).delay(ratio * span),
                         value: value)
    }
}

/// 一块从 12 点起顺时针张开的扇形,给环形图做扫开的入场。
///
/// 环形图不能靠"把每段的值乘上进度"来扫开——每段同比例缩小之后,各段的角度
/// 占比一模一样,画出来和原图没有区别。得在外面盖一块会张开的遮罩。
struct Wedge: Shape {
    var end: Double

    var animatableData: Double {
        get { end }
        set { end = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(1, max(0, end))
        guard t > 0 else { return Path() }
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        // 半径取对角线,保证四个角也盖得住,否则扫到边角时会露出方形的缺口。
        let r = (rect.width * rect.width + rect.height * rect.height).squareRoot()
        p.move(to: c)
        p.addArc(center: c, radius: r,
                 startAngle: .degrees(-90),
                 endAngle: .degrees(-90 + 360 * t),
                 clockwise: false)
        p.closeSubpath()
        return p
    }
}
