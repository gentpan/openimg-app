import Foundation

/// 一个一键预设:点一下把描述填进输入框,用户仍然可以接着改。
///
/// `prompt` 中英两份是同一句英文,不跟界面语言走。上游模型对英文指令的理解
/// 稳得多,而这句话是给模型看的,不是给用户读的——`label` 才是给用户读的。
struct RetouchPreset: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let prompt: String
}

/// 修图分区:选原图、写要改什么、看历史。
///
/// 与生成分区共用额度卡与状态词(那是同一套额度、同一条轮询),这里只写它
/// 独有的那部分——「原图」这件事从头到尾都是生成页没有的。
struct RetouchStrings: Sendable {
    // 原图
    let sourcesLabel: String
    let addSource: String
    let removeSource: String
    /// 已选 / 上限。
    let sourceCount: @Sendable (Int, Int) -> String
    /// 一张都没选时,按钮上的悬浮说明——按钮是灰的,得说清为什么。
    let needSource: String

    // 选图面板
    let pickTitle: String
    /// 副标题写清能选几张。
    let pickSubtitle: @Sendable (Int) -> String
    let pickSearchPlaceholder: String
    let pickEmpty: String
    let pickLimitReached: @Sendable (Int) -> String
    let pickDone: String

    // 预设
    let presetsLabel: String
    let presets: [RetouchPreset]

    // 提示词
    let promptPlaceholder: String

    // 参数
    let sizeLabel: String
    let resolutionLabel: String
    /// 不指定尺寸时上游按原图出图,所以这一档叫「跟随原图」而不是「自动」
    /// ——后者没说清跟随的是什么。
    let followSource: String

    // 提交
    let retouchAction: String
    let retouching: String
    let submitted: String
    let takesAWhile: String
    let landsInGallery: String

    // 历史
    let historyTitle: String
    let historyEmpty: String
    let historyEmptyHint: String
    /// 一行里放不下的原图张数,跟在缩略图后面。
    let moreSources: @Sendable (Int) -> String
    /// 原图后来被删了,取不到缩略图。
    let sourcesGone: String
    /// 把这条记录的描述连同原图一起放回上面,再改一次。
    let reuse: String
    let doneToast: String
    let failedToast: @Sendable (String) -> String

    // 提交失败
    let errNoSource: String
    let errSourceMissing: String
}

extension RetouchStrings {
    static let zh = RetouchStrings(
        sourcesLabel: "原图",
        addSource: "从图库选图",
        removeSource: "移除这张",
        sourceCount: { picked, limit in "\(picked) / \(limit)" },
        needSource: "先从图库里选一张要改的图",

        pickTitle: "从图库选图",
        pickSubtitle: { limit in "最多选 \(limit) 张，再点一次可以取消选择" },
        pickSearchPlaceholder: "搜索文件名",
        pickEmpty: "没有找到图片",
        pickLimitReached: { limit in "最多 \(limit) 张，先取消一张再选" },
        pickDone: "完成",

        presetsLabel: "常用",
        presets: [
            .init(id: "watermark", label: "去水印", prompt: RetouchPrompts.watermark),
            .init(id: "declutter", label: "去除路人 / 杂物", prompt: RetouchPrompts.declutter),
            .init(id: "background", label: "换背景", prompt: RetouchPrompts.background),
            .init(id: "restore", label: "修复老照片", prompt: RetouchPrompts.restore),
            .init(id: "sharpen", label: "提升清晰度", prompt: RetouchPrompts.sharpen),
        ],

        promptPlaceholder: "说清楚要改哪里，其余保持不变",

        sizeLabel: "尺寸",
        resolutionLabel: "清晰度",
        followSource: "跟随原图",

        retouchAction: "开始修图",
        retouching: "修图中…",
        submitted: "已提交，出图约需几十秒",
        takesAWhile: "出图约需几十秒，期间可以去做别的",
        landsInGallery: "改好的图会作为新图存进图库，原图不会被动到",

        historyTitle: "最近修图",
        historyEmpty: "还没有修过图",
        historyEmptyHint: "选一张图，说一句要改什么",
        moreSources: { n in "+\(n)" },
        sourcesGone: "原图已不在图库",
        reuse: "用这张图和这句再改一次",
        doneToast: "修图完成，已存入图库",
        failedToast: { reason in "修图失败：\(reason)" },

        errNoSource: "至少要选一张原图",
        errSourceMissing: "选中的原图已经不在图库里了，重新选一张")

    static let en = RetouchStrings(
        sourcesLabel: "Source",
        addSource: "Pick from Gallery",
        removeSource: "Remove This One",
        sourceCount: { picked, limit in "\(picked) / \(limit)" },
        needSource: "Pick an image from your gallery first",

        pickTitle: "Pick from Gallery",
        pickSubtitle: { limit in "Up to \(limit) images — click again to deselect" },
        pickSearchPlaceholder: "Search file names",
        pickEmpty: "No images found",
        pickLimitReached: { limit in "\(limit) at most — deselect one first" },
        pickDone: "Done",

        presetsLabel: "Common",
        presets: [
            .init(id: "watermark", label: "Remove Watermark", prompt: RetouchPrompts.watermark),
            .init(id: "declutter", label: "Remove People / Clutter", prompt: RetouchPrompts.declutter),
            .init(id: "background", label: "Replace Background", prompt: RetouchPrompts.background),
            .init(id: "restore", label: "Restore Old Photo", prompt: RetouchPrompts.restore),
            .init(id: "sharpen", label: "Sharpen", prompt: RetouchPrompts.sharpen),
        ],

        promptPlaceholder: "Say what to change — everything else stays as it is",

        sizeLabel: "Aspect Ratio",
        resolutionLabel: "Detail",
        followSource: "Match Source",

        retouchAction: "Retouch",
        retouching: "Retouching…",
        submitted: "Submitted — this usually takes under a minute",
        takesAWhile: "Usually under a minute — feel free to do something else",
        landsInGallery: "The result is saved as a new image; your original is left untouched",

        historyTitle: "Recent Edits",
        historyEmpty: "Nothing retouched yet",
        historyEmptyHint: "Pick an image and say what to change",
        moreSources: { n in "+\(n)" },
        sourcesGone: "Source no longer in your gallery",
        reuse: "Reuse This Image and Prompt",
        doneToast: "Retouched — saved to your gallery",
        failedToast: { reason in "Retouch failed: \(reason)" },

        errNoSource: "At least one source image is required",
        errSourceMissing: "That source image is no longer in your gallery — pick another")
}

/// 预设的提示词本体。
///
/// 只有一份,中英两套文案共用:这些句子是发给上游模型的指令,不是界面文案。
/// 每一句都以「其余保持不变」收尾——不加这句,模型会顺手把整张图重画一遍。
enum RetouchPrompts {
    static let watermark = """
        Remove all watermarks, logos and text overlays from this image. \
        Keep everything else exactly unchanged.
        """
    static let declutter = """
        Remove the unwanted people and clutter in the background. \
        Keep the main subject unchanged.
        """
    static let background = """
        Replace the background with a clean solid studio backdrop. \
        Keep the subject unchanged.
        """
    static let restore = """
        Restore this old photo: remove scratches and stains, fix fading, \
        keep the original look.
        """
    static let sharpen = """
        Enhance the sharpness and detail of this image without changing its content.
        """
}
