import SwiftUI
import Charts
import OpenimgKit

/// Swift Charts rather than a web view around the site's Chart.js.
///
/// Wrapping the existing charts in a WKWebView would have been less work and
/// would have shipped something that scrolls at a different speed to the rest
/// of the window, ignores the system accent, does not follow appearance
/// changes, and cannot be selected or right-clicked like anything else in the
/// app. The point of a native client is that it behaves like one.
struct OverviewView: View {
    @ObservedObject var model: AppModel

    /// 卡片的一条序列。行怎么切由 CardGrid 按列数算,这里只声明顺序和跨度。
    ///
    /// 原来是手分的两列(左三右四)加 980pt 上限,没有断点。后果是两列高度对不
    /// 上——左列到屏幕中段就结束,右列一直拉到底,左下空出整整 523pt;而窗口拉
    /// 宽之后左右各留白 236pt(16 吋满屏)没人用。
    ///
    /// 分组:先「我还剩多少」(空间、签到),再「东西长什么样」(构成、格式),
    /// 最后「最近发生了什么」(最近上传、趋势、流水)。
    private enum CardID: String, Hashable, Sendable {
        case quota, checkin, composition, format, recent, activity
    }

    private var cards: [BoardCard<CardID>] {
        [
            BoardCard(.quota),
            BoardCard(.checkin),
            BoardCard(.composition),
            BoardCard(.format),
            // 唯一真吃宽度的卡:三列档跨两格,缩略图从 4 列变 6 列。
            BoardCard(.recent, spans: [3: 2]),
            // 流水与趋势并排,占满整行,内部按 1:2 切。
            //
            // 合成一格而不是两张各自参与装箱:1:2 在整数格里排不出来
            // (两列档只能 1:1),而这个比例是要在任何宽度下都成立的。
            BoardCard(.activity, spans: [2: 2, 3: 3]),
        ]
    }

    var body: some View {
        CardBoard(cards: cards) { id in
            switch id {
            case .quota:       quotaCard
            case .checkin:     checkinCard
            case .composition: compositionCard
            case .format:      formatCard
            case .recent:      recentCard
            case .activity:    activityRow
            }
        }
        .task { await model.loadStats() }
    }

    // MARK: - 最近上传

    /// 最近上传的缩略图带。
    ///
    /// 概览原来全是数字和饼图,看不到一张自己的图。这条带子用图库已经加载
    /// 的那一页数据,不多发一次请求;点一张直接跳到图库。
    @ViewBuilder private var recentCard: some View {
        if !model.images.isEmpty {
            PanelCard(L.s.overview.recentTitle, "photo.stack") {
                RecentStrip(model: model)
            }
        }
    }

    /// 空间流水与上传趋势并排,宽度 1:2。
    ///
    /// 流水是一列窄条目,宽了只是把「说明……数字」拉成横跨半屏的虚线;趋势是
    /// 14 根柱子,窄了柱间距发虚。同一行里一个要窄一个要宽,正好互补。
    ///
    /// 做成独立的 View 而不是 OverviewView 上的一个属性:环境值是 CardBoard
    /// 加在「闭包返回的那个视图」上的,只有它的子视图读得到。写在 OverviewView
    /// 自己身上会一直读到默认值 0。
    private var activityRow: some View {
        SplitRow(ratio: 1.0 / 3.0) { ledgerCard } trailing: { trendCard }
    }

    // MARK: - 上传趋势

