import Foundation
import ImageIO
import CoreGraphics
import CoreText
import UniformTypeIdentifiers

/// 上传前编辑的"配方"。渲染顺序:
///
///   变换(旋转+翻转) → 自动增强 → 抠图 → 色彩调整 → 马赛克 → 裁剪 → 水印 → 导出缩放
///
/// 这个顺序不是历史沿革,每一步的位置都有一条不能换的理由:
///
///  1. **变换最先**。所有归一化坐标(笔迹、裁剪框)都定义在"变换后所见的
///     画面"上,变换必须先落定,后面的坐标才有意义。
///  2. **增强、抠图紧随其后**。两者都靠对整幅画面的判断:autoAdjustment 看
///     全局直方图,Vision 的前景分割认的是语义上的"主体"。任何局部涂抹或
///     全局滤镜都会污染这个判断。
///  3. **色彩调整在抠图之后、马赛克之前**。不能更早:模糊会糊掉主体边缘和
///     纹理,饱和归零(黑白预设)会削弱分割线索,Vision 会跟着抠错。也不能
///     更晚:马赛克是隐私遮挡,一层高斯模糊压在纯色块上会把边缘晕开、泄出
///     底下像素的颜色,而像素化格子被"平滑"回渐变,看起来像是能被复原——
///     遮挡必须是最后落下、不被任何后续滤镜削弱的一层。
///  4. **裁剪在调色之后**。高斯模糊要取画外的样(见 ImageAdjust.apply);先裁
///     的话裁剪边就成了画面边,四周会多一圈晕边。代价是对全尺寸图做模糊,
///     慢一点,但这是正确性换的。
///  5. **水印最后**。署名不该被调色、被模糊、被裁掉。
///  6. **导出缩放收尾**,纯重采样,不改内容。
///
/// 所有坐标归一化到 0-1,基于**当前变换后的画面**(用户所见即所记);再转
/// 90° 或翻转时由 EditGeometry 把已有笔迹/裁剪框一起搬过去。笔刷半径与模糊
/// 半径都归一化到对角线——变换不改变对角线,含义因此变换不变。
///
/// 这里只做服务端做不了的**内容决策**(涂掉隐私、裁掉无关、打署名、调色)。
/// 默认仍不转格式:本地转码会破坏 SHA 秒传、叠加两代有损——见 LocalResize
/// 头注,同一条纪律。exportFormat 是那条纪律唯一的例外,而它只在用户显式选
/// 了某个格式时才生效。
public struct EditSpec: Sendable, Equatable {
    /// 顺时针 90° 次数,0-3。
    public var rotationQuarters = 0
    /// 水平翻转(所见画面的左右互换)。
    ///
    /// 与旋转同属"变换"一档,渲染时合并成一次绘制。定义上**翻转在旋转之后**
    /// 应用(最终画面 = flip(rotate(原图))),这样不论转了几个 90°,flipHorizontal
    /// 永远就是"我看到的这幅画左右对调"——界面上那个按钮可以无脑 toggle,
    /// 归一化坐标的变换也永远只是 x → 1-x。代价记在 rotateSpecCW 里。
    public var flipHorizontal = false
    /// 垂直翻转(所见画面的上下互换)。同上。
    public var flipVertical = false
    /// 归一化裁剪区,nil 不裁。
    public var crop: CGRect?
    public var strokes: [MosaicStroke] = []
    public var mosaicStyle: MosaicStyle = .pixelate
    public var watermark: WatermarkSpec?
    /// 本机智能操作。见头注第 2、3 条。
    public var enhance = false
    public var cutout = false
    /// 六个连续色彩参数。全中性时整段跳过,不进渲染管线。
    public var adjustments = ColorAdjustments()
    /// 导出质量。只作用于编辑产物——编辑过的图本来就是新内容,不存在破坏
    /// 秒传去重的问题(未编辑的原件仍走原样上传,见 LocalResize 头注)。
    public var exportQuality: Double = 0.92
    /// 导出前限宽,0 不限。同上,只对编辑产物生效。
    public var exportMaxWidth = 0
    /// 导出倍率。**只与 exportMaxWidth 相乘**,见 effectiveMaxWidth。
    public var exportScale: ExportScale = .x1
    /// 输出格式,auto = 保持原格式。最终格式由 ExportFormat.resolve 定,那里
    /// 写着与抠图(必须带 alpha)和本机可写性的优先级。
    public var exportFormat: ExportFormat = .auto

