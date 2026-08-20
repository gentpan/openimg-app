import SwiftUI
import OpenimgKit

// MARK: - 存储位置

/// 你的图分别存在哪儿。
///
/// 数据是两个来源合出来的(见 StorageOverview.slots):存储位置列表有名字、类型
/// 和连通状态,存储统计多覆盖两种孤儿——桶删了但字节还在、以及历史上没有归属的
/// 图。合并规则里有三条写错了不会报错,所以那部分在 Kit 里、由自检钉住。
struct StorageCard: View {
    @ObservedObject var model: AppModel

    private var slots: [StorageSlot] {
        StorageOverview.slots(profiles: model.storageProfiles,
                              byProfile: model.summary?.byProfile ?? [])
    }

    var body: some View {
        PanelCard(L.s.overview.storageTitle, "externaldrive") {
            let rows = slots
            if rows.isEmpty {
                // 空态分两种:还在加载,和真的没有。混成一句"暂无数据"会让人在
                // 加载的那两秒里以为出错了。
                HStack {
                    Spacer()
                    if model.statsLoading { ProgressView().controlSize(.small) }
                    else { Text(L.s.overview.emptyState).font(.caption).foregroundStyle(.tertiary) }
                    Spacer()
                }
                .frame(height: 72)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { s in
                        row(s)
                        if s.id != rows.last?.id { Divider().overlay(Color.white.opacity(0.06)) }
                    }
                    // 只有平台池时给一条出路。
                    //
                    // 这张卡在那种情况下只有一行,下面空着一大片——而空着的地
                    // 方正好是"你还可以把图存到自己那儿"该说的地方。不是为了
                    // 填空:平台配额用完之后唯一的出路就是绑自己的桶,而这张卡
                    // 恰恰是用户发现配额吃紧时会看的地方。
                    if !rows.contains(where: { $0.kind != .platform && $0.kind != .removed }) {
                        Divider().overlay(Color.white.opacity(0.06))
                        bindPrompt
                    }
                }
            }
        }
    }

    private var bindPrompt: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 15))
                .foregroundStyle(Color.brand)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.brand.opacity(0.12)))
            VStack(alignment: .leading, spacing: 4) {
                Text(L.s.overview.storageBindTitle).font(.callout)
                Text(L.s.overview.storageBindBody)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L.s.overview.storageBindAction) { model.section = .settings }
                    .buttonStyle(QuietButton())
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
    }

    private func row(_ s: StorageSlot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text(s.name).font(.callout).lineLimit(1)
                if let badge = s.kind.badge {
                    Text(badge)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(.white.opacity(0.08)))
                        .foregroundStyle(.secondary)
                }
                if s.isDefault {
                    Text(L.s.overview.storageDefault)
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.brand.opacity(0.18)))
                        .foregroundStyle(Color.brand)
                }
                if s.mirrors > 0 {
                    Text(L.s.overview.storageMirrors(s.mirrors))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 6)
                Text(model.bytes(s.bytes))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text(L.s.overview.storageImages(s.images))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            }

            // 占比条。用品牌色的透明度分层,不引第二种色相——这一栏里橙色只表示
            // 出问题了,那是语义不是装饰。
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.06))
                    Capsule()
                        .fill(barColor(s))
                        .frame(width: max(2, geo.size.width * s.share))
                }
            }
            .frame(height: 4)

            if let note = healthNote(s) {
                Text(note).font(.caption2).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .padding(.vertical, 7)
    }

    private func barColor(_ s: StorageSlot) -> Color {
        switch s.health {
        case .ok: s.isDefault ? Color.brand : Color.brand.opacity(0.55)
        case .fallenBack, .failing: .orange
        case .removed: Color.white.opacity(0.22)
        }
    }

    private func healthNote(_ s: StorageSlot) -> String? {
        switch s.health {
        // 默认位置失效是"图还在传,只是没进你的桶",与"这个桶连不上"要说不同的话。
        case .fallenBack: L.s.overview.storageFellBack
        case .failing: L.s.overview.storageFailing
        case .removed: L.s.overview.storageRemoved
        case .ok: nil
        }
    }
}

// MARK: - AI 余量

