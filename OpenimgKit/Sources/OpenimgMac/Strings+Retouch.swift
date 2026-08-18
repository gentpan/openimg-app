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

/// 修图分区:写要改什么、看历史。
///
/// 与生成分区共用额度卡与状态词(那是同一套额度、同一条轮询);选图那一行
/// 的措辞也已经共用了(见 AISourceStrings)——生成页加上参考图之后,那一行
/// 两页长得一模一样,只剩「原图 / 参考图」这个称呼还是各自的。
struct RetouchStrings: Sendable {
    // 原图
    let sourcesLabel: String
    /// 一张都没选时,按钮上的悬浮说明——按钮是灰的,得说清为什么。
    let needSource: String

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
        needSource: "先选一张要改的图：从图库里选，或者直接传一张",

        presetsLabel: "常用",
        presets: [
            .init(id: "watermark", label: "去水印", prompt: RetouchPrompts.watermark),
            .init(id: "declutter", label: "去除路人 / 杂物", prompt: RetouchPrompts.declutter),
            .init(id: "background", label: "换背景", prompt: RetouchPrompts.background),
            .init(id: "restore", label: "修复老照片", prompt: RetouchPrompts.restore),
            .init(id: "sharpen", label: "提升清晰度", prompt: RetouchPrompts.sharpen),
            .init(id: "text", label: "去文字", prompt: RetouchPrompts.removeText),
            .init(id: "whitebg", label: "白底商品图", prompt: RetouchPrompts.whiteBackground),
            .init(id: "colorize", label: "黑白上色", prompt: RetouchPrompts.colorize),
            .init(id: "portrait", label: "人像精修", prompt: RetouchPrompts.portrait),
            .init(id: "cartoon", label: "卡通风格", prompt: RetouchPrompts.cartoon),
            .init(id: "expand", label: "扩展画面", prompt: RetouchPrompts.expand),
        ],

        promptPlaceholder: "说清楚要改哪里，其余保持不变",

        sizeLabel: "尺寸",
        resolutionLabel: "清晰度",
        followSource: "跟随原图",

        retouchAction: "开始修图",
        retouching: "修图中…",
        submitted: "已提交，出图约需几十秒",
        takesAWhile: "出图约需几十秒，期间可以去做别的",

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
        needSource: "Pick an image first — from your gallery, or upload one",

        presetsLabel: "Common",
        presets: [
            .init(id: "watermark", label: "Remove Watermark", prompt: RetouchPrompts.watermark),
            .init(id: "declutter", label: "Remove People / Clutter", prompt: RetouchPrompts.declutter),
            .init(id: "background", label: "Replace Background", prompt: RetouchPrompts.background),
            .init(id: "restore", label: "Restore Old Photo", prompt: RetouchPrompts.restore),
            .init(id: "sharpen", label: "Sharpen", prompt: RetouchPrompts.sharpen),
            .init(id: "text", label: "Remove Text", prompt: RetouchPrompts.removeText),
            .init(id: "whitebg", label: "White Background", prompt: RetouchPrompts.whiteBackground),
            .init(id: "colorize", label: "Colorize", prompt: RetouchPrompts.colorize),
            .init(id: "portrait", label: "Retouch Portrait", prompt: RetouchPrompts.portrait),
            .init(id: "cartoon", label: "Illustration", prompt: RetouchPrompts.cartoon),
            .init(id: "expand", label: "Extend Canvas", prompt: RetouchPrompts.expand),
        ],

        promptPlaceholder: "Say what to change — everything else stays as it is",

        sizeLabel: "Aspect Ratio",
        resolutionLabel: "Detail",
        followSource: "Match Source",

        retouchAction: "Retouch",
        retouching: "Retouching…",
        submitted: "Submitted — this usually takes under a minute",
        takesAWhile: "Usually under a minute — feel free to do something else",

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
    static let removeText = """
        Remove all text, captions and subtitles from this image. \
        Reconstruct what was behind them; keep everything else unchanged.
        """
    static let whiteBackground = """
        Cut out the product and place it on a pure white background, \
        centered, with soft even lighting and a natural contact shadow.
        """
    static let colorize = """
        Colorize this black and white photo with natural, period-accurate \
        colors. Keep the original composition and details.
        """
    static let portrait = """
        Retouch this portrait: even out skin tone, remove blemishes, \
        brighten the eyes. Keep the person clearly recognizable — \
        do not reshape the face.
        """
    static let cartoon = """
        Redraw this image as a clean flat illustration with bold outlines \
        and simple shading. Keep the subject and composition recognizable.
        """
    static let expand = """
        Extend this image outward, continuing the scene naturally on all \
        sides. Keep the existing content untouched.
        """
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
