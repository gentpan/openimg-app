import SwiftUI

/// 概览页与设置页共用的卡壳。
///
/// 原来是两个:`OverviewView` 里的 `Card` 和 `SettingsView` 里的 `SettingsCard`,
/// 结构逐字相同。合并的直接理由是下面那行 `maxHeight` ——它要是分散在两处,
/// 以后改一处忘一处;而这一行放错位置,整套等高布局就落空。
struct PanelCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    init(_ title: String, _ icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            content
        }
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
        .panelSurface()
    }
}