/// 还能生成几次。
///
/// 三本互不相通的账:今日次数、本月额度、pic.bi 余额。摆在一起最容易犯的错是
/// 让人以为总数是它们的和,所以主数字只有一个,另外两行是解释它从哪来。
struct AIQuotaCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let s = model.aiStatus, s.enabled {
            let r = AIQuotaReadout(s)
            PanelCard(L.s.overview.aiTitle, "sparkles") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(r.headline)")
                            .font(.system(size: 30, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(r.blocked == nil ? Color.brand : .secondary)
                        Text(L.s.overview.aiTimes).font(.callout).foregroundStyle(.secondary)
                        if r.fromPicbi {
                            Text(L.s.overview.aiFromPicbi)
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }

                    // 光是"0 / 5"读不出还剩多少余地。填色一律代表**已用**,
                    // 与空间卡那张方块图同一套读法——同一页里两种相反的填色
                    // 含义,比不填色更糟。
                    line(L.s.overview.aiToday, "\(r.usedToday) / \(r.dailyLimit)")
                    dots(used: r.usedToday, total: r.dailyLimit)
                    line(L.s.overview.aiMonthlyUsed,
                         "\(r.monthlyTotal - r.monthlyLeft) / \(r.monthlyTotal)")
                    bar(used: r.monthlyTotal - r.monthlyLeft, total: r.monthlyTotal)

                    switch r.picbi {
                    case .none:
                        EmptyView()
                    case .known(let n):
                        line("pic.bi", "\(n)")
                    case .unknown:
                        // 查不到就写「—」,不写 0。写 0 会让人以为钱花光了,
                        // 而实际只是对端抖了一下——两种情况要做的事正好相反。
                        line("pic.bi", "—", hint: L.s.overview.aiPicbiUnknown)
                    }

                    if let b = r.blocked {
                        Text(b == .monthly ? L.s.overview.aiMonthlyOut : L.s.overview.aiDailyOut)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// 一天几次就画几个点。次数多到点不下时退回细条——十几个点排成一行,
    /// 数它们比读"3 / 20"还慢。
    @ViewBuilder
    private func dots(used: Int, total: Int) -> some View {
        if total > 0 && total <= 12 {
            HStack(spacing: 5) {
                ForEach(0..<total, id: \.self) { i in
                    Circle()
                        .fill(i < used ? AnyShapeStyle(Color.brand) : AnyShapeStyle(.quaternary))
                        .frame(width: 9, height: 9)
                }
                Spacer(minLength: 0)
            }
        } else {
            bar(used: used, total: total)
        }
    }

    private func bar(used: Int, total: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Color.brand)
                    .frame(width: total > 0
                           ? max(used > 0 ? 3 : 0,
                                 geo.size.width * min(1, Double(used) / Double(total)))
                           : 0)
            }
        }
        .frame(height: 6)
    }

    private func line(_ k: String, _ v: String, hint: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).font(.caption).foregroundStyle(.secondary)
            if let hint {
                Text(hint).font(.caption2).foregroundStyle(.quaternary)
            }
            Spacer()
            Text(v).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 空间

/// 空间卡片。绑了自己的桶就分页显示。
///
/// 方块图取代了原来那根横条。横条只读得出比例,读不出量级——同样是半满,10 GB
/// 的一半和 100 MB 的一半在条上长得一模一样。方块图把"每格多少"印在下面,比例
/// 和量级就能同时读出来。填几格、每格多大在 `UsageGrid` 里算,那里面有三处一错
/// 就会骗人的地方(见那份注释),全由自检钉住。
///
/// 平台配额和自有桶是**两种不同的东西**,所以两个页签读法也不同:平台有上限,
/// 格子是比例;自有桶没有上限,格子是量,每格固定大小、按量点亮。硬给自有桶凑
/// 一个分母出来的话,那张图会永远是七成满,变成纯装饰。
struct QuotaCard: View {
    @ObservedObject var model: AppModel
    @State private var tabID: String?
    /// 本格的实际宽度,由 CardBoard 发下来。格子要是方的就得知道这个数——
    /// 读得到是因为 QuotaCard 是装箱闭包**返回**的那个视图,环境值正好落在
    /// 它身上;写在 OverviewView 自己的 body 里读同一个键会永远拿到默认值。
    @Environment(\.cardWidth) private var cardWidth

    /// 一个页签背后的一组数。
    private struct Tab: Hashable, Identifiable {
        let id: String
        let label: String
        /// 大字要显示的数:平台是剩余,自有桶是已存。
        let headline: Int64
        let headlineSuffix: String
        let bytes: Int64
        /// nil 表示没有上限。
        let capacity: Int64?
        let images: Int
    }

