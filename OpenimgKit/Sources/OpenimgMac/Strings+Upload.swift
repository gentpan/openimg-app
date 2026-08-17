import Foundation

/// 上传页:拖放区、批次头、队列行状态。
struct UploadStrings: Sendable {
    // 拖放区
    let dropTitle: String
    let dropHint: String
    let addMore: String

    // 编辑入口
    let editThenUpload: String
    let editHelp: String
    let editOnDrop: String

    // 批次头
    let uploadingProgress: @Sendable (Int, Int) -> String
    let allDone: @Sendable (Int) -> String
    let partlyDone: @Sendable (Int, Int) -> String
    let uploadingBusy: String
    let clearList: String

    // 链接格式
    let copyAfterUpload: String

    // 转换设置一览
    let maxWidth: @Sendable (Int) -> String
    let changeInSettings: String
    let unlimited: String

    // 配额
    let remainingToday: String
    let imageCount: @Sendable (Int) -> String
    let maxFileSize: String
    let supportedFormats: String

    // 队列行
    let shrunkTo: @Sendable (Int) -> String
    let deduplicated: String
    let waiting: String
    let done: String
}

extension UploadStrings {
    static let zh = UploadStrings(
        dropTitle: "把图片或文件夹拖到这里",
        dropHint: "或点击选择，文件夹会自动展开",
        addMore: "继续添加",

        editThenUpload: "编辑后上传…",
        editHelp: "裁剪、马赛克、旋转、水印，改完直接进上传队列",
        editOnDrop: "单张拖入先打开编辑器",

        uploadingProgress: { done, total in "上传中 \(done) / \(total)" },
        allDone: { n in "\(n) 张全部完成" },
        partlyDone: { ok, bad in "\(ok) 张完成，\(bad) 张未成功" },
        uploadingBusy: "上传中…",
        clearList: "清空列表",

        copyAfterUpload: "上传后复制",

        maxWidth: { px in "最大 \(px)px" },
        changeInSettings: "在设置里改",
        unlimited: "不限",

        remainingToday: "今日剩余",
        imageCount: { n in "\(n) 张" },
        maxFileSize: "单文件上限",
        supportedFormats: "支持格式",

        shrunkTo: { pct in "已缩至 \(pct)%" },
        deduplicated: "秒传",
        waiting: "等待中",
        done: "完成")

    static let en = UploadStrings(
        dropTitle: "Drop images or folders here",
        dropHint: "Or click to choose — folders expand automatically",
        addMore: "Add More",

        editThenUpload: "Edit Before Upload…",
        editHelp: "Crop, mosaic, rotate, watermark — then straight into the upload queue",
        editOnDrop: "Open the editor when a single image is dropped",

        uploadingProgress: { done, total in "Uploading \(done) of \(total)" },
        allDone: { n in n == 1 ? "1 image uploaded" : "All \(n) images uploaded" },
        partlyDone: { ok, bad in "\(ok) uploaded, \(bad) failed" },
        uploadingBusy: "Uploading…",
        clearList: "Clear List",

        copyAfterUpload: "Copy after upload",

        maxWidth: { px in "Max \(px)px" },
        changeInSettings: "Change in Settings",
        unlimited: "Unlimited",

        remainingToday: "Remaining today",
        imageCount: { n in n == 1 ? "1 image" : "\(n) images" },
        maxFileSize: "Max file size",
        supportedFormats: "Formats",

        shrunkTo: { pct in "Shrunk to \(pct)%" },
        deduplicated: "Instant",
        waiting: "Waiting",
        done: "Done")
}
