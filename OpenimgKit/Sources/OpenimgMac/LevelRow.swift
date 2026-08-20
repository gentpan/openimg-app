import SwiftUI
import OpenimgKit

/// 个人资料卡下半部分:等级与升级进度。
///
/// **只是荣誉,不发任何奖励。** 权益全部由用户组决定——等级要是也能改配额,同一个
/// 数字就有了两个来源,而"我明明升级了空间怎么没变"这种 bug 几乎无法排查。
///
/// 这张卡原来只有头像、名字、邮箱,下面空掉大半(卡片被同行拉高,而内容只占顶上
/// 三分之一)。等级正好填进去,而且填的是有意义的东西,不是撑高度的空行。
struct LevelRow: View {
    @ObservedObject var model: AppModel

    private var level: MemberLevel? {
        guard let q = model.quota else { return nil }
        // 两个字段都是可选的(旧服务器不发)。全都取不到时整块不显示 —— 显示一个
        // 恒为「新来的」的等级,比不显示更误导。
        let days = q.checkin?.totalDays
        guard days != nil || q.memberSince != nil else { return nil }
        return MemberLevel.of(checkinDays: days ?? 0, memberSince: q.memberSince)
    }

    var body: some View {
        if let lv = level {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(L.s.settings.levelBadge(lv.level))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.brand))
                        .foregroundStyle(Color.brandInk)
                    Text(lv.title).font(.callout.weight(.medium))
                    Spacer(minLength: 8)
                    if lv.isMax {
                        Text(L.s.settings.levelMax)
                            .font(.caption2).foregroundStyle(.tertiary)
                    } else {
                        Text(L.s.settings.levelToNext(lv.pointsToNext))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.07))
                        Capsule()
                            .fill(Color.brand)
                            .frame(width: max(2, geo.size.width * lv.progress))
                    }
                }
                .frame(height: 4)

                // 说清这个数怎么来的。不说的话,一个不涨的进度条只会让人猜。
                Text(L.s.settings.levelHow(model.quota?.checkin?.totalDays ?? 0))
                    .font(.caption2).foregroundStyle(.quaternary)
            }
        }
    }
}
