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
        case quota, checkin, composition, format, recent, trend, ledger
    }

    private var cards: [BoardCard<CardID>] {
        [
            BoardCard(.quota),
            BoardCard(.checkin),
            BoardCard(.composition),
            BoardCard(.format),
            // 唯一真吃宽度的卡:三列档跨两格,缩略图从 4 列变 6 列。
            BoardCard(.recent, spans: [3: 2]),
            BoardCard(.trend),
            // 12 条 × 37pt 单栏 = 514pt,它一个人就是原来那个失衡的全部来源。
            BoardCard(.ledger, spans: [2: 2, 3: 3]),
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
            case .trend:       trendCard
            case .ledger:      ledgerCard
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
                let shots = Array(model.images.prefix(8))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                          spacing: 6) {
                    ForEach(shots) { img in
                        Button {
                            model.section = .gallery
                            model.detail = img
                        } label: {
                            Thumbnail(url: img.thumbURL, client: try? model.client())
                                .frame(height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(img.origName)
                    }
                }
            }
        }
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


