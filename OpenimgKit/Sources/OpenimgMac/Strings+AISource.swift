import Foundation

/// 「给 AI 几张图」这件事的文案。
///
/// 修图页把它叫「原图」、生成页把它叫「参考图」,但要用户做的事一模一样:
/// 从图库里挑几张,或者现传几张。所以除了那个称呼(由各页自己给),其余
/// 的话都收在这一份里——两页各写一套的话,同一个按钮迟早会有两种说法。
struct AISourceStrings: Sendable {
    /// 输入区那条「最近上传」快捷条的小标。
    let recentLabel: String
    let pickFromGallery: String
    /// 直接上传:选完就是图库里的一张普通图片,顺手被选中。
    let uploadNew: String
    let uploading: String
    /// 那一行同时也是拖放目标,得说一句,否则没人会去试。
    let dropHint: String
    let removeSource: String
    /// 已选 / 上限。
    let sourceCount: @Sendable (Int, Int) -> String
    let limitReached: @Sendable (Int) -> String
    /// 传完并选中了几张。说「已选中」而不只是「已上传」:用户按的是选图,
    /// 上传只是路上顺带发生的事。
    let uploaded: @Sendable (Int) -> String
    /// 一张都没传成功。具体原因由上传流水线自己播报,这里只收尾。
    let uploadFailed: String
    /// 选的文件一个都不能传时说清原因,而不是静默什么都不做。
    let noUploadable: String
    let uploadBusy: String

    // 选图面板
    let pickTitle: String
    /// 副标题写清能选几张。
    let pickSubtitle: @Sendable (Int) -> String
    let pickSearchPlaceholder: String
    let pickEmpty: String
    let pickDone: String
}

extension AISourceStrings {
    static let zh = AISourceStrings(
        recentLabel: "最近上传",
        pickFromGallery: "从图库选图",
        uploadNew: "上传新图",
        uploading: "上传中…",
        dropHint: "也可以把图片拖到这一行",
        removeSource: "移除这张",
        sourceCount: { picked, limit in "\(picked) / \(limit)" },
        limitReached: { limit in "最多 \(limit) 张，先取消一张再选" },
        uploaded: { n in n == 1 ? "已上传并选中这张" : "已上传并选中 \(n) 张" },
        uploadFailed: "上传失败，没有图被选中",
        noUploadable: "这些文件传不了：只能是图片，且要在你的套餐支持的格式里",
        uploadBusy: "正在上传，稍等一下",

        pickTitle: "从图库选图",
        pickSubtitle: { limit in "最多选 \(limit) 张，再点一次可以取消选择" },
        pickSearchPlaceholder: "搜索文件名",
        pickEmpty: "没有找到图片",
        pickDone: "完成")

    static let en = AISourceStrings(
        recentLabel: "Recent",
        pickFromGallery: "Pick from Gallery",
        uploadNew: "Upload",
        uploading: "Uploading…",
        dropHint: "or drop images onto this row",
        removeSource: "Remove This One",
        sourceCount: { picked, limit in "\(picked) / \(limit)" },
        limitReached: { limit in "\(limit) at most — deselect one first" },
        uploaded: { n in n == 1 ? "Uploaded and selected" : "Uploaded and selected \(n)" },
        uploadFailed: "Upload failed — nothing was selected",
        noUploadable: "Nothing to upload — images only, in a format your plan allows",
        uploadBusy: "Still uploading — hang on",

        pickTitle: "Pick from Gallery",
        pickSubtitle: { limit in "Up to \(limit) images — click again to deselect" },
        pickSearchPlaceholder: "Search file names",
        pickEmpty: "No images found",
        pickDone: "Done")
}
