import Foundation

/// 上传前编辑器:裁剪 / 马赛克 / 旋转 / 水印的工具栏、提示与放弃确认。
struct EditorStrings: Sendable {
    // 入口与不可编辑的几种情形
    let pickPrompt: String
    let animatedUnsupported: String
    /// 像素上限取自 `ImageEdit.maxEditPixels`,单位是**百万像素**——数字别
    /// 写死在文案里,中文那份自己换算成「万」。
    let tooLarge: @Sendable (Int) -> String
    let unreadable: String
    let renderFailed: String

    // 工具栏
    let modeCrop: String
    let modeMosaic: String
    let ratioLabel: String
    let ratioFree: String
    let clearCrop: String
    let mosaicPixelate: String
    let mosaicSolid: String
    let brush: String
    let undoStroke: String
    let rotate: String
    let watermark: String
    let watermarkNeedsText: String
    let watermarkHelp: String

    // 放弃编辑确认
    let discardTitle: String
    let discardMessage: String
    let discardConfirm: String
    let keepEditing: String

    // 底栏
    let reset: String
    let cropHint: String
    let mosaicHint: String
    let cancel: String
    let upload: String
}

extension EditorStrings {
    static let zh = EditorStrings(
        pickPrompt: "编辑",
        animatedUnsupported: "动图不支持编辑，可直接上传",
        tooLarge: { mp in "图片超过 \(mp * 100) 万像素，暂不支持编辑，可直接上传" },
        unreadable: "无法读取此图片（文件可能已损坏）",
        renderFailed: "编辑渲染失败，未上传——请重试或取消",

        modeCrop: "裁剪",
        modeMosaic: "马赛克",
        ratioLabel: "比例",
        ratioFree: "自由",
        clearCrop: "清除裁剪",
        mosaicPixelate: "像素化",
        mosaicSolid: "纯色",
        brush: "笔刷",
        undoStroke: "撤销一笔",
        rotate: "旋转",
        watermark: "水印",
        watermarkNeedsText: "先在 设置 → 水印 里填好水印文字",
        watermarkHelp: "按设置里的样式加水印",

        discardTitle: "放弃当前编辑？",
        discardMessage: "裁剪、涂抹和旋转都会丢失。",
        discardConfirm: "放弃编辑",
        keepEditing: "继续编辑",

        reset: "重置",
        cropHint: "拖出裁剪框，四角可调，框内拖动移动",
        mosaicHint: "在需要遮盖的地方拖动涂抹",
        cancel: "取消",
        upload: "上传")

    static let en = EditorStrings(
        pickPrompt: "Edit",
        animatedUnsupported: "Animated images can’t be edited — upload this one as is",
        tooLarge: { mp in "Images over \(mp) megapixels can’t be edited — upload this one as is" },
        unreadable: "Can’t read this image (the file may be damaged)",
        renderFailed: "Rendering failed and nothing was uploaded — try again or cancel",

        // 「马赛克」在英文里不是遮挡工具的名字,macOS 预览的同款工具叫
        // Redact;这样下面的 Pixelate / Solid 才是它的两种样式而非同义反复。
        modeCrop: "Crop",
        modeMosaic: "Redact",
        ratioLabel: "Ratio",
        ratioFree: "Freeform",
        clearCrop: "Clear Crop",
        mosaicPixelate: "Pixelate",
        mosaicSolid: "Solid",
        brush: "Brush",
        undoStroke: "Undo Stroke",
        rotate: "Rotate",
        watermark: "Watermark",
        watermarkNeedsText: "Set the watermark text in Settings → Watermark first",
        watermarkHelp: "Applies the watermark style from Settings",

        discardTitle: "Discard your edits?",
        discardMessage: "The crop, brush strokes, and rotation will be lost.",
        discardConfirm: "Discard Edits",
        keepEditing: "Keep Editing",

        reset: "Reset",
        cropHint: "Drag to draw a crop box — drag the corners to resize, inside to move",
        mosaicHint: "Drag over anything you want to hide",
        cancel: "Cancel",
        upload: "Upload")
}
