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
        let ctx = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        return ctx.createCGImage(ci, from: ci.extent,
                                 format: .RGBA8,
                                 colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
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
        let ctx = CIContext()
        return ctx.createCGImage(out, from: out.extent)
    }

    /// 这台机器是否支持去背景。Vision 的前景分割是 macOS 14 起的能力,
    /// 而 App 的最低版本正是 14,所以恒为真——留着这个入口是为了 iOS 端
    /// 复用时能收紧条件,而不是让调用方去猜。
    public static var canRemoveBackground: Bool {
        if #available(macOS 14.0, iOS 17.0, *) { return true }
        return false
    }
}
