import SwiftUI

/// 卡片标题右侧的 ⓘ,点开是一段说明。
///
/// 用来收那些「说清楚很有用、但不需要一直摆在眼前」的文字。水印卡原来把三段
/// 解释常驻在界面上,占掉了整张卡将近一半的高度——而那些话绝大多数时候是背景
/// 知识,不是当下要做的决定。
///
/// 用点击而不是悬浮:悬浮出现的浮层没法选中复制,而这类说明里常有具体数字和
/// 名词,人会想复制走。点击还顺带让键盘可达。
struct InfoTip: View {
    let text: String
    var title: String? = nil

    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title ?? L.s.common.details)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                if let title {
                    Text(title).font(.subheadline.weight(.medium))
                }
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(16)
            // 定宽:不给宽度的话 popover 会按最长那一行摊开,一段中文长句能拉到
            // 半个屏幕宽。
            .frame(width: 380, alignment: .leading)
        }
    }
}
