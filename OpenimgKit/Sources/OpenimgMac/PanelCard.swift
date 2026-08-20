import SwiftUI

/// 卡片右上角那枚水印。
///
/// 只是一枚放大的、压得很淡的图形,不承载信息——同一件事在别处必须还有一个说
/// 得清的表达(资料卡上是那枚文字徽章)。水印读的是"一眼认出这是哪一类",而不
/// 是"读出这是哪一类"。
struct PanelWatermark {
    let symbol: String
    let tint: Color
}

/// 概览页与设置页共用的卡壳。
///
/// 原来是两个:`OverviewView` 里的 `Card` 和 `SettingsView` 里的 `SettingsCard`,
/// 结构逐字相同。合并的直接理由是下面那行 `maxHeight` ——它要是分散在两处,
/// 以后改一处忘一处;而这一行放错位置,整套等高布局就落空。
struct PanelCard<Content: View, Accessory: View>: View {
    let title: String
    let icon: String
    /// 内容要不要吃掉这一行多出来的高度。
    ///
    /// 默认不吃:多数卡是几行字,撑开只会让内部松散。图表是例外——它有一根
    /// 基线,不撑满就会停在半空,下面吊一大片空白。
    var fills = false
    /// 右上角那枚水印。见 PanelWatermark。
    var watermark: PanelWatermark?
    /// 标题行右端的东西——翻页、切换之类**属于这张卡**的控件。
    ///
    /// 放在标题行而不是内容底部:它管的是整张卡显示什么,不是内容的一部分。
    /// 摆在下面会读成"列表的最后一项"。
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    init(_ title: String, _ icon: String, fills: Bool = false,
         watermark: PanelWatermark? = nil,
         @ViewBuilder accessory: () -> Accessory = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.fills = fills
        self.watermark = watermark
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                accessory
            }
            content
        }
        .frame(maxHeight: fills ? .infinity : nil, alignment: .top)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 撑满这一行的高度,内容顶对齐。
        //
        // 必须写在 panelSurface() 之前。写在卡外面只会放大布局盒子,圆角面板
        // 仍停在内容的自然高度上——结果是面板底下吊着一段透明空白,和原来那种
        // 一列比另一列短一大截是同一个毛病,只是换了个位置。
        //
        // 同一行里高度不齐本身不是问题:卡片是一块面板,不是一块瓷砖。面板被拉
        // 到行高、内容顶对齐,它仍然是一块完整的面板——空白进到卡里就不叫空白
        // 了。原来那 523pt 是卡与卡之外的空白,那才是断裂。
        .frame(maxHeight: .infinity, alignment: .top)
        // 水印画在内容**底下**,并且裁到面板自己的形状上。
        //
        // 裁剪是必须的:它有意向右上角外溢一截,不裁就会盖到圆角外面,看着不
        // 是水印,是一个没放好的图标。而 panelSurface 只画背景和描边、不裁,
        // 所以这一层得自己裁。
        .background { watermarkLayer }
        .panelSurface()
    }

    @ViewBuilder
    private var watermarkLayer: some View {
        if let w = watermark {
            Image(systemName: w.symbol)
                .font(.system(size: 88, weight: .semibold))
                .foregroundStyle(w.tint.opacity(0.12))
                .offset(x: 22, y: -12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous))
                // 纯装饰:既不该挡住头像和昵称的点击,也不该被念出来。
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