    public init() {}

    /// 倍率作用后的实际限宽;没设限宽时倍率无效,返回 0(不限)。
    ///
    /// 倍率**不**单独作用于原始尺寸,理由:
    ///  - 图床的产物是给人看的。把 4000px 的源图插值放大到 12000px 不产生任何
    ///    新信息,只是让别人多下载几 MB;而这个 App 的图最终都要过服务端再编码,
    ///    放大的那部分连"本地留个高清底"的借口都没有。
    ///  - 限宽回答"我要多宽",倍率回答"按几倍屏出",两者相乘正是 @2x 资源的
    ///    语义:限宽 800 + 2x = 1600px 的图,拿去当 800pt 宽的 HiDPI 素材。
    ///  - 这样倍率永远不会把图放到超过原始尺寸(渲染只在图比目标宽时才缩),
    ///    不需要额外的上限判断。
    public var effectiveMaxWidth: Int {
        guard exportMaxWidth > 0 else { return 0 }
        return max(1, Int((Double(exportMaxWidth) * exportScale.rawValue).rounded()))
    }

    /// 有任何会改变像素(或改变文件格式)的操作。
    ///
    /// exportScale 不单独计入:没有限宽时它本来就无效,有限宽时 exportMaxWidth
    /// 已经把这条算进来了。exportFormat 计入是因为换格式本身就是要写一份新
    /// 文件——即便它碰巧和源格式相同也照算:EditSpec 不知道源是什么格式,
    /// 宁可多编一次,也不要静默吞掉用户明确点下的选择。
    public var hasEdits: Bool {
        rotationQuarters % 4 != 0 || flipHorizontal || flipVertical
            || crop != nil || !strokes.isEmpty || watermark != nil
            || enhance || cutout || !adjustments.isNeutral
            || exportMaxWidth > 0 || exportFormat != .auto
    }

    /// 产物必须带透明通道(抠图挖空的背景)。
    public var requiresAlpha: Bool { cutout }

    /// 最终写出去的格式。要源格式才能定 auto,所以是方法不是属性。
    public func resolvedFormat(sourceType: UTType?) -> ExportFormat {
        ExportFormat.resolve(requested: exportFormat, sourceType: sourceType,
                             requiresAlpha: requiresAlpha)
    }

    /// 用户选的格式存不下 alpha,而这张图抠过背景——最终会被改写成 PNG。
    /// 界面据此提前提示,而不是让人事后发现自己拿到一张黑底图。
    ///
    /// 只回答"显式选择"这一种情形:exportFormat 为 auto 时格式跟着源走,而
    /// EditSpec 不持有源文件,答不了。真正的最终格式问 resolvedFormat(sourceType:)。
    public var forcesPNG: Bool {
        requiresAlpha && !exportFormat.supportsAlpha
    }
}

public struct MosaicStroke: Sendable, Equatable {
    /// 归一化点列(基于旋转后画面)。
    public var points: [CGPoint]
    /// 笔刷半径,归一化到画面对角线。
    public var radius: Double

    public init(points: [CGPoint], radius: Double) {
        self.points = points
        self.radius = radius
    }
}

/// 像素化会破坏信息,纯色覆盖更彻底;都不用高斯模糊——模糊文字有被复原
/// 的先例,给用户一个"看起来遮住了"的假安全感比不提供更糟。
public enum MosaicStyle: String, Sendable, CaseIterable {
    case pixelate, solid
}

public struct WatermarkSpec: Sendable, Equatable {
    public var text: String
    /// 九宫格锚点 0-8,行优先:0 左上、4 居中、8 右下。
    public var anchor: Int
    public var opacity: Double
    /// 字号相对画面宽度的比例。
    public var scale: Double

    public init(text: String, anchor: Int = 8, opacity: Double = 0.45, scale: Double = 0.03) {
        self.text = text
        self.anchor = anchor
        self.opacity = opacity
        self.scale = scale
    }
}

