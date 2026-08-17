import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

/// 色彩调整、滤镜预设与导出选项——EditSpec 的"非几何"那一半。
///
/// 与 SmartEdit 同一条纪律:全部离线,不外发。这里六个参数刻意都是 Core Image
/// 内置滤镜的直接映射,不做自研调色曲线——自研的那种"胶片感"参数没法解释,
/// 用户拖到一半不知道自己在调什么,而 CIColorControls 的三个量纲是所有修图
/// 软件通用的。

/// 六个连续色彩参数。每个都有明确的中性值,全中性 == 这一步整个跳过。
///
/// 中性值不统一取 0 是刻意的:亮度/色相/复古/模糊是"叠加量",中性是 0;
/// 对比/饱和是"乘数",中性是 1。跟着 Core Image 的量纲走,别为了整齐把乘数
/// 重新参数化成 0 起点——那样每次渲染都要换算一遍,还得在两处保持一致。
public struct ColorAdjustments: Sendable, Equatable {
    /// 亮度叠加量,CIColorControls 原生量纲。中性 0。
    public var brightness: Double = 0
    /// 对比度乘数,CIColorControls 原生量纲。中性 1。
    public var contrast: Double = 1
    /// 饱和度乘数,CIColorControls 原生量纲。0 = 灰度。中性 1。
    public var saturation: Double = 1
    /// 色相旋转,弧度。中性 0。
    public var hue: Double = 0
    /// 复古(棕调)强度 0-1。中性 0。
    public var sepia: Double = 0
    /// 模糊强度 0-1。中性 0。
    ///
    /// 存的是强度不是像素半径:半径按画面对角线折算(见 blurRadiusFraction),
    /// 与 MosaicStroke.radius 同一条约定——缩放不改变观感,1600px 预览和
    /// 全尺寸成品因此逐像素同构,不用为预览另配一套参数。
    public var blur: Double = 0

    public init() {}

    public init(brightness: Double = 0, contrast: Double = 1, saturation: Double = 1,
                hue: Double = 0, sepia: Double = 0, blur: Double = 0) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.hue = hue
        self.sepia = sepia
        self.blur = blur
    }

    public static let neutral = ColorAdjustments()

    // 滑块范围。故意比 Core Image 的合法区间窄:contrast 允许到 0 会把图压成
    // 一片灰,允许负数会反色——那不是"调整"是"事故",没有哪个用户是奔着
    // 拖出一张灰卡去的。
    public static let brightnessRange: ClosedRange<Double> = -0.5...0.5
    public static let contrastRange: ClosedRange<Double> = 0.5...1.8
    public static let saturationRange: ClosedRange<Double> = 0...2
    public static let hueRange: ClosedRange<Double> = -.pi ... .pi
    public static let sepiaRange: ClosedRange<Double> = 0...1
    public static let blurRange: ClosedRange<Double> = 0...1

    /// 模糊强度 1.0 对应画面对角线的 2%。
    ///
    /// 2% 是从"能糊到认不出人脸、但还看得出构图"试出来的:4000x3000 的图
    /// 对角线 5000px,满强度半径 100px。再大就只剩色块,滑块后半段全是废行程。
    public static let blurRadiusFraction = 0.02

    /// 判"等于中性"的容差。滑块吐出的是连续浮点,用户拖回中间落在 0.9999
    /// 是常态;严格 == 会让"我明明调回去了"的图白跑一遍 Core Image。
    public static let epsilon = 1e-4

    /// 全中性——渲染管线据此整段跳过,hasEdits 也据此不为真。
    public var isNeutral: Bool {
        abs(brightness) < Self.epsilon
            && abs(contrast - 1) < Self.epsilon
            && abs(saturation - 1) < Self.epsilon
            && abs(hue) < Self.epsilon
            && sepia < Self.epsilon
            && blur < Self.epsilon
    }

    /// 把落在容差内的分量吸附到精确中性值。
    ///
    /// isNeutral 只回答"整体要不要跑",这个负责让 Equatable 与预设匹配可靠:
    /// 0.99999 的饱和度和 1.0 在合成的 == 下是两个值,不吸附的话"选了黑白又
    /// 手动拖回去"会永远匹配不上任何预设,界面上没有一项高亮。
    public func snapped() -> ColorAdjustments {
        var a = self
        if abs(a.brightness) < Self.epsilon { a.brightness = 0 }
        if abs(a.contrast - 1) < Self.epsilon { a.contrast = 1 }
        if abs(a.saturation - 1) < Self.epsilon { a.saturation = 1 }
        if abs(a.hue) < Self.epsilon { a.hue = 0 }
        if a.sepia < Self.epsilon { a.sepia = 0 }
        if a.blur < Self.epsilon { a.blur = 0 }
        return a
    }

    /// 夹进滑块范围。界面之外还有配置文件和监控目录那条路会直接构造 spec,
    /// 渲染前统一夹一次比在每个入口各夹一次可靠。
    public func clamped() -> ColorAdjustments {
        ColorAdjustments(
            brightness: min(max(brightness, Self.brightnessRange.lowerBound), Self.brightnessRange.upperBound),
            contrast: min(max(contrast, Self.contrastRange.lowerBound), Self.contrastRange.upperBound),
            saturation: min(max(saturation, Self.saturationRange.lowerBound), Self.saturationRange.upperBound),
            hue: min(max(hue, Self.hueRange.lowerBound), Self.hueRange.upperBound),
            sepia: min(max(sepia, Self.sepiaRange.lowerBound), Self.sepiaRange.upperBound),
            blur: min(max(blur, Self.blurRange.lowerBound), Self.blurRange.upperBound))
    }

    /// 与另一组调整在容差内相等。预设匹配用,不用合成的 ==(浮点严格相等)。
    public func nearlyEquals(_ other: ColorAdjustments, tolerance: Double = 1e-6) -> Bool {
        abs(brightness - other.brightness) < tolerance
            && abs(contrast - other.contrast) < tolerance
            && abs(saturation - other.saturation) < tolerance
            && abs(hue - other.hue) < tolerance
            && abs(sepia - other.sepia) < tolerance
            && abs(blur - other.blur) < tolerance
    }
}

