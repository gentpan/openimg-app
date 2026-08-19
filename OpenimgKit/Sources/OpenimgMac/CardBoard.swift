import SwiftUI
import OpenimgKit

/// 卡片当前占了几格。卡片内部靠它决定要不要分栏、列表放几条。
private struct CardSpanKey: EnvironmentKey { static let defaultValue = 1 }
/// 本格的实际宽度。要在格子内部再按比例切分时得有真数,靠 maxWidth 分不出
/// 1:2 —— 那只会让两边等分。
private struct CardWidthKey: EnvironmentKey { static let defaultValue: Double = 0 }

extension EnvironmentValues {
    var cardSpan: Int {
        get { self[CardSpanKey.self] }
        set { self[CardSpanKey.self] = newValue }
    }
    var cardWidth: Double {
        get { self[CardWidthKey.self] }
        set { self[CardWidthKey.self] = newValue }
    }
}

/// 按可用宽度排卡片的容器,概览页与设置页共用。
///
/// 几何算在 `BoardFit` / `CardGrid` 里(Kit,`KitCheck` 覆盖得到),这里只负责
/// 把算出来的行画出来。
struct CardBoard<ID: Hashable & Sendable, Content: View>: View {
    let cards: [BoardCard<ID>]
    @ViewBuilder let content: (ID) -> Content

    /// 页面左右各 22。放在这里而不是外面:求解要拿去掉留白之后的净宽,
    /// 两处各写一遍迟早对不上。
    private static var inset: Double { 22 }

    var body: some View {
        // GeometryReader 必须在 ScrollView 外面:竖向滚动视图给内容提议的是
        // 无限高度,从里面量会拿到 infinity。同 GalleryView 的理由。
        GeometryReader { geo in
            let fit = BoardFit.solve(width: max(1, geo.size.width - Self.inset * 2))
            ScrollView {
                VStack(spacing: BoardFit.gap) {
                    ForEach(Array(CardGrid.rows(cards, columns: fit.columns).enumerated()),
                            id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: BoardFit.gap) {
                            ForEach(row) { cell in
                                let w = width(of: cell.span, in: fit)
                                content(cell.id)
                                    .environment(\.cardSpan, cell.span)
                                    .environment(\.cardWidth, w)
                                    .frame(width: w)
                            }
                        }
                        // 行内靠左起排。行尾余量已经在装箱时并给最后一张卡了,
                        // 所以这里永远是满的;写 .leading 是为了万一将来放宽了
                        // 那条规则,卡片也不会突然开始居中漂移。
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(width: fit.contentWidth)
                // 列宽封顶之后剩下的宽度不拉伸卡片,而是让整块内容居中。
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Self.inset)
                .padding(.bottom, 22)
            }
        }
    }

    /// 跨 n 格的宽度 = n 个列宽 + 中间 n−1 个间隙。
    private func width(of span: Int, in fit: BoardFit) -> Double {
        fit.columnWidth * Double(span) + BoardFit.gap * Double(span - 1)
    }
}