    private var tabs: [Tab] {
        var out: [Tab] = []
        if let q = model.quota {
            out.append(Tab(id: "platform", label: L.s.overview.quotaTabPlatform,
                           headline: q.availableBytes,
                           headlineSuffix: L.s.overview.quotaAvailable,
                           bytes: q.usedBytes, capacity: q.quotaBytes,
                           images: q.imageCount))
        }
        // 只列自有桶。平台那行已经在上面了,而"已移除"的位置没有可用容量可言,
        // 它属于 存储位置 那张卡要讲的事。
        let own = StorageOverview.slots(profiles: model.storageProfiles,
                                        byProfile: model.summary?.byProfile ?? [])
            .filter { $0.kind != .platform && $0.kind != .removed }
        for s in own {
            out.append(Tab(id: s.id, label: s.kind.badge ?? s.name,
                           headline: s.bytes,
                           headlineSuffix: L.s.overview.quotaStoredLabel,
                           bytes: s.bytes, capacity: nil, images: s.images))
        }
        return out
    }

    /// 选中的那个。选中的桶被删掉之后要退回第一个,否则卡片会空着。
    private var current: Tab? { tabs.first { $0.id == tabID } ?? tabs.first }

    var body: some View {
        PanelCard(L.s.overview.quotaTitle, "internaldrive") {
            if tabs.count > 1, let cur = current {
                PillRow(items: tabs, label: { $0.label },
                        selection: Binding(get: { cur }, set: { tabID = $0.id }))
            }
        } content: {
            if let t = current {
                let grid = UsageGrid.of(bytes: t.bytes, capacity: t.capacity)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(model.bytes(t.headline))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(grid.overflowed ? Color.orange : Color.brand)
                        Text(t.headlineSuffix).foregroundStyle(.secondary)
                        Spacer()
                        Text(L.s.common.imageCount(t.images))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    cells(grid)
                    footer(t, grid)
                }
            } else {
                placeholder
            }
        }
    }

    private func cells(_ g: UsageGrid) -> some View {
        // 边长由卡片实宽反算,不用 GeometryReader:后者要先知道宽才能定高,
        // 而高又决定容器给多少宽,绕成一个环。算术在 Kit 里,自检钉得住。
        let inner = cardWidth - 32          // 减掉 PanelCard 的左右内边距
        let side = inner > 40
            ? UsageGrid.cellSide(contentWidth: inner, columns: g.columns)
            : 0                             // 还没量到宽度时退回弹性布局
        return VStack(spacing: UsageGrid.gap) {
            ForEach(0..<g.rows, id: \.self) { r in
                HStack(spacing: UsageGrid.gap) {
                    ForEach(0..<g.columns, id: \.self) { c in
                        let cell = RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(r * g.columns + c < g.filled
                                  ? AnyShapeStyle(g.overflowed ? Color.orange : Color.brand)
                                  : AnyShapeStyle(.quaternary))
                        if side > 0 {
                            cell.frame(width: side, height: side)
                        } else {
                            cell.frame(maxWidth: .infinity).frame(height: 12)
                        }
                    }
                    if side > 0 { Spacer(minLength: 0) }
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: g.filled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(g.hasCeiling
                            ? L.s.overview.quotaUsed(model.bytes(g.unit * Int64(g.filled)))
                            : L.s.overview.quotaGridUnit(model.bytes(g.unit)))
    }

    private func footer(_ t: Tab, _ g: UsageGrid) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                if let cap = t.capacity {
                    Text(L.s.overview.quotaUsed(model.bytes(t.bytes)))
                    if g.overflowed {
                        Text(L.s.overview.quotaOverflow).foregroundStyle(.orange)
                    }
                    Spacer()
                    Text(L.s.overview.quotaTotal(model.bytes(cap)))
                } else {
                    Text(L.s.overview.quotaNoLimit)
                    Spacer()
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            // 不印单位的方块图什么也没说——读者无从知道一格是 10 MB 还是 10 GB。
            Text(L.s.overview.quotaGridUnit(model.bytes(g.unit)))
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var placeholder: some View {
        HStack {
            Spacer()
            if model.statsLoading { ProgressView().controlSize(.small) }
            else { Text(L.s.overview.emptyState).font(.caption).foregroundStyle(.tertiary) }
            Spacer()
        }
        .frame(height: 72)
    }
}
