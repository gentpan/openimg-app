import SwiftUI

/// 页面入场:各模块按视觉层级依次进入,而不是整页一起亮。
///
/// 顺序本身就是信息:侧栏 → 顶栏 → 卡片区(**整块一起**)→ 卡片里的内容(依次
/// 填充)。它告诉眼睛先看哪儿。整页同时出现的话,读者要自己在一屏东西里找落
/// 点;依次进入等于替他排了一遍。
///
/// 卡片刻意**不**一张一张弹:七张卡各占一个节拍,光排完就要小半秒,而它们本来
/// 就是一屏里同一层的东西,没有先后之分——真正有层级的是"容器"和"内容",框先
/// 立住,数字和图表再填进去。
///
/// 四条参数一起动,少一条都会露怯:
///
///   - 只有透明度 = 一块东西凭空亮起来,没有"来"的感觉;
///   - 加上位移和缩放才像是从后面推上来的;
///   - 模糊是让它"对上焦",没有它,位移看着像元素在滑动而不是在到位。
///
/// 曲线是 cubic-bezier(0.16, 1, 0.3, 1):开头极快、末端长长地收住,没有任何回
/// 弹。刻意不用 spring——弹一下会把注意力吸到动画本身,而这里要的是"内容已经
/// 在那儿了",动画只负责让它到位。
struct Entrance: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    static let duration: Double = 0.5
    static let stagger: Double = 0.06
    static let curve = Animation.timingCurve(0.16, 1, 0.3, 1, duration: duration)

    /// 卡片从第几号开始。0 是侧栏,1 是顶栏。
    static let cardBase = 2
    /// 卡片内部的图表比卡片本身晚这么久开始。
    ///
    /// 不等卡片完全到位(500ms)才开始:那样两段动画首尾相接,总时长翻倍,看着
    /// 拖沓。取 180ms——卡片已经基本落位、模糊也散了,图表在它上面接着长出来,
    /// 读起来是一件事而不是两件。
    static let innerLead: Double = 0.18

    static func delay(_ index: Int) -> Double { Double(max(0, index)) * stagger }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.98)
            .offset(y: shown ? 0 : 12)
            .blur(radius: shown ? 0 : 4)
            .onAppear {
                guard !shown else { return }
                // 「减弱动态效果」打开时直接到位。这不是可选的润色——大面积的
                // 位移和模糊对前庭功能敏感的人会真的引起不适。
                guard !reduceMotion else { shown = true; return }
                withAnimation(Self.curve.delay(Self.delay(index))) { shown = true }
            }
    }
}

/// 弹窗入场:遮罩淡入,内容同步放大到位。
///
/// 比页面入场快一倍(250ms):弹窗是用户**刚刚点出来的**,他已经在等它了。页面
/// 入场可以从容,弹窗慢一点就是迟钝。
///
/// 缩放从 0.96 起,不是从 0.9:后者会让弹窗看着像"弹出来",而这里要的是它本来
/// 就在那儿、只是刚对上焦。
struct ModalEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    static let duration: Double = 0.25
    static let curve = Animation.timingCurve(0.16, 1, 0.3, 1, duration: duration)

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.96)
            .onAppear {
                guard !shown else { return }
                guard !reduceMotion else { shown = true; return }
                withAnimation(Self.curve) { shown = true }
            }
    }
}

/// 本模块入场的延迟。发给卡片内部,让图表的自绘动画排在卡片到位**之后**。
///
/// 少了这个协调,一张排在第 6 位的卡片要 360ms 之后才进场,而它里面的折线从第
/// 0 毫秒就开始画了——等卡片可见时线已经画完,那张卡看起来是唯一没有动画的。
private struct EntranceDelayKey: EnvironmentKey { static let defaultValue: Double = 0 }

extension EnvironmentValues {
    var entranceDelay: Double {
        get { self[EntranceDelayKey.self] }
        set { self[EntranceDelayKey.self] = newValue }
    }
}

extension View {
    func entrance(_ index: Int) -> some View {
        modifier(Entrance(index: index))
            .environment(\.entranceDelay, Entrance.delay(index))
    }

    func modalEntrance() -> some View {
        modifier(ModalEntrance())
    }
}