/// 滤镜预设。
///
/// 预设**不是**另一条渲染路径,只是 ColorAdjustments 的一组取值:选中即把这
/// 组值写进 spec.adjustments,之后用户接着拖滑块就是普通的微调,不存在"预设
/// 模式"和"手动模式"两套状态要同步。反过来,当前调整值恰好等于某个预设时
/// matching() 会认出它——界面据此高亮,而唯一的真值来源始终是那六个数。
public enum FilterPreset: String, Sendable, CaseIterable, Identifiable {
    case none, mono, vivid, warm, cool, vintage

    public var id: String { rawValue }

    public var adjustments: ColorAdjustments {
        switch self {
        case .none:
            ColorAdjustments.neutral
        case .mono:
            // 去色后补一点对比:直接把饱和归零的灰图普遍发闷,黑白照片的
            // 观感本来就来自反差而不是"没有颜色"。
            ColorAdjustments(contrast: 1.12, saturation: 0)
        case .vivid:
            ColorAdjustments(brightness: 0.02, contrast: 1.12, saturation: 1.45)
        case .warm:
            // 暖色靠轻度 sepia 而不是色相旋转:sepia 是朝棕调**混合**,肤色
            // 只会更暖;色相旋转是整个色轮转动,同样幅度下天空会先垮掉。
            // 混合会压低整体饱和,补 1.15 回来。
            ColorAdjustments(saturation: 1.15, sepia: 0.25)
        case .cool:
            // 冷色没有 sepia 那样的现成滤镜,只能用小角度色相偏移近似。
            // -0.12 rad ≈ -7°:再大肤色开始发绿,这是六个参数能给到的上限,
            // 想要真正的色温轴得引入 CITemperatureAndTint,那会多出一个第七
            // 参数、且与 hue 的效果互相打架。
            ColorAdjustments(brightness: 0.02, saturation: 0.92, hue: -0.12)
        case .vintage:
            ColorAdjustments(brightness: 0.03, contrast: 0.9, saturation: 0.85, sepia: 0.55)
        }
    }

