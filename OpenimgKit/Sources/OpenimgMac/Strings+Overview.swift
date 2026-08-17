import Foundation

/// 概览页文案:配额卡、存储构成、格式分布、签到、空间流水。
///
/// 图表里的 `.value(...)` 标签也收在这里——图例虽然隐藏,但它是 VoiceOver
/// 念出来的那一份,漏掉就等于把中文留在了朗读里。
struct OverviewStrings: Sendable {
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
}

extension OverviewStrings {
    static let zh = OverviewStrings(
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

        emptyState: "暂无数据")

    static let en = OverviewStrings(
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

        emptyState: "No data yet")
}
