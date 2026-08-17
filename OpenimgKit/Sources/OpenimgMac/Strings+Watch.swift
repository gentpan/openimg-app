import Foundation

/// 目录监控分区:状态行与提示。
///
/// 状态行由若干片段拼成(`清单 N 条 · 本次 +N · 收编 N`),每个片段单独成
/// 键、不含分隔符——分隔符由调用方 join,中英文才不用各背一份标点。
struct WatchStrings: Sendable {
    /// 一轮扫描开始
    let scanning: String
    /// 单文件被组规则拒绝时的提示,参数是拒绝原因
    let skippedSome: @Sendable (String) -> String
    /// 正在上传某个文件,参数是文件名
    let uploadingFile: @Sendable (String) -> String
    /// 一轮结束的浮层提示,参数是本轮新上传张数
    let uploadedAnnounce: @Sendable (Int) -> String
    /// 状态行片段:清单总条数
    let manifestCount: @Sendable (Int) -> String
    /// 状态行片段:本轮新上传
    let addedThisRun: @Sendable (Int) -> String
    /// 状态行片段:同内容已传过、被收编的条数
    let adoptedCount: @Sendable (Int) -> String
    /// 状态行片段:本轮跳过的条数
    let skippedCount: @Sendable (Int) -> String
    /// 撞上限流,参数是等待秒数
    let rateLimitedRetry: @Sendable (Int) -> String
}

extension WatchStrings {
    static let zh = WatchStrings(
        scanning: "扫描中…",
        skippedSome: { reason in "部分文件被跳过：\(reason)" },
        uploadingFile: { name in "上传 \(name)…" },
        uploadedAnnounce: { n in "目录监控：新上传 \(n) 张" },
        manifestCount: { n in "清单 \(n) 条" },
        addedThisRun: { n in "本次 +\(n)" },
        adoptedCount: { n in "收编 \(n)" },
        skippedCount: { n in "跳过 \(n)" },
        rateLimitedRetry: { s in "限流，\(s) 秒后继续…" })

    static let en = WatchStrings(
        scanning: "Scanning…",
        skippedSome: { reason in "Some files were skipped: \(reason)" },
        uploadingFile: { name in "Uploading \(name)…" },
        uploadedAnnounce: { n in
            n == 1 ? "Folder watch: 1 new image uploaded"
                   : "Folder watch: \(n) new images uploaded"
        },
        manifestCount: { n in "\(n) tracked" },
        addedThisRun: { n in "+\(n) this run" },
        adoptedCount: { n in "\(n) matched" },
        skippedCount: { n in "\(n) skipped" },
        rateLimitedRetry: { s in "Rate limited, resuming in \(s)s…" })
}
