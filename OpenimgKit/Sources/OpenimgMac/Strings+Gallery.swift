import Foundation
import OpenimgKit

/// 图库分区:网格、灯箱、整库导出。
///
/// `sortLabel` / `linkLabel` 是把 OpenimgKit 里的枚举标签翻出来的映射——枚举
/// 本身在共享的 Models.swift 里,不属于界面层,所以文案在这边落地,调用点
/// 传闭包而不是 `\.label`。
struct GalleryStrings: Sendable {
    // 筛选条与选择条。「删除」「取消」是通用词,取 common 那份,这里不留副本。
    let sortLabel: @Sendable (SortKey) -> String
    let selectedCount: @Sendable (Int) -> String
    let selectAll: String
    let deselectAll: String

    // 整库导出
    let exportAll: String
    let exportHelp: String
    let exportPanelPrompt: String
    /// 新下载 / 已存在跳过 / 失败;失败为 0 时不提这一段。
    let exportCounts: @Sendable (Int, Int, Int) -> String
    let exportInterrupted: @Sendable (String, String) -> String
    let exportCancelled: @Sendable (String) -> String
    let exportFinished: @Sendable (String) -> String

    // 状态栏。张数用 common.imageCount。
    let usedSpace: @Sendable (String) -> String
    let prevPage: String
    let nextPage: String

    // 卡片右键菜单
    let linkLabel: @Sendable (LinkFormat) -> String
    let copyFormat: @Sendable (String) -> String
    let copiedFormat: @Sendable (String) -> String
    let openInBrowser: String
    let editImage: String
    /// 从图库进编辑器要先把原图取回本地,几兆的图有可感的等待,得出声。
    let editFetching: String
    let editFetchFailed: String

    // 空状态
    let noMatches: @Sendable (String) -> String
    let clearSearch: String
    let emptyTitle: String
    let emptyHint: String
    let uploadFirst: String

    // 灯箱。「复制链接」那行标题用 common.copyLink。
    let openSharePage: String
    let deleteImage: String
}

extension GalleryStrings {
    static let zh = GalleryStrings(
        sortLabel: { key in
            switch key {
            case .newest: "最新上传"
            case .oldest: "最早上传"
            case .largest: "占用最大"
            case .smallest: "占用最小"
            case .widest: "分辨率最高"
            case .name: "文件名"
            }
        },
        selectedCount: { n in "已选 \(n) 张" },
        selectAll: "全选本页",
        deselectAll: "取消全选",

        exportAll: "导出全部",
        exportHelp: "把整个图库下载到本地目录；已存在的文件跳过，中断后重跑只补缺的。导出的是存储的图片——开着自动转换时是 WebP/AVIF，不是上传前的原文件。",
        exportPanelPrompt: "导出到此目录",
        exportCounts: { done, skipped, failed in
            "新下载 \(done)，已存在跳过 \(skipped)" + (failed > 0 ? "，失败 \(failed)" : "")
        },
        exportInterrupted: { reason, counts in "导出中断：\(reason)（\(counts)）" },
        exportCancelled: { counts in "导出已取消：\(counts)" },
        exportFinished: { counts in "导出完成：\(counts)" },

        usedSpace: { size in "已用 \(size)" },
        prevPage: "上一页",
        nextPage: "下一页",

        linkLabel: { f in
            switch f {
            case .url: "直链"
            case .markdown: "Markdown"
            case .html: "HTML"
            case .bbcode: "BBCode"
            }
        },
        copyFormat: { what in "复制\(what)" },
        copiedFormat: { what in "已复制\(what)" },
        openInBrowser: "在浏览器打开",
        editImage: "编辑",
        editFetching: "正在取回原图…",
        editFetchFailed: "取回原图失败",

        noMatches: { query in "没有匹配「\(query)」的图片" },
        clearSearch: "清除搜索",
        emptyTitle: "图库还是空的",
        emptyHint: "拖一张图片进来，或按 ⌘U 选择文件",
        uploadFirst: "上传第一张",

        openSharePage: "打开分享页",
        deleteImage: "删除这张图片")

    static let en = GalleryStrings(
        sortLabel: { key in
            switch key {
            case .newest: "Newest"
            case .oldest: "Oldest"
            case .largest: "Largest"
            case .smallest: "Smallest"
            case .widest: "Highest Resolution"
            case .name: "Name"
            }
        },
        selectedCount: { n in "\(n) selected" },
        selectAll: "Select All on Page",
        deselectAll: "Deselect All",

        exportAll: "Export All",
        exportHelp: "Download the whole gallery to a local folder. Files already there are skipped, so re-running after an interruption only fills the gaps. This exports the stored images — WebP/AVIF while auto-conversion is on, not the files you uploaded.",
        exportPanelPrompt: "Export Here",
        exportCounts: { done, skipped, failed in
            "\(done) downloaded, \(skipped) already there" + (failed > 0 ? ", \(failed) failed" : "")
        },
        exportInterrupted: { reason, counts in "Export interrupted: \(reason) (\(counts))" },
        exportCancelled: { counts in "Export cancelled: \(counts)" },
        exportFinished: { counts in "Export complete: \(counts)" },

        usedSpace: { size in "\(size) used" },
        prevPage: "Previous Page",
        nextPage: "Next Page",

        linkLabel: { f in
            switch f {
            case .url: "Direct Link"
            case .markdown: "Markdown"
            case .html: "HTML"
            case .bbcode: "BBCode"
            }
        },
        copyFormat: { what in "Copy \(what)" },
        copiedFormat: { what in "Copied \(what)" },
        openInBrowser: "Open in Browser",
        editImage: "Edit",
        editFetching: "Fetching the original…",
        editFetchFailed: "Could not fetch the original",

        noMatches: { query in "No images match “\(query)”" },
        clearSearch: "Clear Search",
        emptyTitle: "Your gallery is empty",
        emptyHint: "Drag an image in, or press ⌘U to choose a file",
        uploadFirst: "Upload Your First Image",

        openSharePage: "Open Share Page",
        deleteImage: "Delete This Image")
}