/// 纯几何,不碰像素——KitCheck 能在无渲染环境里自检。
public enum EditGeometry {
    /// 裁剪矩形夹进 0-1 并保证最小边长(防手一抖裁出零面积)。
    public static func clampCrop(_ r: CGRect, minSide: Double = 0.02) -> CGRect {
        var x = max(0, min(r.origin.x, 1 - minSide))
        var y = max(0, min(r.origin.y, 1 - minSide))
        var w = max(minSide, r.width)
        var h = max(minSide, r.height)
        if x + w > 1 { w = 1 - x }
        if y + h > 1 { h = 1 - y }
        // 夹宽高后仍可能低于最小边(rect 本来就贴边),往回挪原点补足。
        if w < minSide { w = minSide; x = 1 - w }
        if h < minSide { h = minSide; y = 1 - h }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// 顺时针转 90° 后的尺寸。
    public static func rotatedSize(_ s: CGSize, quarters: Int) -> CGSize {
        (quarters % 2 == 0) ? s : CGSize(width: s.height, height: s.width)
    }

    /// 归一化点随画面顺时针转 90°:(x,y) → (1-y, x)。
    public static func rotateQuarterCW(_ p: CGPoint) -> CGPoint {
        CGPoint(x: 1 - p.y, y: p.x)
    }

    /// 归一化矩形随画面顺时针转 90°。
    public static func rotateQuarterCW(_ r: CGRect) -> CGRect {
        // 转角点再取包围盒:旋转后 origin 换角,直接转四角最不易错。
        let a = rotateQuarterCW(CGPoint(x: r.minX, y: r.minY))
        let b = rotateQuarterCW(CGPoint(x: r.maxX, y: r.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                      width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// 归一化点随画面水平翻转:(x,y) → (1-x, y)。
    public static func flipH(_ p: CGPoint) -> CGPoint { CGPoint(x: 1 - p.x, y: p.y) }
    /// 归一化点随画面垂直翻转:(x,y) → (x, 1-y)。
    public static func flipV(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: 1 - p.y) }

    /// 归一化矩形随画面水平翻转。
    public static func flipH(_ r: CGRect) -> CGRect {
        CGRect(x: 1 - r.maxX, y: r.minY, width: r.width, height: r.height)
    }
    /// 归一化矩形随画面垂直翻转。
    public static func flipV(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
    }

    /// 把整份配方随画面顺时针转 90°(笔迹与裁剪框跟着画面走,半径归一化
    /// 到对角线所以不变)。
    ///
    /// 翻转标志要跟着换轴。EditSpec 定义的变换是 flip ∘ rotate^q,而用户点
    /// "转 90°"要的是 R ∘ (flip ∘ rotate^q)。把 R 挪到最外层要用恒等式
    /// R∘F_h = F_v∘R(顺时针 90° 把"左右互换"变成"上下互换"),于是:
    ///
    ///   R ∘ F_h ∘ R^q  =  F_v ∘ R^(q+1)
    ///
    /// 只翻一个轴时 H 与 V 互换;两个都翻等于转 180°,与 R 交换,不受影响;
    /// 都不翻自然也没事。所以规则就是"恰好翻了一个轴时交换这两个布尔"。
    /// 这一条是把 flip 定义在旋转之外(而不是之内)换来的唯一代价——换来的
    /// 是界面上的翻转按钮永远只是 toggle,坐标变换永远只是 x → 1-x。
    public static func rotateSpecCW(_ spec: EditSpec) -> EditSpec {
        var s = spec
        s.rotationQuarters = (s.rotationQuarters + 1) % 4
        if s.flipHorizontal != s.flipVertical {
            let h = s.flipHorizontal
            s.flipHorizontal = s.flipVertical
            s.flipVertical = h
        }
        s.crop = s.crop.map(rotateQuarterCW)
        s.strokes = s.strokes.map { MosaicStroke(points: $0.points.map(rotateQuarterCW), radius: $0.radius) }
        return s
    }

    /// 把整份配方随画面水平翻转:切换标志,并把已有笔迹/裁剪框一起翻过去
    /// (涂在鼻子上的马赛克翻完还得在鼻子上)。垂直翻转同理。
    public static func flipSpecH(_ spec: EditSpec) -> EditSpec {
        var s = spec
        s.flipHorizontal.toggle()
        s.crop = s.crop.map(flipH)
        s.strokes = s.strokes.map { MosaicStroke(points: $0.points.map(flipH), radius: $0.radius) }
        return s
    }

    public static func flipSpecV(_ spec: EditSpec) -> EditSpec {
        var s = spec
        s.flipVertical.toggle()
        s.crop = s.crop.map(flipV)
        s.strokes = s.strokes.map { MosaicStroke(points: $0.points.map(flipV), radius: $0.radius) }
        return s
    }

    /// 九宫格锚点 → 水印左下角原点(像素坐标,CG 坐标系 y 向上)。
    public static func watermarkOrigin(anchor: Int, textSize: CGSize,
                                       canvas: CGSize, margin: Double) -> CGPoint {
        let col = Double(max(0, min(anchor, 8)) % 3)
        let row = Double(max(0, min(anchor, 8)) / 3)   // 0 顶 1 中 2 底
        let x: Double = switch col {
        case 0: margin
        case 1: (canvas.width - textSize.width) / 2
        default: canvas.width - textSize.width - margin
        }
        // CG y 向上:九宫格第 0 行是视觉顶部 → 高 y。
        let y: Double = switch row {
        case 0: canvas.height - textSize.height - margin
        case 1: (canvas.height - textSize.height) / 2
        default: margin
        }
        return CGPoint(x: x, y: y)
    }

    /// 拖拽版比例约束:以锚点(拖拽的固定对角)为不动点,朝光标方向按像素
    /// 比定框。中心重锚版(下面那个)只适合比例下拉框——拖角时用它会让
    /// "固定角"持续漂移。minSide 兜底两轴同乘,比例不破;顶到画布边同样
    /// 等比缩回。
    public static func applyRatio(anchor: CGPoint, cursor: CGPoint, pixelRatio: Double,
                                  canvas: CGSize, minSide: Double = 0.02) -> CGRect {
        guard pixelRatio > 0, canvas.width > 0, canvas.height > 0 else {
            return clampCrop(CGRect(x: min(anchor.x, cursor.x), y: min(anchor.y, cursor.y),
                                    width: abs(anchor.x - cursor.x), height: abs(anchor.y - cursor.y)))
        }
        var pw = abs(cursor.x - anchor.x) * canvas.width
        var ph = abs(cursor.y - anchor.y) * canvas.height
        if ph * pixelRatio > pw { ph = pw / pixelRatio } else { pw = ph * pixelRatio }
        let k = max(1, minSide * canvas.width / max(pw, 1e-9),
                    minSide * canvas.height / max(ph, 1e-9))
        pw *= k
        ph *= k
        var w = min(pw / canvas.width, 1)
        var h = min(ph / canvas.height, 1)
        // 越过画布边:两轴同乘缩回——归一化宽高等比缩,像素比不变。
        var shrink = 1.0
        if cursor.x < anchor.x { shrink = min(shrink, anchor.x / max(w, 1e-9)) }
        else { shrink = min(shrink, (1 - anchor.x) / max(w, 1e-9)) }
        if cursor.y < anchor.y { shrink = min(shrink, anchor.y / max(h, 1e-9)) }
        else { shrink = min(shrink, (1 - anchor.y) / max(h, 1e-9)) }
        if shrink < 1 {
            w *= shrink
            h *= shrink
        }
        let x = cursor.x >= anchor.x ? anchor.x : anchor.x - w
        let y = cursor.y >= anchor.y ? anchor.y : anchor.y - h
        return CGRect(x: max(0, min(x, 1 - w)), y: max(0, min(y, 1 - h)), width: w, height: h)
    }

    /// 以中心为锚把矩形调整为给定宽高比(ratio = w/h),并夹回 0-1。
    /// 注意归一化坐标的比例要预先按画布像素换算——调用方传像素比。
    public static func applyRatio(_ r: CGRect, pixelRatio: Double, canvas: CGSize) -> CGRect {
        guard pixelRatio > 0, canvas.width > 0, canvas.height > 0 else { return r }
        // 换到像素域求形状,再归一化回去,避免归一化域里比例失真。
        var pw = r.width * canvas.width
        var ph = r.height * canvas.height
        if pw / ph > pixelRatio {
            pw = ph * pixelRatio
        } else {
            ph = pw / pixelRatio
        }
        let cx = (r.midX) * canvas.width
        let cy = (r.midY) * canvas.height
        let out = CGRect(x: (cx - pw / 2) / canvas.width,
                         y: (cy - ph / 2) / canvas.height,
                         width: pw / canvas.width,
                         height: ph / canvas.height)
        return clampCrop(out)
    }
}

/// 渲染:配方 + 源文件 → 编辑产物(临时文件)。
public enum ImageEdit {
    /// 单幅像素上限:80MP 全尺寸 RGBA 上下文一步就是 320MB,叠加各渲染步
    /// 骤峰值破 GB——编辑器不是给航拍拼接图用的。
    public static let maxEditPixels = 80_000_000

    public enum Editability: Sendable {
        case ok, animated, tooLarge, unreadable
    }

    /// 编辑器能处理的输入。动图不行——逐帧编辑是另一码事,静默取首帧会
    /// 丢动画,不如明说不支持;损坏文件与超大图各有各的原因,分开报,
    /// 别把一切失败都说成"动图"。
    public static func editability(_ url: URL) -> Editability {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(src) >= 1 else { return .unreadable }
        if CGImageSourceGetCount(src) > 1 { return .animated }
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let pw = props[kCGImagePropertyPixelWidth] as? Int,
              let ph = props[kCGImagePropertyPixelHeight] as? Int else { return .unreadable }
        if pw * ph > maxEditPixels { return .tooLarge }
        return .ok
    }

    public static func editable(_ url: URL) -> Bool { editability(url) == .ok }

    /// 头部读像素尺寸,不解码。编辑器用它当画布几何基准——不能等预览
    /// 渲染完才有基准,旋转窗口期的比例/手势会用错画布。
    public static func pixelSize(of url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let pw = props[kCGImagePropertyPixelWidth] as? Int,
              let ph = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: pw, height: ph)
    }

    /// 水印文字的光学尺寸——预览与渲染共用这一个度量,谁都别估算
    /// (0.62em/字那种估法对 CJK 偏小近四成)。
    public static func watermarkTextSize(_ text: String, fontSize: Double) -> CGSize {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        return CTLineGetBoundsWithOptions(line, .useOpticalBounds).size
    }

    /// 编辑器画布用的预览:降采样解码 → 变换 → 增强 → 抠图 → 调色 → 马赛克,
    /// 不裁剪不打水印(那两样由画布叠加层所见即所得)。笔刷半径与模糊半径都
    /// 归一化到对角线,降采样不改变含义,预览与成品逐像素同构——这正是当初
    /// 把两个半径都定义成比例而不是像素的原因。
    public static func preview(source: URL, spec: EditSpec, maxPixel: Int = 1600) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(src) == 1,
              let base = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        var img = base
        if let t = transform(img, spec: spec) { img = t } else { return nil }
        if spec.enhance, let e = SmartEdit.autoEnhance(img) { img = e }
        if spec.cutout, let c = (try? SmartEdit.removeBackground(img)) ?? nil { img = c }
        // 调色在抠图之后、马赛克之前——理由见 EditSpec 头注第 3 条。
        if !spec.adjustments.isNeutral {
            guard let a = ImageAdjust.apply(spec.adjustments, to: img) else { return nil }
            img = a
        }
        if !spec.strokes.isEmpty {
            guard let m = mosaic(img, strokes: spec.strokes, style: spec.mosaicStyle) else { return nil }
            img = m
        }
        return img
    }

    /// 渲染到独立临时目录,文件名保留源名(上传以 lastPathComponent 作
    /// 展示名);格式由 ExportFormat.resolve 定——默认(auto)跟着源走,
    /// 用户显式选了就按选的来,写不出的格式与抠图的 alpha 要求各有优先级,
    /// 都写在 resolve 的头注里。
    public static func render(source: URL, spec: EditSpec) -> URL? {
        guard spec.hasEdits else { return nil }
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(src) == 1 else { return nil }
        // 全尺寸解码并顺手把 EXIF 方向烙进像素(标签活不过重绘)。
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let pw = props[kCGImagePropertyPixelWidth] as? Int,
              let ph = props[kCGImagePropertyPixelHeight] as? Int,
              pw * ph <= maxEditPixels,
              let base = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: max(pw, ph),
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }

        var img: CGImage = base
        guard let transformed = transform(img, spec: spec) else { return nil }
        img = transformed
        // 智能操作先于一切滤镜与涂抹:去背景认的是整幅画面里的主体,先涂一块
        // 马赛克会把主体糊掉,分割结果跟着错。
        if spec.enhance, let e = SmartEdit.autoEnhance(img) {
            img = e
        }
        if spec.cutout {
            // 抠不出主体时保持原图——与其给一张被胡乱挖空的图,不如什么都
            // 不做,调用方会据此提示。
            if let c = (try? SmartEdit.removeBackground(img)) ?? nil { img = c }
        }
        // 调色夹在抠图与马赛克之间:更早会让模糊/去色骗过 Vision 的主体判断,
        // 更晚会让模糊晕开遮挡块的边缘。见 EditSpec 头注第 3 条。
        if !spec.adjustments.isNeutral {
            guard let a = ImageAdjust.apply(spec.adjustments, to: img) else { return nil }
            img = a
        }
        if !spec.strokes.isEmpty {
            guard let m = mosaic(img, strokes: spec.strokes, style: spec.mosaicStyle) else { return nil }
            img = m
        }
        if let crop = spec.crop {
            let c = EditGeometry.clampCrop(crop)
            let px = CGRect(x: (c.origin.x * Double(img.width)).rounded(),
                            y: (c.origin.y * Double(img.height)).rounded(),
                            width: (c.width * Double(img.width)).rounded(),
                            height: (c.height * Double(img.height)).rounded())
            guard px.width >= 1, px.height >= 1, let cropped = img.cropping(to: px) else { return nil }
            img = cropped
        }
        if let wm = spec.watermark, !wm.text.isEmpty {
            guard let w = watermark(img, spec: wm) else { return nil }
            img = w
        }

        // 导出限宽(已乘过倍率):编辑产物是新内容,缩放它不影响秒传去重。
        // 只缩不放——倍率乘出来的目标比图还宽时什么都不做,见 effectiveMaxWidth。
        let targetWidth = spec.effectiveMaxWidth
        if targetWidth > 0, img.width > targetWidth {
            let scale = Double(targetWidth) / Double(img.width)
            let w = targetWidth, h = max(1, Int((Double(img.height) * scale).rounded()))
            if let ctx = context(w, h) {
                ctx.interpolationQuality = .high
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
                if let scaled = ctx.makeImage() { img = scaled }
            }
        }

        let sourceType = CGImageSourceGetType(src).flatMap { UTType($0 as String) }
        let format = spec.resolvedFormat(sourceType: sourceType)
        guard let uti = format.utType?.identifier else { return nil }   // resolve 不会返回 auto
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("openimg-edit-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = source.deletingPathExtension().lastPathComponent
        let out = dir.appendingPathComponent(name).appendingPathExtension(format.fileExtension)
        guard let dst = CGImageDestinationCreateWithURL(out as CFURL, uti as CFString, 1, nil) else { return nil }
        // 质量键只对有损格式有意义;PNG 给了也是被忽略,但传进去不会出错,
        // 分支反而多一条路要维护。下限 0.4:再低的 JPEG 是块状糊,用户以为
        // 自己在省流量,实际是把图毁了。
        CGImageDestinationAddImage(dst, img, [
            kCGImageDestinationLossyCompressionQuality: max(0.4, min(1, spec.exportQuality)),
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dst) else {
            try? FileManager.default.removeItem(at: dir)
            return nil
        }
        return out
    }

    // MARK: - 渲染步骤

    private static func context(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// 旋转与翻转合成一次绘制。
    ///
    /// 合并不是为了省一次重采样(90° 整数倍与镜像都是无损的像素搬运),而是
    /// 为了省一次全尺寸位图分配:8000x6000 的图每多一遍中间产物就是 192MB,
    /// 而这一步正好在管线最前端、图还没被裁小的时候。
    ///
    /// 变换定义是 **flip ∘ rotate**(先转再翻,见 EditSpec.flipHorizontal)。
    /// CGContext 的 CTM 把用户坐标映到设备坐标,连续 concat 后先应用的是最后
    /// 加的那个——所以这里必须**先**加翻转、**后**加旋转,得到的才是
    /// device = flip(rotate(p))。顺序写反了在正方形图上看不出来,在旋转过的
    /// 长方形图上会同时错方向和错轴。
    private static func transform(_ img: CGImage, spec: EditSpec) -> CGImage? {
        let q = ((spec.rotationQuarters % 4) + 4) % 4
        if q == 0, !spec.flipHorizontal, !spec.flipVertical { return img }
        let w = img.width, h = img.height
        let out = EditGeometry.rotatedSize(CGSize(width: w, height: h), quarters: q)
        guard let ctx = context(Int(out.width), Int(out.height)) else { return nil }
        // 翻转在输出坐标系里做镜像。x 轴两套坐标系一致;y 轴虽然 CG 向上而
        // 视图向下,但"整幅上下对调"这个操作本身在两套坐标下是同一件事。
        if spec.flipHorizontal {
            ctx.translateBy(x: out.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        if spec.flipVertical {
            ctx.translateBy(x: 0, y: out.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        ctx.translateBy(x: out.width / 2, y: out.height / 2)
        // CG 坐标系 y 向上,顺时针(视觉)= 负角度。
        ctx.rotate(by: -Double(q) * .pi / 2)
        ctx.draw(img, in: CGRect(x: -Double(w) / 2, y: -Double(h) / 2,
                                 width: Double(w), height: Double(h)))
        return ctx.makeImage()
    }

    private static func mosaic(_ img: CGImage, strokes: [MosaicStroke], style: MosaicStyle) -> CGImage? {
        let w = img.width, h = img.height
        let diag = (Double(w * w + h * h)).squareRoot()
        guard let ctx = context(w, h) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

        // 笔迹归一化坐标 y 向下(视图习惯),CG y 向上——翻转。
        let path = CGMutablePath()
        for s in strokes {
            guard let first = s.points.first else { continue }
            let lineWidth = max(2, s.radius * 2 * diag)
            let sub = CGMutablePath()
            sub.move(to: CGPoint(x: first.x * Double(w), y: (1 - first.y) * Double(h)))
            if s.points.count == 1 {
                // 单点也要着色:补一段极短线,strokingWithWidth 才有面积。
                sub.addLine(to: CGPoint(x: first.x * Double(w) + 0.1, y: (1 - first.y) * Double(h)))
            } else {
                for p in s.points.dropFirst() {
                    sub.addLine(to: CGPoint(x: p.x * Double(w), y: (1 - p.y) * Double(h)))
                }
            }
            path.addPath(sub.copy(strokingWithWidth: lineWidth, lineCap: .round,
                                  lineJoin: .round, miterLimit: 10))
        }
        guard !path.isEmpty else { return ctx.makeImage() }

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        switch style {
        case .solid:
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        case .pixelate:
            // 缩小再放大、关插值 = 经典像素化。格子随图幅走,截图上肉眼
            // 明确不可读。
            let cell = max(8.0, Double(max(w, h)) / 80)
            let sw = max(1, Int((Double(w) / cell).rounded())), sh = max(1, Int((Double(h) / cell).rounded()))
            guard let small = context(sw, sh) else { ctx.restoreGState(); return nil }
            small.interpolationQuality = .low
            small.draw(img, in: CGRect(x: 0, y: 0, width: sw, height: sh))
            guard let tiny = small.makeImage() else { ctx.restoreGState(); return nil }
            ctx.interpolationQuality = .none
            ctx.draw(tiny, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        ctx.restoreGState()
        return ctx.makeImage()
    }

    private static func watermark(_ img: CGImage, spec: WatermarkSpec) -> CGImage? {
        let w = img.width, h = img.height
        guard let ctx = context(w, h) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

        let fontSize = max(9, spec.scale * Double(w))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let alpha = max(0.05, min(1, spec.opacity))

        func line(_ color: CGColor) -> CTLine {
            let attrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ]
            return CTLineCreateWithAttributedString(
                NSAttributedString(string: spec.text, attributes: attrs))
        }

        let white = line(CGColor(gray: 1, alpha: alpha))
        let bounds = CTLineGetBoundsWithOptions(white, .useOpticalBounds)
        let origin = EditGeometry.watermarkOrigin(
            anchor: spec.anchor,
            textSize: bounds.size,
            canvas: CGSize(width: w, height: h),
            margin: fontSize * 0.8)

        // CTLineDraw 的 textPosition 是基线起点,不是外框左下角;补偿光学
        // 边界原点,外框才恰好落在 watermarkOrigin 算出的位置——否则顶部
        // 锚点会下沉约半个字号,降部字符在底部锚压进边距。
        let pen = CGPoint(x: origin.x - bounds.origin.x, y: origin.y - bounds.origin.y)
        // 影子再正字:白字在亮背景上会隐形,一枚低透明度黑影保住可读性。
        let shadow = line(CGColor(gray: 0, alpha: alpha * 0.7))
        let off = max(1, fontSize / 24)
        ctx.textPosition = CGPoint(x: pen.x + off, y: pen.y - off)
        CTLineDraw(shadow, ctx)
        ctx.textPosition = pen
        CTLineDraw(white, ctx)
        return ctx.makeImage()
    }
}
