import SwiftUI
import OpenimgKit

/// 生成页与修图页共用的零件。
///
/// 这两页是同一件事的两副面孔:一个额度池、一张历史表、一条轮询。凡是两边
/// 长得一样的东西都收在这里,免得同一个概念在两个文件里慢慢长成两个样子。

/// 「我还能用几次」那张卡。
///
/// 生成页和修图页各摆一份,内容却是同一份:两件事花的是同一个额度池,同一
/// 次调用就是同一次扣减。所以它不属于任何一页,单独放在这里——各写一份的话,
/// 两页会在同一件事上慢慢说出两种话。
///
/// 位置一律在输入框正下方而不是折进设置里:这是一件**次数有限**的事,用户
/// 按下按钮之前就该知道自己还剩几次,以及用完之后是等明天还是去签到。
struct AIQuotaCard: View {
    @ObservedObject var model: AppModel
    /// 卡片脚注:出来的图去哪了。两页的答案不同(一张新图 / 一张改过的图),
    /// 所以这句由调用方给。
    let footnote: String

    var body: some View {
        if let s = model.aiStatus {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 22) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.s.generate.remainingLabel)
                            .font(.caption2).foregroundStyle(.tertiary)
                        Text(L.s.generate.times(s.remaining))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(s.remaining > 0 ? AnyShapeStyle(Color.brandDisplay)
                                                             : AnyShapeStyle(Color.orange))
                    }
                    stat(L.s.generate.todayLabel, L.s.generate.todayValue(s.usedToday, s.dailyLimit))
                    stat(L.s.generate.monthlyLabel, L.s.generate.monthlyValue(s.credits, s.monthly))
                    Spacer(minLength: 12)
                    exhaustedNote(s)
                }
                if s.dailyLimit > 0 {
                    ProgressBar(
                        tint: s.remaining > 0 ? .brand : .orange,
                        value: Double(s.usedToday) / Double(s.dailyLimit)
                    )
                    .frame(height: 4)
                }
                Text(footnote)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(14)
            .panelSurface(12)
        }
    }

    /// 用完了要说清是哪一种用完。
    ///
    /// 本月余额先判:余额为零时明天也一样用不了,说「明天再来」是句会让人白
    /// 等一天的话。今日上限则相反,睡一觉就有。
    @ViewBuilder
    private func exhaustedNote(_ s: AIStatus) -> some View {
        if s.remaining <= 0 {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption).foregroundStyle(.orange)
                if s.monthlyExhausted {
                    Text(L.s.generate.monthlyExhausted)
                        .font(.caption).foregroundStyle(.secondary)
                    Button(L.s.generate.goCheckin) { model.section = .overview }
                        .buttonStyle(LinkButton())
                        .font(.caption)
                } else if s.dailyExhausted {
                    // dailyExhausted 而不是 else:每日上限为 0 的部署里
                    // remaining 也是 0,那句「今天的 0 次已经用完」是胡话。
                    Text(L.s.generate.dailyExhausted(s.dailyLimit))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func stat(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.callout.weight(.medium).monospacedDigit())
        }
    }
}

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
