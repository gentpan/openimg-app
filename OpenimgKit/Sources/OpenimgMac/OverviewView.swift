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
    // 三张图各自的入场进度。分开而不是共用一个:它们的入场方式不同(扫开 /
    // 生长 / 画出来),共用一个进度就没法给折线单独一条更长的曲线。
    @State private var revealDonut: Double = 0
    @State private var revealFormats: Double = 0
    @State private var revealTrend: Double = 0

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
        case quota, ai, checkin, storage, composition, format, activity
    }

    private var cards: [BoardCard<CardID>] {
        [
            // 顺序按**高度**配对,不按语义分组。
            //
            // 语义分组("我还剩多少"三张排一行)排出来的是:空间 230 / AI 140 /
            // 签到 265 一行,存储位置 95 / 构成 355 / 格式 175 一行——同行卡片
            // 会被拉到最高那张的高度,于是存储位置下面空出 260pt、AI 下面空出
            // 125pt。分组是说给作者听的,空白是给用户看的。
            //
            // 现在把三张高的排一行、三张矮的排一行,行高从 277+359 降到
            // 355+230,最大空隙从 260pt 降到 85pt。两列档下配对随之变化
            // (空间+构成 / 签到+AI / 格式+位置),同样是高配高、矮配矮。
            BoardCard(.quota),
            BoardCard(.composition),
            BoardCard(.checkin),
            BoardCard(.ai),
            BoardCard(.format),
            BoardCard(.storage),
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
            case .quota:       QuotaCard(model: model)
            case .ai:          AIQuotaCard(model: model)
            case .checkin:     checkinCard
            case .storage:     StorageCard(model: model)
            case .composition: compositionCard
            case .format:      formatCard
            case .activity:    activityRow
            }
        }
        .task { await model.loadStats() }
    }

    /// 空间流水与上传趋势并排,宽度 1:2。
    ///
    /// 流水是一列窄条目,宽了只是把「说明………数字」拉成横跨半屏的虚线;趋势是
    /// 14 根柱子,窄了柱间距发虚。同一行里一个要窄一个要宽,正好互补。
    ///
    /// 做成独立的 View(SplitRow)而不是这里直接算宽度:环境值是 CardBoard 加在
    /// 「闭包返回的那个视图」上的,只有它的子视图读得到。
    private var activityRow: some View {
        SplitRow { ledgerCard } trailing: { trendCard }
    }

    // MARK: - 上传趋势

    /// 最近 30 天的上传折线。
    ///
    /// 数据来自 `GET /api/stats/uploads`。原来是拿图库当前那一页按天聚合的——
    /// 那份数据受排序与搜索影响,把排序切成「占用最大」再看趋势,画出来的图不是
    /// 不全,是彻底错的;而 30 天的窗口一页几十张图根本覆盖不到。
    ///
    /// 折线而不是柱状:30 根柱子在一张卡的宽度里每根不到 10pt,细得看不出高低差;
    /// 折线读的是走势,点密反而更顺。底下补一层填充,让"零"和"没有数据"在视觉上
    /// 分得开。
    @ViewBuilder private var trendCard: some View {
        let points = model.uploadTrend?.points ?? []
        if let why = model.uploadTrendError {
            // 说出来,别消失。
            PanelCard(L.s.overview.trendTitle, "chart.xyaxis.line") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.s.overview.trendFailed).font(.caption).foregroundStyle(.secondary)
                    Text(why).font(.caption2).foregroundStyle(.tertiary).lineLimit(3)
                }
            }
        } else if model.uploadTrend != nil && !points.contains(where: { $0.count > 0 }) {
            // 取到了,但这 30 天确实一张都没传。这与"取不到"是两回事,要分开说。
            PanelCard(L.s.overview.trendTitle, "chart.xyaxis.line") {
                Text(L.s.overview.trendEmpty).font(.caption).foregroundStyle(.tertiary)
            }
        } else if points.contains(where: { $0.count > 0 }) {
            PanelCard(L.s.overview.trendTitle, "chart.xyaxis.line", fills: true) {
                Chart(points) { p in
                    if let day = p.day {
                        AreaMark(
                            x: .value(L.s.overview.trendDay, day, unit: .day),
                            y: .value(L.s.overview.trendCount, p.count)
                        )
                        .foregroundStyle(
                            .linearGradient(colors: [Color.brand.opacity(0.28), .clear],
                                            startPoint: .top, endPoint: .bottom)
                        )
                        LineMark(
                            x: .value(L.s.overview.trendDay, day, unit: .day),
                            y: .value(L.s.overview.trendCount, p.count)
                        )
                        .foregroundStyle(Color.brand)
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineJoin: .round))
                        .interpolationMethod(.monotone)
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                // 只遮绘图区,不遮坐标轴——把刻度也一起擦掉的话,画到一半的
                // 图看着不像在画,像是没加载完。
                .chartPlotStyle { plot in
                    plot.mask(alignment: .leading) {
                        GeometryReader { g in
                            Rectangle().frame(width: g.size.width * revealTrend)
                        }
                    }
                }
                .reveal($revealTrend, duration: Reveal.draw)
                .frame(minHeight: 110, maxHeight: .infinity)
                Text(L.s.overview.trendNote(points.reduce(0) { $0 + $1.count }))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Quota

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
                    .frame(height: 124)
                    // 遮罩加在 overlay **之前**:加在后面的话中间那行字会跟着
                    // 被扇形切掉一半,扫到一半时看着像渲染坏了。
                    .mask { Wedge(end: revealDonut) }
                    .reveal($revealDonut)
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
                // 横轴的定义域钉死在最大那根上,不让它跟着数据缩放。
                //
                // 少了这一句,"把每根乘上进度"是没有效果的:所有值同比例缩小,
                // 自动推出来的定义域也同比例缩小,画出来和原图一模一样。
                let widest = max(1, s.byFormat.map(\.bytes).max() ?? 1)
                Chart(Array(s.byFormat.enumerated()), id: \.element.id) { i, f in
                    BarMark(
                        x: .value(L.s.overview.chartSizeLabel,
                                  Double(f.bytes) * revealFormats),
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
                .chartXScale(domain: 0...Double(widest), range: .plotDimension(endPadding: 66))
                .reveal($revealFormats)
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
        LedgerCard(model: model)
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

/// 一格之内横切成两块,**按列切,不按比例切**。
///
/// 按比例是错的,而且错得不明显:这一格宽 `3C + 32`(三列加两个间隙),按
/// 1/3 切出来是 `C + 5.33` —— 比一个标准列宽了 5.3pt,于是左边这张卡的右
/// 边缘比它上下的卡都多探出去一点,整列看着是歪的。
///
/// 反过来从列宽推:先由格宽解出 C,再按整数列数拼回去,边缘就和栅格严丝合缝。
private struct SplitRow<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    @Environment(\.cardWidth) private var cardWidth
    @Environment(\.cardSpan) private var cardSpan

    var body: some View {
        // 左边恒占 1 列,右边吃掉其余。三列时正好是 1:2;两列时退成 1:1 ——
        // 1:2 在两格里拆不成整数列,而对齐比那个比例重要:歪 5pt 是看得见的,
        // 窄一点不是。
        let span = max(2, cardSpan)
        HStack(alignment: .top, spacing: BoardFit.gap) {
            leading.frame(width: BoardFit.subWidth(of: cardWidth, span: span, columns: 1))
            trailing.frame(width: BoardFit.subWidth(of: cardWidth, span: span, columns: span - 1))
        }
    }
}

/// 空间流水,一页 5 条,翻页在标题右侧。
///
/// 分页是纯本地的:`model.transactions` 一次拉 50 条,翻页只是换个切片,
/// 不发请求也没有等待——所以两颗按钮点下去是即时的。
///
/// 一页 5 条而不是一屏铺满:原来一次画 12 条、单栏 514pt,它一个人就是概览
/// 页两列失衡的全部来源。翻页比截断好在什么都没丢。
private struct LedgerCard: View {
    @ObservedObject var model: AppModel
    @State private var page = 0

    private static let perPage = 5

    private var pageCount: Int {
        max(1, Int(ceil(Double(model.transactions.count) / Double(Self.perPage))))
    }

    /// 夹一道:流水会被刷新替换掉(签到、删图都会让它变短),停在第 4 页时
    /// 数据缩到 8 条,不夹就会显示一页空白。
    private var clamped: Int { min(page, pageCount - 1) }

    private var slice: ArraySlice<QuotaTransaction> {
        let start = clamped * Self.perPage
        guard start < model.transactions.count else { return [] }
        return model.transactions[start..<min(start + Self.perPage, model.transactions.count)]
    }

    var body: some View {
        PanelCard(L.s.overview.ledgerTitle, "list.bullet.rectangle") {
            if model.transactions.count > Self.perPage {
                HStack(spacing: 6) {
                    pager("chevron.left", enabled: clamped > 0) { page = clamped - 1 }
                    Text("\(clamped + 1)/\(pageCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    pager("chevron.right", enabled: clamped < pageCount - 1) { page = clamped + 1 }
                }
            }
        } content: {
            if model.transactions.isEmpty {
                LedgerPlaceholder(model: model)
            } else {
                VStack(spacing: 0) {
                    ForEach(slice) { t in
                        row(t)
                        if t.id != slice.last?.id { Divider() }
                    }
                }
                // 末页不足 5 条时不让卡片缩一截:高度跟着内容变,翻到最后一页
                // 整张卡会往上跳,而旁边那张图表没动——看着像页面自己抖了一下。
                .frame(minHeight: Double(Self.perPage) * 27, alignment: .top)
            }
        }
    }

    /// 当天只印时分,更早才印日期。
    ///
    /// 流水多半看的是"刚才那几笔",一水儿的「8月20日」既占地方又没区分度;
    /// 而隔了天的条目,知道是哪天比知道几点重要。
    private func stamp(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) {
            return d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L.locale))
        }
        // 同年不印年份。「2026年8月19日」里那四位对辨认哪一天毫无帮助,却占掉
        // 半个标题的宽度,而流水几乎都是今年的。
        let sameYear = cal.component(.year, from: d) == cal.component(.year, from: Date())
        let style = Date.FormatStyle(date: sameYear ? .omitted : .abbreviated, time: .omitted)
            .locale(L.locale)
        guard sameYear else { return d.formatted(style) }
        return d.formatted(style.month(.abbreviated).day())
    }

    private func pager(_ icon: String, enabled: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? AnyShapeStyle(Color.brand) : AnyShapeStyle(.quaternary))
        .disabled(!enabled)
    }

    private func row(_ t: QuotaTransaction) -> some View {
        // 不用 QuotaTransaction.label:它写死在共享的 Models.swift 里,
        // 只有中文一份。
        let label = L.s.overview.txLabel(t.type)
        return HStack(spacing: 8) {
            Image(systemName: t.isGrant ? "plus.circle.fill" : "minus.circle.fill")
                .foregroundStyle(t.isGrant ? Color.brand : Color.secondary)
                .font(.caption)
            Text(label).font(.caption).fixedSize()
            Text(detail(t, label))
                .font(.caption2).foregroundStyle(.tertiary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            Text(stamp(t.createdAt))
                .font(.caption2.monospacedDigit()).foregroundStyle(.quaternary)
                .fixedSize()
            // 取绝对值再自己加符号。ByteCountFormatter 对负数会自带一个连字
            // 符,前面再拼一个减号就是「−-104 KB」——两个不同的字符撞在一起,
            // 看着像排版坏了。
            Text("\(t.isGrant ? "+" : "−")\(model.bytes(abs(t.bytes)))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(t.isGrant ? Color.brand : .secondary)
                .fixedSize()
        }
        .padding(.vertical, 6)
    }

    /// 去掉 reason 开头那段和类型标签重复的字。
    ///
    /// 服务端写进来的 reason 多半以类型开头(「上传 Yetex.jpg」),而左边已经
    /// 印了「上传」——并排就是同一个词说两遍,而这一行的宽度本来就不宽裕。
    ///
    /// 只砍开头,不砍别处:「删除图片 上传的封面.png」里第二个词是文件名的一
    /// 部分,不能一起吃掉。
    private func detail(_ t: QuotaTransaction, _ label: String) -> String {
        var r = t.reason
        if r.hasPrefix(label) {
            r = String(r.dropFirst(label.count))
        }
        return r.trimmingCharacters(in: .whitespaces)
    }
}

private struct LedgerPlaceholder: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack {
            Spacer()
            if model.statsLoading { ProgressView().controlSize(.small) }
            else { Text(L.s.overview.emptyState).font(.caption).foregroundStyle(.tertiary) }
            Spacer()
        }
        .frame(height: 90)
    }
}
