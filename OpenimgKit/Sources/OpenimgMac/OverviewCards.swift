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
                }
            }
        }
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

                    line(L.s.overview.aiToday, "\(r.usedToday) / \(r.dailyLimit)")
                    line(L.s.overview.aiMonthly, "\(r.monthlyLeft) / \(r.monthlyTotal)")

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
