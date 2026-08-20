import Foundation

/// 概览页文案:配额卡、存储构成、格式分布、签到、空间流水。
///
/// 图表里的 `.value(...)` 标签也收在这里——图例虽然隐藏,但它是 VoiceOver
/// 念出来的那一份,漏掉就等于把中文留在了朗读里。
struct OverviewStrings: Sendable {
    let recentTitle: String
    let trendTitle: String
    let trendDay: String
    let trendCount: String
    let trendNote: @Sendable (Int) -> String
    let trendFailed: String
    let trendEmpty: String
    // 配额
    let quotaTitle: String
    let quotaAvailable: String
    let quotaUsed: @Sendable (String) -> String
    let quotaTotal: @Sendable (String) -> String

    // 存储构成
    let compositionTitle: String
    let partPrimary: String
    let partVariants: String
    let partThumbs: String
    let partUnclassified: String
    let savedVsOriginal: @Sendable (String) -> String
    let largerThanOriginal: @Sendable (String) -> String

    // 格式分布
    let formatsTitle: String
    let chartSizeLabel: String
    let chartFormatLabel: String

    // 签到
    let checkinTitle: String
    let streakLabel: String
    let streakUnit: @Sendable (Int) -> String
    let checkinAction: String
    let checkedInToday: String
    let monthProgressTitle: String

    // 空间流水
    let ledgerTitle: String
    /// 流水条目的类型名。`type` 是服务端给的原始串,同 GalleryStrings 里的
    /// `sortLabel`——共享模型层不该带界面文案,映射落在这边,认不出就原样显示。
    let txLabel: @Sendable (String) -> String

    let emptyState: String
    let storageTitle: String
    let storageDefault: String
    let storageImages: @Sendable (Int) -> String
    let storageMirrors: @Sendable (Int) -> String
    let storageFellBack: String
    let storageFailing: String
    let storageRemoved: String
    let aiTitle: String
    let aiTimes: String
    let aiToday: String
    let aiMonthly: String
    let aiFromPicbi: String
    let aiPicbiUnknown: String
    let aiMonthlyOut: String
    let aiDailyOut: String
}

extension OverviewStrings {
    static let zh = OverviewStrings(
        recentTitle: "最近上传",
        trendTitle: "上传趋势",
        trendDay: "日期",
        trendCount: "张数",
        trendNote: { n in "最近 30 天共 \(n) 张" },
        trendFailed: "取不到上传趋势",
        trendEmpty: "最近 30 天还没有上传",
        quotaTitle: "空间",
        quotaAvailable: "可用",
        quotaUsed: { size in "已用 \(size)" },
        quotaTotal: { size in "总量 \(size)" },

        compositionTitle: "存储构成",
        partPrimary: "主图",
        partVariants: "衍生图",
        partThumbs: "缩略图",
        partUnclassified: "未分类",
        savedVsOriginal: { size in "比原始文件省了 \(size)" },
        largerThanOriginal: { size in "比原始文件多用 \(size)" },

        formatsTitle: "格式分布",
        chartSizeLabel: "占用",
        chartFormatLabel: "格式",

        checkinTitle: "签到",
        streakLabel: "连续签到",
        streakUnit: { _ in "天" },
        checkinAction: "签到",
        checkedInToday: "今天已签到",
        monthProgressTitle: "本月进度",

        ledgerTitle: "空间流水",
        txLabel: { type in
            switch type {
            case "signup_grant": "注册赠送"
            case "checkin": "每日签到"
            case "referral": "邀请奖励"
            case "admin_grant": "管理员调整"
            case "upload": "上传"
            case "delete_refund": "删除退还"
            default: type
            }
        },

        emptyState: "暂无数据",
        storageTitle: "存储位置",
        storageDefault: "默认",
        storageImages: { n in "\(n) 张" },
        storageMirrors: { n in "\(n) 个镜像" },
        storageFellBack: "这个位置连不上，新图已经暂时改存平台池",
        storageFailing: "上次检查没连上",
        storageRemoved: "位置已删除，这些图的字节还记在它名下",
        aiTitle: "AI 余量",
        aiTimes: "次",
        aiToday: "今天已用",
        aiMonthly: "本月剩余",
        aiFromPicbi: "来自 pic.bi",
        aiPicbiUnknown: "这次没查到",
        aiMonthlyOut: "本月额度用完了，签到可以再领。",
        aiDailyOut: "今天的次数用完了，明天再来。")

    static let en = OverviewStrings(
        recentTitle: "Recent uploads",
        trendTitle: "Upload activity",
        trendDay: "Day",
        trendCount: "Images",
        trendNote: { n in "\(n) uploads in the last 30 days" },
        trendFailed: "Could not load upload activity",
        trendEmpty: "No uploads in the last 30 days",
        quotaTitle: "Storage",
        quotaAvailable: "available",
        quotaUsed: { size in "\(size) used" },
        quotaTotal: { size in "\(size) total" },

        compositionTitle: "Storage Breakdown",
        partPrimary: "Primary",
        partVariants: "Variants",
        partThumbs: "Thumbnails",
        partUnclassified: "Unclassified",
        savedVsOriginal: { size in "\(size) smaller than the originals" },
        largerThanOriginal: { size in "\(size) larger than the originals" },

        formatsTitle: "Formats",
        chartSizeLabel: "Size",
        chartFormatLabel: "Format",

        checkinTitle: "Check-in",
        streakLabel: "Current streak",
        streakUnit: { n in n == 1 ? "day" : "days" },
        checkinAction: "Check In",
        checkedInToday: "Checked In Today",
        monthProgressTitle: "This month",

        ledgerTitle: "Storage Activity",
        txLabel: { type in
            switch type {
            case "signup_grant": "Signup Bonus"
            case "checkin": "Daily Check-in"
            case "referral": "Referral Bonus"
            case "admin_grant": "Admin Adjustment"
            case "upload": "Upload"
            case "delete_refund": "Space Returned"
            default: type
            }
        },

        emptyState: "No data yet",
        storageTitle: "Where your images live",
        storageDefault: "Default",
        storageImages: { n in "\(n) images" },
        storageMirrors: { n in "\(n) mirror(s)" },
        storageFellBack: "This bucket is unreachable — new uploads are going to the platform pool for now",
        storageFailing: "Last check could not reach it",
        storageRemoved: "Location deleted; these bytes are still counted against it",
        aiTitle: "AI allowance",
        aiTimes: "left",
        aiToday: "Used today",
        aiMonthly: "Left this month",
        aiFromPicbi: "from pic.bi",
        aiPicbiUnknown: "not available",
        aiMonthlyOut: "This month's allowance is used up — check in to earn more.",
        aiDailyOut: "Today's runs are used up. Try again tomorrow.")
}
