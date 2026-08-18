import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 图片水印那枚 logo 的存放处。
///
/// **存 Application Support,不存 UserDefaults。** 其余的水印偏好(文字、锚点、
/// 透明度、比例)都在 UserDefaults 里,唯独这一份不是,理由是量级:UserDefaults
/// 背后是一份 plist,第一次读**任何**一个键就要把整份反序列化进内存,而每写一
/// 个键又要把整份刷回磁盘。一枚几百 KB 的 logo 塞进去,代价是每次冷启动多读几
/// 百 KB(哪怕这次根本没打水印),以及每拖动一次透明度滑块就把这几百 KB 重写
/// 一遍。它是一份从不参与比较、只在渲染那一刻被读一次的二进制,放文件里正好。
///
/// 一个固定文件名,不按账号或服务器分——与令牌、监控清单那种"属于某个账号"
/// 的东西不同,水印是这台机器上"我的署名",换个实例登录还是同一枚。
public enum WatermarkStore: Sendable {
    /// 存进来的 logo 的最长边。
    ///
    /// 1024 是内存与带宽考量,不是画质考量:这份字节会随配方进渲染任务、在
    /// 监控目录那条路上排队,而水印最终按画面宽度的百分之十几渲染——即便贴在
    /// 4000px 宽的图上也就 480px。存一张 4000px 的 logo,多出来的像素一个都不会
    /// 被用上,却要在每条排队的配方里各躺一份。
    public static let maxSide = 1024

    /// 收进来的原始文件的字节上限。挡的是"随手拖了一张 200MB 的 TIFF 进来"
    /// ——解码那一步会照做,然后这台机器安静下来好几秒。
    public static let maxInputBytes = 64 << 20

    public enum Failure: Error, Sendable, Equatable {
        /// 文件太大,连解码都不该开始。
        case tooLarge
        /// 这些字节不是一张认得出的图。
        case notAnImage
        /// 归一化成 PNG 失败。
        case encodeFailed
        /// 写盘失败,带上系统给的原话。
        case writeFailed(String)
    }

    public static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("io.openimg.mac/watermark.png")
    }

    /// 读回当前的水印图。没设过、或文件被人删了都返回 nil。
    public static func load() -> Data? {
        guard let d = try? Data(contentsOf: fileURL), !d.isEmpty else { return nil }
        return d
    }

    /// 归一化并存下一张图,返回**真正存进去的** PNG 字节。
    ///
    /// 返回而不是让调用方回头再读一次盘:调用方紧接着就要拿它去渲染预览、
    /// 判断透明度,而刚写下的那份就在手上。
    ///
    /// 一律转 PNG,不管进来的是什么:后面每一个环节(整层乘透明度、去背景、
    /// "有没有真的透明"的判断)都要 alpha,而用户拖进来的可能是 JPEG、HEIC,
    /// 或者从剪贴板落下来的 TIFF。在入口处统一一次,比让每个读的人各自判断
    /// 格式便宜,也让"存下来的东西是什么"这个问题只有一个答案。
    @discardableResult
    public static func store(_ data: Data) throws -> Data {
        guard data.count <= maxInputBytes else { throw Failure.tooLarge }
        guard let img = ImageEdit.decode(data) else { throw Failure.notAnImage }
        return try store(img)
    }

    @discardableResult
    public static func store(_ image: CGImage) throws -> Data {
        guard let png = pngData(downscaled(image)) else { throw Failure.encodeFailed }
        let url = fileURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            // 原子写:这份文件会在启动时被读,写到一半崩掉留下的半张 PNG
            // 下次启动就是一个解不开的水印。
            try png.write(to: url, options: .atomic)
        } catch {
            throw Failure.writeFailed(error.localizedDescription)
        }
        return png
    }

    /// 清掉水印图。文件不在也当成功——"现在没有水印图"正是调用方要的结果。
    public static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// 抠掉背景,返回新的 PNG 字节;认不出主体时返回 nil。
    ///
    /// 放在这里而不是让界面自己拼 SmartEdit + 编码:去背景的产物**必须**编成
    /// 带 alpha 的格式,写成 JPEG 会把刚挖空的地方填成黑色——这条纪律和存在
    /// 哪儿是同一件事,归同一个类型管。
    ///
    /// 不写盘。调用方多半要先让用户看一眼再决定留不留,存不存是它的决定。
    public static func withoutBackground(_ png: Data) throws -> Data? {
        guard let img = ImageEdit.decode(png) else { throw Failure.notAnImage }
        guard let cut = try SmartEdit.removeBackground(img) else { return nil }
        return pngData(cut)
    }

    /// 缩到 maxSide 之内。已经够小就原样返回,不为"过了一趟"付一次重采样。
    public static func downscaled(_ image: CGImage) -> CGImage {
        let side = max(image.width, image.height)
        guard side > maxSide else { return image }
        let k = Double(maxSide) / Double(side)
        let w = max(1, Int((Double(image.width) * k).rounded()))
        let h = max(1, Int((Double(image.height) * k).rounded()))
        // premultipliedLast + sRGB:logo 的 alpha 要留住,而这里不追求广色域
        // ——一枚署名图缩一次的色彩损失,肉眼在百分之十几的尺寸上看不出来。
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    /// CGImage → PNG 字节。PNG 是唯一的选择:这份图的全部价值在 alpha 上。
    public static func pngData(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, image, nil)
        guard CGImageDestinationFinalize(dst) else { return nil }
        return out as Data
    }
}
