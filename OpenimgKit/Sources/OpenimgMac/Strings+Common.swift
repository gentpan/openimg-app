import Foundation

/// 全应用共享的词汇:动作、状态、计数。
///
/// 这些词每个界面都要用,分散到各分区就会出现「取消/撤销/退出」三种译法。
/// 放在一处,别的分区只放自己独有的文案。
struct CommonStrings: Sendable {
    // MARK: 动作
    let ok: String
    let cancel: String
    let save: String
    let details: String
    let delete: String
    let remove: String
    let close: String
    let reset: String
    let change: String
    let replace: String
    let resume: String
    let refresh: String
    let copy: String
    let copyLink: String
    let upload: String
    let open: String

    // MARK: 状态
    let loading: String
    let copied: String
    let deleted: String
    let done: String
    let failed: String
    let unlimited: String

    // MARK: 计数
    let imageCount: @Sendable (Int) -> String

    // MARK: 签到卡片
    /// 里程碑给的奖励:天数 + 已格式化的容量。
    let milestoneReward: @Sendable (Int, String) -> String
    /// 「几天 / 共几天」。
    let dayProgress: @Sendable (Int, Int) -> String
}

extension CommonStrings {
    static let zh = CommonStrings(
        ok: "确定",
        cancel: "取消",
        save: "保存",
        details: "说明",
        delete: "删除",
        remove: "移除",
        close: "关闭",
        reset: "重置",
        change: "修改",
        replace: "更换",
        resume: "继续",
        refresh: "刷新",
        copy: "复制",
        copyLink: "复制链接",
        upload: "上传",
        open: "打开",

        loading: "加载中…",
        copied: "已复制",
        deleted: "已删除",
        done: "完成",
        failed: "失败",
        unlimited: "不限",

        imageCount: { n in "\(n) 张" },

        milestoneReward: { days, size in "满 \(days) 天 +\(size)" },
        dayProgress: { current, total in "\(current) / \(total) 天" })

    static let en = CommonStrings(
        ok: "OK",
        cancel: "Cancel",
        save: "Save",
        details: "Details",
        delete: "Delete",
        remove: "Remove",
        close: "Close",
        reset: "Reset",
        change: "Change",
        replace: "Replace",
        resume: "Resume",
        refresh: "Refresh",
        copy: "Copy",
        copyLink: "Copy Link",
        upload: "Upload",
        open: "Open",

        loading: "Loading…",
        copied: "Copied",
        deleted: "Deleted",
        done: "Done",
        failed: "Failed",
        unlimited: "Unlimited",

        imageCount: { n in n == 1 ? "1 image" : "\(n) images" },

        milestoneReward: { days, size in "+\(size) at \(days) days" },
        dayProgress: { current, total in "\(current) / \(total) days" })
}
