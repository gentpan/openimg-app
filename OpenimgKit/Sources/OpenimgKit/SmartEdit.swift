import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// 本机智能修图:去背景与自动增强。
///
/// 刻意全部离线。云端 AI 要 API key、要花钱,还得把用户的图发给第三方——
/// 这和产品「上传即剥 EXIF」的隐私立场直接冲突。macOS 14 起 Vision 自带
/// 前景分割,Core Image 自带自动色彩校正,两者都在本机跑,零依赖、零外发。
public enum SmartEdit: Sendable {
    /// 共享一个 CIContext,理由与 ImageAdjust 那个完全相同:建一个 CIContext
    /// 要起一条 Metal 命令队列,比这里真正的工作还贵。原先这两个方法各自
    /// `CIContext()` 一次,而 SmartEdit 恰恰是被"每帧预览"反复调用的那一侧,
    /// 与隔壁特意共享上下文的理由自相矛盾。
    ///
    /// 不再指定 workingColorSpace:这两条路上都没有真跑滤镜(一条是把 Vision
    /// 的遮罩结果转成 CGImage,另一条的滤镜链由 Core Image 自己给出),工作
    /// 空间只影响中间运算,默认的扩展线性 sRGB 覆盖得住广色域。
    private static let ciContext = CIContext()

    /// 抠掉背景,只留主体,输出带透明通道的图。
    ///
    /// 用 Vision 的前景实例遮罩:它认的是"照片里的主体",人像、物品、宠物
    /// 都算,而不是按颜色抠图。没有可辨认主体时返回 nil——与其给一张被
    /// 胡乱挖空的图,不如说这张不适合。
    public static func removeBackground(_ image: CGImage) throws -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            return nil
        }
        let masked = try result.generateMaskedImage(
            ofInstances: result.allInstances,
            from: handler,
            croppedToInstancesExtent: false)
        let ci = CIImage(cvPixelBuffer: masked)
        // 输出必须带 alpha:抠完的图正是要透明背景,用不带 alpha 的格式
        // 会把透明处填成黑色。
        return ciContext.createCGImage(ci, from: ci.extent,
                                       format: .RGBA8,
                                       colorSpace: ImageEdit.drawingSpace(image))
    }

    /// 自动增强:曝光、对比、色偏、肤色一起校正。
    ///
    /// 用 Core Image 自己分析出来的滤镜链,而不是我拍脑袋写一组固定参数——
    /// 同一组参数在欠曝夜景和过曝雪景上会朝相反方向拉。
    public static func autoEnhance(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let filters = input.autoAdjustmentFilters(options: [.enhance: true, .redEye: false])
        var out = input
        for f in filters {
            f.setValue(out, forKey: kCIInputImageKey)
            guard let result = f.outputImage else { continue }
            out = result
        }
        // 没有可调的(已经很正)时原样返回,不为"点了按钮"付一次重编码。
        guard out != input else { return image }
        // 色彩空间跟着源图,别让"自动增强"顺带把广色域源压成 sRGB
        // ——同 ImageAdjust.apply,见 ImageEdit.drawingSpace。
        return ciContext.createCGImage(out, from: out.extent, format: .RGBA8,
                                       colorSpace: ImageEdit.drawingSpace(image))
    }

    /// 这台机器是否支持去背景。Vision 的前景分割是 macOS 14 起的能力,
    /// 而 App 的最低版本正是 14,所以恒为真——留着这个入口是为了 iOS 端
    /// 复用时能收紧条件,而不是让调用方去猜。
    public static var canRemoveBackground: Bool {
        if #available(macOS 14.0, iOS 17.0, *) { return true }
        return false
    }
}