    /// 认出当前调整对应哪个预设;都不匹配(用户微调过)返回 nil = 自定义。
    public static func matching(_ adjustments: ColorAdjustments) -> FilterPreset? {
        allCases.first { $0.adjustments.nearlyEquals(adjustments) }
    }
}

/// 导出倍率。
///
/// 只与 exportMaxWidth 相乘,不单独作用于原始尺寸——见 EditSpec.effectiveMaxWidth
/// 头注里的理由。
public enum ExportScale: Double, Sendable, CaseIterable, Identifiable {
    case x1 = 1, x1_5 = 1.5, x2 = 2, x3 = 3

    public var id: Double { rawValue }
    public var label: String { self == .x1_5 ? "1.5x" : "\(Int(rawValue))x" }
}

/// 输出格式。auto = 保持原格式。
public enum ExportFormat: String, Sendable, CaseIterable, Identifiable {
    case auto, jpeg, png, webp, heic

    public var id: String { rawValue }

    /// auto 没有对应的具体类型——它要先经 resolve() 落到某个真格式。
    public var utType: UTType? {
        switch self {
        case .auto: nil
        case .jpeg: .jpeg
        case .png: .png
        case .webp: .webP
        case .heic: .heic
        }
    }

    public var fileExtension: String {
        switch self {
        case .auto: "png"   // 兜底,正常路径上 auto 已被 resolve 掉
        case .jpeg: "jpg"
        case .png: "png"
        case .webp: "webp"
        case .heic: "heic"
        }
    }

    /// 能不能存透明通道。JPEG 不能——抠图产物落到 JPEG 会把透明填成黑色。
    public var supportsAlpha: Bool { self != .jpeg }

    /// 有损编码,吃 exportQuality;PNG 不吃(给了也没用)。
    public var isLossy: Bool { self == .jpeg || self == .webp || self == .heic }

    /// 本机 ImageIO 实际能**写**的格式。
    ///
    /// 必须运行期问,不能照着文档写死:ImageIO 从 macOS 11 起能读 WebP,但到
    /// 目前为止**写**不了(本机实测 CGImageDestinationCopyTypeIdentifiers 里
    /// 没有 org.webmproject.webp)。哪天系统补上了,这里自动就通了,不用改码。
    /// auto 不是真格式,不参与。
    public static let writable: Set<ExportFormat> = {
        let ids = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        return Set(allCases.filter { f in
            guard let t = f.utType else { return false }
            return ids.contains(t.identifier)
        })
    }()

    /// 把用户的选择落到一个真能写出去的格式。
    ///
    /// 冲突时的优先级——**alpha > 可写性 > 用户选择 > 源格式**:
    ///
    ///  1. 源格式最弱:auto 的意思就是"没意见,跟着源走",任何显式选择都盖过它。
    ///  2. 可写性盖过用户选择:选了 WebP 而本机写不了,只能换一个。宁可换格式
    ///     也不能让 render 返回 nil——那对用户表现为"点了导出什么都没发生"。
    ///  3. alpha 最强,盖过一切:抠图产物落到不带 alpha 的格式就是一张黑底废图,
    ///     用户的格式选择在这里必须让位。回退目标固定 PNG——它一定可写,而
    ///     HEIC/WebP 就算标称支持 alpha 也未必在每台机器上写得出来。
    ///
    /// writable 可注入,便于在没有真编码器的环境里断言这套优先级。
    public static func resolve(requested: ExportFormat,
                               sourceType: UTType?,
                               requiresAlpha: Bool,
                               writable: Set<ExportFormat> = ExportFormat.writable) -> ExportFormat {
        // 1) auto → 跟着源格式
        var f = requested
        if f == .auto {
            if let t = sourceType {
                if t.conforms(to: .jpeg) { f = .jpeg }
                else if t.conforms(to: .heic) || t.conforms(to: .heif) { f = .heic }
                else if t.conforms(to: .webP) { f = .webp }
                else { f = .png }
            } else {
                f = .png
            }
        }
        // 2) 写不了就换:有损的换 JPEG(体积量级相当),无损的换 PNG
        if !writable.contains(f) {
            f = f.isLossy ? .jpeg : .png
            if !writable.contains(f) { f = .png }
        }
        // 3) 需要 alpha 而这个格式存不了 → PNG,不再商量
        if requiresAlpha, !f.supportsAlpha { f = .png }
        return f
    }
}