    /// 最近 14 天的上传条形图。
    ///
    /// 由已加载的图片按天聚合,而不是另加一个统计接口——用户端本来就没有
    /// 按日序列的端点,而"最近这些图是什么时候传的"用现成数据就能答。
    /// 只画有数据的那段:一整排零柱说明的是没数据,不是趋势。
    @ViewBuilder private var trendCard: some View {
        let days = recentDays
        if days.contains(where: { $0.count > 0 }) {
            PanelCard(L.s.overview.trendTitle, "chart.bar") {
                Chart(days, id: \.day) { d in
                    BarMark(
                        x: .value(L.s.overview.trendDay, d.day, unit: .day),
                        y: .value(L.s.overview.trendCount, d.count)
                    )
                    .foregroundStyle(Color.brand.gradient)
                    .cornerRadius(2)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 110)
                Text(L.s.overview.trendNote(days.reduce(0) { $0 + $1.count }))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    /// 把当前这页图片按自然日归并到最近 14 天。
    private var recentDays: [(day: Date, count: Int)] {
        var cal = Calendar.current
        cal.locale = L.locale
        let today = cal.startOfDay(for: Date())
        guard let from = cal.date(byAdding: .day, value: -13, to: today) else { return [] }
        var buckets: [Date: Int] = [:]
        for img in model.images {
            let d = cal.startOfDay(for: img.createdAt)
            guard d >= from else { continue }
            buckets[d, default: 0] += 1
        }
        return (0..<14).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: from) else { return nil }
            return (d, buckets[d] ?? 0)
        }
    }

    // MARK: - Quota

    private var quotaCard: some View {
        PanelCard(L.s.overview.quotaTitle, "internaldrive") {
            if let q = model.quota {
                let used = q.quotaBytes > 0 ? Double(q.usedBytes) / Double(q.quotaBytes) : 0
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(model.bytes(q.availableBytes))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.brand)
                        Text(L.s.overview.quotaAvailable).foregroundStyle(.secondary)
                        Spacer()
                        // Moved here from the settings page, which carried a
                        // second copy of this whole card. Settings is for
                        // things you can change; nothing in it was.
                        Text(L.s.common.imageCount(q.imageCount))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    // A plain bar, not a gauge: this is one number against one
                    // ceiling, and a dial makes the reader do trigonometry to
                    // learn what a rectangle says immediately.
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule()
                                .fill(Color.brand)
                                .frame(width: max(3, geo.size.width * min(1, used)))
                        }
                    }
                    .frame(height: 8)
                    HStack {
                        Text(L.s.overview.quotaUsed(model.bytes(q.usedBytes)))
                        Spacer()
                        Text(L.s.overview.quotaTotal(model.bytes(q.quotaBytes)))
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                placeholder
            }
        }
    }

    // MARK: - Storage composition

    private var compositionCard: some View {
        PanelCard(L.s.overview.compositionTitle, "chart.pie") {
            if let s = model.summary {
                // Distinct hues, not four opacities of one. Shades of the same
                // colour force the reader back to the legend for every slice;
                // and with 86 / 13 / 2 the two small ones were near-identical
                // slivers of purple that nothing distinguished.
                let parts = [
                    (L.s.overview.partPrimary, s.sizePrimary, Color.brand),
                    (L.s.overview.partVariants, s.sizeVariants, Color(red: 0.20, green: 0.74, blue: 0.80)),
                    (L.s.overview.partThumbs, s.sizeThumbs, Color(red: 0.98, green: 0.72, blue: 0.25)),
                    (L.s.overview.partUnclassified, s.sizeUnclassified, Color.white.opacity(0.28)),
                ].filter { $0.1 > 0 }

                VStack(alignment: .leading, spacing: 12) {
                    Chart(parts, id: \.0) { part in
                        SectorMark(
                            angle: .value(L.s.overview.chartSizeLabel, part.1),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.5
                        )
                        .cornerRadius(3)
                        .foregroundStyle(part.2)
                    }
                    .chartLegend(.hidden)
                    .frame(height: 150)
                    .overlay {
                        VStack(spacing: 0) {
                            Text(model.bytes(s.sizeStored))
                                .font(.callout.weight(.semibold))
                            Text(L.s.common.imageCount(s.images))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    ForEach(parts, id: \.0) { part in
                        HStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 2).fill(part.2).frame(width: 9, height: 9)
                            Text(part.0)
                            Spacer()
                            Text(model.bytes(part.1)).foregroundStyle(.secondary)
                            Text(percent(part.1, of: s.sizeStored))
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                                .frame(width: 46, alignment: .trailing)
                        }
                        .font(.caption)
                    }

                    if s.sizeOrig > 0 {
                        Divider()
                        let delta = Double(s.sizeStored) / Double(s.sizeOrig) - 1
                        HStack {
                            Image(systemName: delta <= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                .foregroundStyle(delta <= 0 ? .green : .orange)
                            Text(delta <= 0
                                 ? L.s.overview.savedVsOriginal(model.bytes(s.sizeOrig - s.sizeStored))
                                 : L.s.overview.largerThanOriginal(model.bytes(s.sizeStored - s.sizeOrig)))
                            Spacer()
                            Text(String(format: "%+.0f%%", delta * 100)).monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            } else {
                placeholder
            }
        }
    }

    // MARK: - Formats

    private var formatCard: some View {
        PanelCard(L.s.overview.formatsTitle, "doc.on.doc") {
            if let s = model.summary, !s.byFormat.isEmpty {
                Chart(Array(s.byFormat.enumerated()), id: \.element.id) { i, f in
                    BarMark(
                        x: .value(L.s.overview.chartSizeLabel, f.bytes),
                        y: .value(L.s.overview.chartFormatLabel, f.ext.uppercased())
                    )
                    .foregroundStyle(Self.formatPalette[i % Self.formatPalette.count])
                    .cornerRadius(4)
                    .annotation(position: .trailing) {
                        Text(model.bytes(f.bytes))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                // Room on the right for the annotation, which would otherwise
                // be clipped by the plot area on the widest bar.
                .chartXScale(range: .plotDimension(endPadding: 66))
                .frame(height: CGFloat(s.byFormat.count) * 30 + 12)
            } else {
                placeholder
            }
        }
    }

    // MARK: - Check-in

    private var checkinCard: some View {
        PanelCard(L.s.overview.checkinTitle, "flame.fill") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.orange)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.orange.opacity(0.15)))
                        .shadow(color: .orange.opacity(0.35), radius: 8)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(L.s.overview.streakLabel).font(.caption).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(model.streak)")
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                            Text(L.s.overview.streakUnit(model.streak))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(model.checkedInToday ? L.s.overview.checkedInToday : L.s.overview.checkinAction) {
                        Task { await model.checkin() }
                    }
                    .buttonStyle(model.checkedInToday ? AnyButtonStyle(QuietButton())
                                                      : AnyButtonStyle(BrandButton()))
                    .disabled(model.checkedInToday || model.busy)
                }

                Divider().overlay(Color.white.opacity(0.08))

                WeekStrip(days: model.thisWeek)
                MilestoneBar(
                    title: L.s.overview.monthProgressTitle,
                    current: model.monthProgress.done,
                    total: model.monthProgress.total,
                    reward: model.quota?.checkin?.monthBonus ?? 0,
                    bytes: model.bytes
                )
            }
        }
    }

    // MARK: - Ledger

    private var ledgerCard: some View {
        PanelCard(L.s.overview.ledgerTitle, "list.bullet.rectangle") {
            if model.transactions.isEmpty {
                placeholder
            } else {
                VStack(spacing: 0) {
                    ForEach(model.transactions.prefix(12)) { t in
                        HStack(spacing: 10) {
                            Image(systemName: t.isGrant ? "plus.circle.fill" : "minus.circle.fill")
                                .foregroundStyle(t.isGrant ? Color.brand : Color.secondary)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 1) {
                                // 不用 QuotaTransaction.label:它写死在共享的
                                // Models.swift 里,只有中文一份。
                                Text(L.s.overview.txLabel(t.type)).font(.caption)
                                Text(t.reason)
                                    .font(.caption2).foregroundStyle(.tertiary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text("\(t.isGrant ? "+" : "−")\(model.bytes(t.bytes))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(t.isGrant ? Color.brand : .secondary)
                        }
                        .padding(.vertical, 5)
                        if t.id != model.transactions.prefix(12).last?.id { Divider() }
                    }
                }
            }
        }
    }

    // MARK: - Bits

    private var placeholder: some View {
        HStack {
            Spacer()
            if model.statsLoading { ProgressView().controlSize(.small) }
            else { Text(L.s.overview.emptyState).font(.caption).foregroundStyle(.tertiary) }
            Spacer()
        }
        .frame(height: 90)
    }

    /// Cycled across formats so the bars are told apart by colour as well as
    /// by length — the shortest two are otherwise a pair of stubs.
    static let formatPalette: [Color] = [
        // Accent first, not brand: a chart answers "how much", and violet in a
        // chart reads as "this series is the brand one" rather than as a
        // colour. The fourth used to be another green and sat too close to the
        // first — a slate replaces it, since it only appears once there are
        // four or more formats and a low-saturation neutral cannot clash.
        .brand,
        Color(red: 0.22, green: 0.74, blue: 0.97),
        Color(red: 0.98, green: 0.75, blue: 0.14),
        Color(red: 0.58, green: 0.64, blue: 0.72),
        Color(red: 0.96, green: 0.45, blue: 0.71),
    ]

    private func percent(_ part: Int64, of whole: Int64) -> String {
        guard whole > 0 else { return "—" }
        return String(format: "%.0f%%", Double(part) / Double(whole) * 100)
    }
}

// MARK: - Card chrome

/// 一格之内按比例横切成两块。
///
/// 用本格的实际宽度算,不用 `.frame(maxWidth:)` —— 后者只会把空间均分,
/// 分不出 1:2。
private struct SplitRow<Leading: View, Trailing: View>: View {
    let ratio: Double
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    @Environment(\.cardWidth) private var cardWidth

    var body: some View {
        let inner = max(1, cardWidth - BoardFit.gap)
        HStack(alignment: .top, spacing: BoardFit.gap) {
            leading.frame(width: inner * ratio)
            trailing.frame(width: inner * (1 - ratio))
        }
    }
}

/// 最近上传的缩略图。
///
/// 原来是 4 列 × 54pt 定高,在 474pt 的列里算出来是 106×54 —— 2:1 的扁条,
/// 一张竖构图的照片到这里只剩中间一道,认不出是哪张。改成按 4:3 定比例:
/// 高度随列宽走,横竖构图都还看得出是什么。
///
/// 悬浮才浮出文件名。常驻的话八张图配八条字,这张卡就从"看一眼自己的图"
/// 变成了一张文件列表 —— 那是图库该干的事。
private struct RecentStrip: View {
    @ObservedObject var model: AppModel
    @Environment(\.cardSpan) private var cardSpan

    /// 跨两格时列数从 4 变 6,行数不变。跨度变宽只加列不加高,卡片才不会
    /// 在那一行里突然比邻居高出一截。
    private var columns: Int { cardSpan >= 2 ? 6 : 4 }

    var body: some View {
        let shots = Array(model.images.prefix(columns * 2))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns),
                  spacing: 6) {
            ForEach(shots) { img in
                Tile(img: img, model: model)
            }
        }
    }

    private struct Tile: View {
        let img: RemoteImage
        @ObservedObject var model: AppModel
        @State private var hovering = false

        var body: some View {
            Button {
                model.section = .gallery
                model.detail = img
            } label: {
                Thumbnail(url: img.thumbURL, client: try? model.client())
                    // .fit 而不是 .fill:Thumbnail 是 Color.clear 打底的柔性
                    // 视图,.fill 会让它在两个方向上都不小于父级的提议,而格子
                    // 高度是无界的——那样会撑破。.fit 正好是"拿给定的宽,按比例
                    // 推出高"。真正的填充裁切发生在 Thumbnail 内部。
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .overlay(alignment: .bottom) { caption }
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(hovering ? Color.brand : .white.opacity(0.07),
                                          lineWidth: hovering ? 1.5 : 1)
                    }
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .help(img.origName)
        }

        /// 名字压在一层从下往上收的黑罩里,不是压在图上。浅色的图上直接放白字
        /// 会读不出来,而这张卡里什么颜色的图都可能出现。
        @ViewBuilder private var caption: some View {
            if hovering {
                Text(img.origName)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.bottom, 4)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(colors: [.clear, .black.opacity(0.72)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .transition(.opacity)
            }
        }
    }
}
