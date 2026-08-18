import Foundation
import ImageIO
import CoreGraphics
import CoreText
import UniformTypeIdentifiers

/// 上传前编辑的"配方"。渲染顺序:
///
///   变换(旋转+翻转) → 自动增强 → 抠图 → 色彩调整 → 马赛克 → 标注 → 裁剪 → 水印 → 导出缩放
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
///  4. **标注压在马赛克之上、裁剪之前**。压在马赛克之上:标注是"表达",
///     被遮蔽层盖住就白画了。在裁剪之前:标注和笔迹用的是同一套坐标——
///     归一化到**整幅变换后画面**(编辑器画布显示的就是整幅,裁剪只是一层
///     取景框),所以两者必须在同一时刻落到像素上;裁掉画外的标注,正是
///     用户在画布上看到的结果。
///  5. **裁剪在调色之后**。高斯模糊要取画外的样(见 ImageAdjust.apply);先裁
///     的话裁剪边就成了画面边,四周会多一圈晕边。代价是对全尺寸图做模糊,
///     慢一点,但这是正确性换的。
///  6. **水印最后**。署名不该被调色、被模糊、被裁掉,也不该被标注盖住。
///  7. **导出缩放收尾**,纯重采样,不改内容。
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
    /// 标注(圈、箭头、文字…)。有序,后面的盖前面的,撤销 == removeLast。
    ///
    /// 和 strokes 一样归一化到整幅变换后画面,所以旋转/翻转时由 EditGeometry
    /// 一并搬运;它也和 strokes 一样计入 hasEdits——只画了标注什么都没改的
    /// 那种编辑曾经会被空转闸门当成"没编辑"而静默上传原图。
    public var annotations: [Annotation] = []
    public var watermark: WatermarkSpec?
    /// 本机智能操作。见头注第 2、3 条。
    public var enhance = false
    public var cutout = false
    /// 六个连续色彩参数。全中性时整段跳过,不进渲染管线。
    public var adjustments = ColorAdjustments()
    /// 导出质量。只作用于编辑产物——编辑过的图本来就是新内容,不存在破坏
    /// 秒传去重的问题(未编辑的原件仍走原样上传,见 LocalResize 头注)。
    public var exportQuality: Double = 0.92
    /// 导出前限宽及其**来源**。来源决定倍率吃不吃得动它,见 effectiveMaxWidth。
    public var widthLimit: WidthLimit = .none
    /// 导出前限宽的数值,0 不限。只对编辑产物生效。
    ///
    /// 写它等于"用户手填了一个宽度"(→ .manual);平台预设那条路要写
    /// widthLimit = .preset(w),别绕这个 setter,否则倍率会乘穿锁定的规格。
    public var exportMaxWidth: Int {
        get { widthLimit.width }
        set { widthLimit = newValue > 0 ? .manual(newValue) : .none }
    }
    /// 导出倍率。**只与手填的限宽相乘**,见 effectiveMaxWidth。
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
    ///
    /// 而平台预设锁定的宽度(.preset)**不吃倍率**:上面那套"多宽 × 几倍屏"
    /// 的语义只对用户自己填的宽度成立。选了「小红书 1080×1440」的人要的就是
    /// 1080——再乘个 2x 得到 2160×2880,既不是那个平台的规格,也白传一倍字节。
    public var effectiveMaxWidth: Int {
        switch widthLimit {
        case .none:
            return 0
        case .preset(let w):
            return w > 0 ? w : 0
        case .manual(let w):
            guard w > 0 else { return 0 }
            return max(1, Int((Double(w) * exportScale.rawValue).rounded()))
        }
    }

    /// 有任何会改变像素(或改变文件格式)的操作。
    ///
    /// exportScale 不单独计入:没有限宽时它本来就无效,有限宽时 exportMaxWidth
    /// 已经把这条算进来了。exportFormat 计入是因为换格式本身就是要写一份新
    /// 文件——即便它碰巧和源格式相同也照算:EditSpec 不知道源是什么格式,
    /// 宁可多编一次,也不要静默吞掉用户明确点下的选择。
    public var hasEdits: Bool {
        rotationQuarters % 4 != 0 || flipHorizontal || flipVertical
            || crop != nil || !strokes.isEmpty || !annotations.isEmpty
            || watermark?.isRenderable == true
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

/// 导出限宽及其来源。
///
/// 光存一个 Int 是不够的:同样是"限宽 1080",用户手填的和平台预设锁定的,
/// 在遇到导出倍率时要走两条相反的路(见 EditSpec.effectiveMaxWidth)。把来源
/// 编进类型里,而不是在渲染处另设一个 isPreset 布尔——布尔会和数值分头传、
/// 分头忘,类型不会。
public enum WidthLimit: Sendable, Equatable {
    /// 不限宽。
    case none
    /// 用户手填的宽度。倍率乘在它上面。
    case manual(Int)
    /// 平台预设(SizeIntent.exact)锁定的像素宽。倍率对它无效。
    case preset(Int)

    /// 数值,不限时为 0。
    public var width: Int {
        switch self {
        case .none: 0
        case .manual(let w), .preset(let w): max(0, w)
        }
    }

    /// 是否来自平台预设。界面据此把倍率选择器灰掉,而不是让用户拖完才发现没反应。
    public var isPreset: Bool {
        if case .preset = self { return true }
        return false
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

/// 水印是一行字,还是一枚图。
///
/// 拆成枚举而不是"text 空了就当图片模式":两种模式的 scale 量纲不同(见
/// defaultScale),而"现在该按哪个默认值取"这件事,一个空字符串回答不了。
public enum WatermarkKind: String, Sendable, Equatable, CaseIterable, Codable {
    case text, image

    /// 这一模式下 scale 的默认值。
    ///
    /// 差着四倍,因为两个数量的东西根本不同:文字模式的 scale 是**字号**相对
    /// 画面宽度的比例,0.03 在 1200px 宽的图上是 36pt 的字,读得清;图片模式的
    /// scale 是 **logo 整幅宽度**相对画面宽度的比例,同样按 0.03 贴上去只有
    /// 36px 宽——一枚 logo 缩到这个尺寸基本看不见。所以两种模式各存各的数,
    /// 切模式不该把对方的数字带过来。
    public var defaultScale: Double { self == .text ? 0.03 : 0.12 }

    /// 这一模式下 scale 的合法区间。渲染与界面共用同一个来源,免得滑块拖得到
    /// 渲染会夹掉的地方——那种不一致的表现是"拖到底了还是没变大"。
    public var scaleRange: ClosedRange<Double> {
        self == .text ? 0.015...0.06 : 0.04...0.40
    }

    public func clampScale(_ v: Double) -> Double {
        min(max(v, scaleRange.lowerBound), scaleRange.upperBound)
    }
}

public struct WatermarkSpec: Sendable, Equatable {
    /// 文字还是图片。
    public var kind: WatermarkKind
    public var text: String
    /// 图片模式的 logo,PNG 字节。
    ///
    /// 带的是字节而不是磁盘路径:这份配方要跨并发边界交给渲染任务,也会被
    /// 监控目录那条路攒在队列里等上几分钟。路径意味着"渲染那一刻文件还得在、
    /// 内容还得没变"——用户在设置里换掉 logo,排在队里的那几张就会拿到新的
    /// 那枚,而他以为自己换的是以后。字节是自足的,几百 KB 相对于被渲染的
    /// 整幅图微不足道。
    ///
    /// 也不带 CGImage:那样 Equatable 就无从实现,而"logo 换了没有"正是这份
    /// 配方要能回答的问题(编辑器靠它决定要不要重渲染)。
    public var imagePNG: Data?
    /// 九宫格锚点 0-8,行优先:0 左上、4 居中、8 右下。
    public var anchor: Int
    public var opacity: Double
    /// 比例。**含义随 kind 变**:文字模式是字号 ÷ 画面宽度,图片模式是 logo
    /// 宽度 ÷ 画面宽度。见 WatermarkKind.defaultScale。
    public var scale: Double

    public init(text: String, anchor: Int = 8, opacity: Double = 0.45,
                scale: Double = WatermarkKind.text.defaultScale) {
        self.kind = .text
        self.text = text
        self.imagePNG = nil
        self.anchor = anchor
        self.opacity = opacity
        self.scale = scale
    }

    public init(imagePNG: Data, anchor: Int = 8, opacity: Double = 0.45,
                scale: Double = WatermarkKind.image.defaultScale) {
        self.kind = .image
        self.text = ""
        self.imagePNG = imagePNG
        self.anchor = anchor
        self.opacity = opacity
        self.scale = scale
    }

    /// 这份配方渲染得出东西吗。
    ///
    /// 渲染管线、hasEdits、界面上那个开关三处都问它。分头判(一处看 text 非空、
    /// 一处看 imagePNG 非空)的下场是模式切换时三处的答案对不上:开关亮着、
    /// hasEdits 为真、渲染却什么都不画,用户拿到一张"编辑过"但看不出区别的图。
    public var isRenderable: Bool {
        switch kind {
        case .text: !text.trimmingCharacters(in: .whitespaces).isEmpty
        case .image: !(imagePNG ?? Data()).isEmpty
        }
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
        s.annotations = AnnotationGeometry.rotateQuarterCW(s.annotations)
        return s
    }

    /// 把整份配方随画面水平翻转:切换标志,并把已有笔迹/标注/裁剪框一起翻
    /// 过去(涂在鼻子上的马赛克翻完还得在鼻子上,圈住左边那个人的圈翻完还得
    /// 圈着他)。垂直翻转同理。
    public static func flipSpecH(_ spec: EditSpec) -> EditSpec {
        var s = spec
        s.flipHorizontal.toggle()
        s.crop = s.crop.map(flipH)
        s.strokes = s.strokes.map { MosaicStroke(points: $0.points.map(flipH), radius: $0.radius) }
        s.annotations = AnnotationGeometry.flipH(s.annotations)
        return s
    }

    public static func flipSpecV(_ spec: EditSpec) -> EditSpec {
        var s = spec
        s.flipVertical.toggle()
        s.crop = s.crop.map(flipV)
        s.strokes = s.strokes.map { MosaicStroke(points: $0.points.map(flipV), radius: $0.radius) }
        s.annotations = AnnotationGeometry.flipV(s.annotations)
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

    /// 图片水印在画面上的显示尺寸:宽度按画面宽度的比例定,高度保住 logo 的
    /// 原始长宽比。
    ///
    /// 渲染、编辑器叠加层、设置页那块小预览三处共用这一个函数。分头算的下场
    /// 文字水印当年已经付过一次:预览按 0.62em/字估宽,CJK 偏小近四成,界面
    /// 里看着刚好、传上去偏了一大截(见 ImageEdit.watermarkTextSize)。
    ///
    /// 下限 8px:再小的 logo 只剩几个像素,贴上去是一撮噪点而不是署名。
    public static func watermarkImageSize(logo: CGSize, canvasWidth: Double,
                                          scale: Double) -> CGSize {
        guard logo.width > 0, logo.height > 0, canvasWidth > 0 else { return .zero }
        let w = max(8, (canvasWidth * WatermarkKind.image.clampScale(scale)).rounded())
        return CGSize(width: w, height: max(8, (w * logo.height / logo.width).rounded()))
    }

    /// 图片水印到画面边的留白。
    ///
    /// 按画面短边算,不按 logo 算:图片模式的 scale 能拖到画面的四成宽,按
    /// logo 算出来的边距会随着 logo 变大而变大,一路把它推到画面中央——而
    /// 用户选的锚点是"右下角"。文字模式那边按字号算是另一回事:字号本身就
    /// 被限制在画面宽度的百分之几以内,不会跑出这个量级。
    public static func watermarkImageMargin(canvas: CGSize) -> Double {
        min(canvas.width, canvas.height) * 0.03
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

    /// 画布内**最大**的给定比例矩形,尽量以 center 为中心(顶边就贴边)。
    ///
    /// 换比例时必须用这个,而不是拿当前裁剪框做增量重塑:重塑只会朝一个方向
    /// 削(applyRatio 两个分支都是"把长的那边削到比例"),于是"16:9 → 1:1 →
    /// 16:9"回不到原来的框,同一个比例连点两次框还会继续变小,用户只能靠
    /// 「清除裁剪」才能救回来。换比例是**换一个新构图**,不是在旧框上再削一刀,
    /// 所以基准是整幅画布;保留中心是为了不让画面焦点跳走。
    public static func fitRatio(pixelRatio: Double, canvas: CGSize,
                                center: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> CGRect {
        let fullFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
        guard pixelRatio > 0, canvas.width > 0, canvas.height > 0 else { return fullFrame }
        // 像素域求内接矩形:归一化域里"比例"会被画布长宽比扭曲。
        var pw = canvas.width
        var ph = pw / pixelRatio
        if ph > canvas.height {
            ph = canvas.height
            pw = ph * pixelRatio
        }
        let w = min(1, pw / canvas.width), h = min(1, ph / canvas.height)
        return CGRect(x: min(max(center.x - w / 2, 0), 1 - w),
                      y: min(max(center.y - h / 2, 0), 1 - h),
                      width: w, height: h)
    }

    /// 以中心为锚把矩形调整为给定宽高比(ratio = w/h),并夹回 0-1。
    /// 注意归一化坐标的比例要预先按画布像素换算——调用方传像素比。
    ///
    /// 这一版只削不放,适合"已经定好一个框、要把它捏成某个比例"的场合;
    /// 换比例请用 fitRatio,理由写在那儿。
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

    /// 头部读**显示**尺寸(已套用 EXIF 方向),不解码。编辑器用它当画布几何
    /// 基准——不能等预览渲染完才有基准,旋转窗口期的比例/手势会用错画布。
    ///
    /// 必须套方向:preview 与 render 都带 kCGImageSourceCreateThumbnailWithTransform,
    /// 也就是把方向烙进像素、竖拍照片的画布宽高是互换过的。而 kCGImagePropertyPixelWidth
    /// 给的是**存储**尺寸,orientation=6 的手机竖拍返回的是转置的那一组。两者
    /// 不一致时,比例裁剪和尺寸预设算出来的框全是错的——手机竖拍是常态,
    /// 这条路上的图比横拍还多。
    public static func pixelSize(of url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let pw = props[kCGImagePropertyPixelWidth] as? Int,
              let ph = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        // EXIF 方向 5-8 都含 90° 分量(转置),1-4 只是镜像/180°,不换宽高。
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(orientation)
            ? CGSize(width: ph, height: pw)
            : CGSize(width: pw, height: ph)
    }

    /// 绘制与输出用的色彩空间:源图自己的空间当得了输出就跟着它,否则 sRGB。
    ///
    /// 不一律 sRGB 的理由:纯裁剪走 CGImage.cropping,天然保留原空间;而调色/
    /// 马赛克/水印这些要重绘的步骤一旦钉死 sRGB,同一张 Display P3 的图"只动
    /// 一点亮度"就把广色域截掉了——晚霞、荧光色的衣服、截图里的品牌色会肉眼
    /// 可见地掉一档。"调不调色决定色域"这件事没法向用户解释。
    ///
    /// 只认 RGB 且能当输出的空间:灰度/CMYK/索引色配 RGBA8 上下文建不出来,
    /// 建不出来整条管线就返回 nil。扩展范围空间(extendedSRGB 之类)配 8 位
    /// 整型同样是非法组合,一并退回 sRGB。
    static func drawingSpace(_ image: CGImage) -> CGColorSpace {
        let fallback = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let space = image.colorSpace, space.model == .rgb, space.supportsOutput else {
            return fallback
        }
        if let name = space.name as String?, name.localizedCaseInsensitiveContains("extended") {
            return fallback
        }
        return space
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

    /// 一份图片字节 → CGImage。水印图那条路上到处要它(存的时候归一化、读的
    /// 时候渲染、判断透明度、抠背景),而这段三行代码抄四遍必然有一遍忘了
    /// `CGImageSourceCreateWithData` 会对损坏的字节返回 nil。
    public static func decode(_ data: Data) -> CGImage? {
        guard !data.isEmpty, let src = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(src) > 0 else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// 这张图**真的**用上透明通道了吗。
    ///
    /// 不能只看 alphaInfo:水印图在入库时一律重编成 PNG(见 WatermarkStore),
    /// 而 PNG 总是带 alpha 通道的——一张 JPEG 转过来之后 alphaInfo 说"有
    /// alpha",每个像素却都是 255。要回答的问题其实是"贴上去会不会是个不透明
    /// 方块",那只能数像素。
    ///
    /// 数得起:水印图在存的时候就被限制在 WatermarkStore.maxSide 之内,最坏
    /// 情况是一次 1024×1024 的扫描。
    ///
    /// 阈值取 250 而不是 255:PNG 重编码、色彩空间转换都可能让本该 255 的
    /// alpha 抖到 254,而那不是"用户给了张透明图"的意思。
    public static func hasTransparency(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false   // 连通道都没有,不必数
        default:
            break
        }
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return false }
        // 自己指定 bytesPerRow,不让 CG 去补齐:补齐后每行末尾会多出几个字节
        // 的填充,按 w*4 的步长扫过去就会把填充读成像素。
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              ctx.bytesPerRow == w * 4 else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let base = ctx.data else { return false }
        let p = base.assumingMemoryBound(to: UInt8.self)
        for i in stride(from: 3, to: w * h * 4, by: 4) where p[i] < 250 {
            return true
        }
        return false
    }

    /// 预览底图的"生成键"。相等就说明缓存的底图还能用,只需重跑
    /// applyAdjustments——它列的正是 prepareBase 会读的每一个输入。
    ///
    /// 单独建一个类型而不是让调用方自己比几个字段:漏比一个(比如 cutout)
    /// 的表现是"关掉抠图预览没变",而这种缓存 bug 只在特定操作顺序下出现,
    /// 极难在界面上复现。
    public struct PreviewBaseKey: Sendable, Equatable {
        public var source: URL
        public var rotationQuarters: Int
        public var flipHorizontal: Bool
        public var flipVertical: Bool
        public var enhance: Bool
        public var cutout: Bool
        public var maxPixel: Int

        public init(source: URL, spec: EditSpec, maxPixel: Int = 1600) {
            self.source = source
            self.rotationQuarters = ((spec.rotationQuarters % 4) + 4) % 4
            self.flipHorizontal = spec.flipHorizontal
            self.flipVertical = spec.flipVertical
            self.enhance = spec.enhance
            self.cutout = spec.cutout
            self.maxPixel = maxPixel
        }
    }

    /// 预览的**贵**的那一半:降采样解码 → 变换 → 增强 → 抠图。
    ///
    /// 和 applyAdjustments 拆开,因为两半的触发频率差着两个数量级:调色是
    /// 连续滑块,拖一次能来几十帧,而这半边每帧都要重新解码整张图、重跑一遍
    /// Vision 的前景分割(几百毫秒起)。调用方按 PreviewBaseKey 缓存这半边的
    /// 结果,滑块就只付得起的那部分钱。
    public static func prepareBase(source: URL, spec: EditSpec, maxPixel: Int = 1600) -> CGImage? {
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
        return img
    }

    /// 预览的**便宜**的那一半:调色 → 马赛克 → 标注。全部只依赖入参与 spec,
    /// 拿同一张 base 重复调用是安全的(CGImage 不可变)。
    public static func applyAdjustments(_ base: CGImage, spec: EditSpec) -> CGImage? {
        var img = base
        // 调色在抠图之后、马赛克之前——理由见 EditSpec 头注第 3 条。
        if !spec.adjustments.isNeutral {
            guard let a = ImageAdjust.apply(spec.adjustments, to: img) else { return nil }
            img = a
        }
        if !spec.strokes.isEmpty {
            guard let m = mosaic(img, strokes: spec.strokes, style: spec.mosaicStyle) else { return nil }
            img = m
        }
        // 标注压在马赛克之上——见 EditSpec 头注第 4 条。
        if !spec.annotations.isEmpty {
            img = renderAnnotations(spec.annotations, on: img)
        }
        return img
    }

    /// 编辑器画布用的预览:降采样解码 → 变换 → 增强 → 抠图 → 调色 → 马赛克 →
    /// 标注,不裁剪不打水印(那两样由画布叠加层所见即所得)。笔刷半径、模糊
    /// 半径与标注线宽都归一化到对角线,降采样不改变含义,预览与成品逐像素
    /// 同构——这正是当初把这些量都定义成比例而不是像素的原因。
    ///
    /// 一次性路径(监控目录、批处理)直接用它;交互式的调用方请拆开用
    /// prepareBase + applyAdjustments 并缓存 base。
    public static func preview(source: URL, spec: EditSpec, maxPixel: Int = 1600) -> CGImage? {
        guard let base = prepareBase(source: source, spec: spec, maxPixel: maxPixel) else { return nil }
        return applyAdjustments(base, spec: spec)
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
        // 标注在裁剪之前:它和笔迹用同一套坐标(整幅变换后画面),画布上看到
        // 什么、裁剪框留下什么,成品就是什么。见 EditSpec 头注第 4 条。
        if !spec.annotations.isEmpty {
            img = renderAnnotations(spec.annotations, on: img)
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
        if let wm = spec.watermark, wm.isRenderable {
            guard let w = watermark(img, spec: wm) else { return nil }
            img = w
        }

        // 导出限宽(已乘过倍率):编辑产物是新内容,缩放它不影响秒传去重。
        // 只缩不放——倍率乘出来的目标比图还宽时什么都不做,见 effectiveMaxWidth。
        let targetWidth = spec.effectiveMaxWidth
        if targetWidth > 0, img.width > targetWidth {
            let scale = Double(targetWidth) / Double(img.width)
            let w = targetWidth, h = max(1, Int((Double(img.height) * scale).rounded()))
            if let ctx = context(w, h, like: img) {
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

    /// 中间画布。色彩空间跟着被绘制的图走(`like:`),否则每经过一个重绘步骤
    /// 广色域源就被压回 sRGB 一次——见 drawingSpace。
    private static func context(_ w: Int, _ h: Int, like image: CGImage? = nil) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: image.map(drawingSpace) ?? CGColorSpace(name: CGColorSpace.sRGB)!,
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
        guard let ctx = context(Int(out.width), Int(out.height), like: img) else { return nil }
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
        guard let ctx = context(w, h, like: img) else { return nil }
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
            guard let small = context(sw, sh, like: img) else { ctx.restoreGState(); return nil }
            small.interpolationQuality = .low
            small.draw(img, in: CGRect(x: 0, y: 0, width: sw, height: sh))
            guard let tiny = small.makeImage() else { ctx.restoreGState(); return nil }
            ctx.interpolationQuality = .none
            ctx.draw(tiny, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        ctx.restoreGState()
        return ctx.makeImage()
    }

    /// 水印分发。两种模式共用锚点几何(EditGeometry.watermarkOrigin),各有
    /// 各的"这一层有多大"。
    private static func watermark(_ img: CGImage, spec: WatermarkSpec) -> CGImage? {
        switch spec.kind {
        case .text: textWatermark(img, spec: spec)
        case .image: imageWatermark(img, spec: spec)
        }
    }

    /// 图片水印:按画面宽度定 logo 宽度,保原始长宽比,按锚点贴,整层乘透明度。
    ///
    /// 透明度走 `setAlpha` 而不是自己去改 logo 的每个像素:setAlpha 是把 logo
    /// **自身的** alpha 再乘一个系数,抗锯齿的半透明边缘因此仍是半透明的。
    /// 逐像素改会把"本来全不透明的内部"和"本来就 30% 的边缘"压成同一档,
    /// 结果是圆角 logo 四周镶一圈硬边。
    ///
    /// 抠出来的透明底也正是靠这条保住的:什么都不做,alpha 为 0 的像素画上去
    /// 就是不改变底下的画面。
    private static func imageWatermark(_ img: CGImage, spec: WatermarkSpec) -> CGImage? {
        guard let png = spec.imagePNG, let logo = decode(png) else { return nil }
        let w = img.width, h = img.height
        guard let ctx = context(w, h, like: img) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

        let canvas = CGSize(width: w, height: h)
        let size = EditGeometry.watermarkImageSize(
            logo: CGSize(width: logo.width, height: logo.height),
            canvasWidth: Double(w), scale: spec.scale)
        guard size.width >= 1, size.height >= 1 else { return nil }
        let origin = EditGeometry.watermarkOrigin(
            anchor: spec.anchor, textSize: size, canvas: canvas,
            margin: EditGeometry.watermarkImageMargin(canvas: canvas))

        ctx.saveGState()
        ctx.setAlpha(max(0.05, min(1, spec.opacity)))
        ctx.interpolationQuality = .high
        ctx.draw(logo, in: CGRect(origin: origin, size: size))
        ctx.restoreGState()
        return ctx.makeImage()
    }

    private static func textWatermark(_ img: CGImage, spec: WatermarkSpec) -> CGImage? {
        let w = img.width, h = img.height
        guard let ctx = context(w, h, like: img) else { return nil }
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