/// 色彩调整的渲染实现。独立于 ImageEdit 是因为它是纯 Core Image 的一段,
/// 与 ImageEdit 那套 CGContext 绘制没有共享状态。
public enum ImageAdjust: Sendable {
    /// 共享一个 CIContext(SDK 已把它标为 Sendable,不需要 unsafe 逃生口)。
    ///
    /// 共用而不是每次新建:建一个 CIContext 要起一条 Metal 命令队列,监控目录
    /// 批量打水印时每张新建一次,开销比调色本身还大。
    private static let ciContext = CIContext()

    /// 应用一组调整;全中性时原样返回(**不**重编码,调用方可以无脑调用)。
    ///
    /// 滤镜顺序 色彩控制 → 色相 → 复古 → 模糊,理由:
    ///  - 色相在 sepia 之前:sepia 的输出已经是单一棕调,再转色相会把它拧成
    ///    蓝调/绿调,滑块行为完全反直觉;而先转色相再混棕,两者是叠加关系。
    ///  - 饱和在色相之前:饱和归零(黑白)之后色相无处可转,这个"后一个参数
    ///    吃掉前一个"的关系正是用户预期的——选了黑白,色相滑块自然失效。
    ///  - 模糊最后:它是空间域运算,放在任何颜色运算之前都会被后面的对比度
    ///    再放大一次边缘过渡带,观感是"糊得发脏"。
    public static func apply(_ adjustments: ColorAdjustments, to image: CGImage) -> CGImage? {
        let adj = adjustments.clamped()
        guard !adj.isNeutral else { return image }

        var ci = CIImage(cgImage: image)
        let extent = ci.extent

        // 三个分量任一非中性就走 CIColorControls——它一次算完,拆成三次没意义。
        if abs(adj.brightness) >= ColorAdjustments.epsilon
            || abs(adj.contrast - 1) >= ColorAdjustments.epsilon
            || abs(adj.saturation - 1) >= ColorAdjustments.epsilon {
            let f = CIFilter.colorControls()
            f.inputImage = ci
            f.brightness = Float(adj.brightness)
            f.contrast = Float(adj.contrast)
            f.saturation = Float(adj.saturation)
            guard let out = f.outputImage else { return nil }
            ci = out
        }
        if abs(adj.hue) >= ColorAdjustments.epsilon {
            let f = CIFilter.hueAdjust()
            f.inputImage = ci
            f.angle = Float(adj.hue)
            guard let out = f.outputImage else { return nil }
            ci = out
        }
        if adj.sepia >= ColorAdjustments.epsilon {
            let f = CIFilter.sepiaTone()
            f.inputImage = ci
            f.intensity = Float(adj.sepia)
            guard let out = f.outputImage else { return nil }
            ci = out
        }
        if adj.blur >= ColorAdjustments.epsilon {
            let diag = (Double(image.width * image.width + image.height * image.height)).squareRoot()
            let radius = adj.blur * diag * ColorAdjustments.blurRadiusFraction
            let f = CIFilter.gaussianBlur()
            // clampedToExtent:高斯核在画面边上要取画外的样,不延拓的话边缘会
            // 朝透明衰减,成品四周一圈发暗——先延拓再裁回原 extent。
            f.inputImage = ci.clampedToExtent()
            f.radius = Float(radius)
            guard let out = f.outputImage else { return nil }
            ci = out.cropped(to: extent)
        }

        // 输出保持 RGBA8 + sRGB:与 ImageEdit.context() 同一套,免得调色前后
        // 在管线中途换了色彩空间,后续 CGContext 绘制时被隐式转换一遍。
        return ciContext.createCGImage(ci, from: extent, format: .RGBA8,
                                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }
}
