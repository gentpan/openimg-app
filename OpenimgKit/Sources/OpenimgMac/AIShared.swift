import SwiftUI
import OpenimgKit

/// 生成页与修图页共用的零件。
///
/// 这两页是同一件事的两副面孔:一个额度池、一张历史表、一条轮询。凡是两边
/// 长得一样的东西都收在这里,免得同一个概念在两个文件里慢慢长成两个样子。

/// 尺寸与清晰度的取值由服务器给,是字符串而不是本地枚举(不能写死),包一层
/// 只为满足 PillRow 的 `Hashable & Identifiable`。修图页还借空串表示「跟随
/// 原图」——那一档在服务器的列表里没有对应项,正因为它的意思是"什么都不指定"。
struct AIOption: Hashable, Identifiable {
    let value: String
    init(_ value: String) { self.value = value }
    var id: String { value }
}

// MARK: - 历史行的零件

/// 状态徽章。两页的历史行共用——同一套状态,同一套配色。
struct AIStatusChip: View {
    let status: AIGenStatus

    var body: some View {
        Text(L.s.generate.statusLabel(status))
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(Capsule().fill(tint.opacity(0.16)))
    }

    private var tint: Color {
        switch status {
        case .completed: .success
        case .failed: .orange
        case .charging, .pending, .running: .brand
        }
    }
}

/// 「3 分钟前」。formatter 每次现造:界面语言是可切的静态量,缓存一份会把
/// 切换前的 locale 一直带下去。两页加起来也不过几十行,不值得为它加缓存。
func aiAgo(_ date: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.locale = L.locale
    f.unitsStyle = .short
    return f.localizedString(for: date, relativeTo: Date())
}

/// 额度的紧凑版:一行文字,塞进输入区底排那块空地。
///
/// 原来是一整张卡片,为三个数字占掉一行,而输入区底排(清晰度与提交按钮之间)
/// 本来就空着一大片。同一份信息挪过去,版面少一行,而且它离「生成」按钮更近
/// ——「还剩几次」正是按下去之前最后要确认的那件事。
///
/// 只在还有额度时用这一版。用完了要说清是哪一种用完、该怎么办,那时它值得
/// 单独一行,见 AIQuotaNotice。
struct AIQuotaInline: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let s = model.aiStatus, s.remaining > 0 || s.picbiRemaining > 0 {
            HStack(spacing: 10) {
                Text(L.s.generate.times(s.remaining))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(s.remaining > 0 ? AnyShapeStyle(Color.brandDisplay)
                                                     : AnyShapeStyle(.secondary))
                // 本站额度见底之后花的是 pic.bi 的钱,得让人看见还剩多少
                // ——不然界面上只剩一个「0 次」,而按钮却是亮的。
                if s.picbiRemaining > 0 {
                    pair(L.s.generate.picbiLabel, "\(s.picbiRemaining)")
                }
                pair(L.s.generate.todayLabel, L.s.generate.todayValue(s.usedToday, s.dailyLimit))
                pair(L.s.generate.monthlyLabel, L.s.generate.monthlyValue(s.credits, s.monthly))
            }
            .lineLimit(1)
            .fixedSize()
        }
    }

    private func pair(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.quaternary)
            Text(value).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

/// 额度用完时那一条。
///
/// 有额度时完全不占版面——数字已经由紧凑版说清了。用完了才出现,并且说清是
/// 哪一种用完:本月余额为零时明天也一样用不了,那时说「明天再来」是句会让人
/// 白等一天的话。
struct AIQuotaNotice: View {
    @ObservedObject var model: AppModel

    var body: some View {
        // pic.bi 还有余额时不算用完——那时按钮是亮的,再挂一条「去签到」就是
        // 一句明确说错的话。
        if let s = model.aiStatus, s.remaining <= 0, s.picbiRemaining <= 0 {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
                Text(s.monthlyExhausted ? L.s.generate.monthlyExhausted
                                        : L.s.generate.dailyExhausted(s.dailyLimit))
                    .font(.caption).foregroundStyle(.secondary)
                if s.monthlyExhausted {
                    Button(L.s.generate.goCheckin) { model.section = .overview }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(0.10))
            )
        }
    }
}
