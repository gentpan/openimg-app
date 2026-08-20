import Foundation

/// 账号等级。
///
/// **只是荣誉,不发任何奖励。** 权益全部由用户组决定(配额、每日张数、AI 次数),
/// 那才是唯一说了算的地方。等级要是也能改配额,同一个数字就有了两个来源,而两个
/// 来源迟早会对不上——那种 bug 表现为"我明明升级了空间怎么没变",几乎无法排查。
///
/// 经验值只由两样东西构成,共同点是**都刷不了**:
///
///   - 累计签到天数:一天最多加一,而且签到本身就是每天回来一次的理由;
///   - 注册时长:自己会走,谁也加速不了。
///
/// 刻意不算上传张数——传了再删要么能刷经验、要么会让清理图库掉级,两种都不好;
/// 也不算存储用量,那等于鼓励占空间,和自己的成本直接冲突。
public struct MemberLevel: Sendable, Equatable {
    public let level: Int
    public let title: String
    /// 当前这一级的门槛与下一级的门槛(单位:分)。
    public let floor: Int
    /// nil 表示已经封顶。
    public let ceiling: Int?
    public let points: Int

    /// 距离下一级还差多少分。封顶时为 0。
    public var pointsToNext: Int { ceiling.map { max(0, $0 - points) } ?? 0 }

    /// 当前这一级里的进度,0…1。封顶时为 1。
    public var progress: Double {
        guard let ceiling, ceiling > floor else { return 1 }
        return min(1, max(0, Double(points - floor) / Double(ceiling - floor)))
    }

    public var isMax: Bool { ceiling == nil }

    /// 一天算一分,注册满一个月算一分。
    ///
    /// 两者同权是有意的:只算签到的话,一个每天来的新用户会瞬间超过用了两年但
    /// 偶尔才来的人;只算时长的话,注册完就再没打开过的人照样升级。加起来才同时
    /// 表达"来得久"和"来得勤"。
    ///
    /// 注册时长按 30 天一档折算,不按天——按天的话它会淹没签到那一半,一年就是
    /// 365 分,而签到一年最多也是 365 分却要每天动手。
    public static func points(checkinDays: Int, memberSince: Date?, now: Date = Date()) -> Int {
        let days = max(0, checkinDays)
        var months = 0
        if let memberSince, now > memberSince {
            months = Int(now.timeIntervalSince(memberSince) / (30 * 86400))
        }
        return days + max(0, months)
    }

    /// 各级门槛。
    ///
    /// 间隔越往后越大,但不是指数级——指数会让后面几级永远够不着,而这套东西的
    /// 意义是"看得见下一步"。最高一级 730 分大约是每天签到两年,或者用三年多且
    /// 隔三差五签一次。
    static let ladder: [(floor: Int, title: String)] = [
        (0, "新来的"),
        (7, "常客"),
        (30, "熟客"),
        (90, "老手"),
        (180, "元老"),
        (365, "守夜人"),
        (730, "长住民"),
    ]

    public static func of(checkinDays: Int, memberSince: Date?, now: Date = Date()) -> MemberLevel {
        let p = points(checkinDays: checkinDays, memberSince: memberSince, now: now)
        var idx = 0
        for (i, step) in ladder.enumerated() where p >= step.floor { idx = i }
        let ceiling = idx + 1 < ladder.count ? ladder[idx + 1].floor : nil
        return MemberLevel(level: idx + 1, title: ladder[idx].title,
                           floor: ladder[idx].floor, ceiling: ceiling, points: p)
    }

    public static var levelCount: Int { ladder.count }
}
