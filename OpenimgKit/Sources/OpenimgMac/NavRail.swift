import SwiftUI

/// 侧栏左侧那根会滑动的发光条。
///
/// 一段发光的竖线停在当前页那一行旁边,换页时滑过去。四层叠出来:
///
///   1. 底衬:一条上下淡出的深色竖线,让发光段有所依附——没有它,那道光是
///      飘在黑底上的,看着像渲染错误而不是一根轨道。
///   2. 发光段:同样上下淡出的品牌色,高度正好一行。
///   3. 光晕:一块模糊的品牌色,让中段"亮起来"。单靠渐变的光是平的。
///   4. 横向柔光:向右淡出,把当前那一行整条衬起来。
///
/// 位置是 index × 行高 算出来的,所以 SidebarRow 必须定高、行间不能留缝
/// (见 Metrics.navRow)。
struct NavRail<Content: View>: View {
    let count: Int
    /// 当前行的序号。nil 表示当前页不在侧栏里(比如设置页)。
    let index: Int?
    @ViewBuilder var content: Content

    /// 当前页不在侧栏里时停在原处,而不是跳回第一行或者消失。
    ///
    /// 用户点开设置再回来,发光条应该还在他离开时的位置上;缩回顶部会让人以
    /// 为自己被踢回了第一页。
    @State private var resting = 0

    private var at: Int { index ?? resting }

    var body: some View {
        content
            .padding(.leading, 10)
            .background(alignment: .topLeading) { rail }
            // 过冲再回弹,对应原样式那条 cubic-bezier(0.37, 1.95, 0.66, 0.56)
            // ——它的控制点 y 是 1.95,本来就是要冲过头再收回来的。
            .animation(.spring(response: 0.5, dampingFraction: 0.58), value: at)
            .onChange(of: index) { _, new in if let new { resting = new } }
            .onAppear { if let index { resting = index } }
    }

    private var rail: some View {
        ZStack(alignment: .topLeading) {
            // 1. 底衬
            LinearGradient(
                colors: [.clear, Color(white: 0.11), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 1)

            glider
                .frame(height: Metrics.navRow)
                .offset(y: CGFloat(at) * Metrics.navRow)
        }
        .frame(height: CGFloat(count) * Metrics.navRow, alignment: .top)
        .allowsHitTesting(false)
    }

    private var glider: some View {
        ZStack(alignment: .leading) {
            // 4. 横向柔光。画在最底下,免得它盖住那道光本身。
            LinearGradient(
                colors: [Color.brand.opacity(0.11 * Color.brandGlow), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 150)

            // 3. 光晕
            Rectangle()
                .fill(Color.brand)
                .frame(width: 3, height: Metrics.navRow * 0.6)
                .blur(radius: 10)
                .opacity(Color.brandGlow)

            // 2. 发光段
            LinearGradient(
                colors: [.clear, Color.brand, .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
