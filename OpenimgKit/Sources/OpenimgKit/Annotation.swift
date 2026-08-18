import Foundation
import CoreGraphics
import CoreText

/// 标注:画给人看的东西——圈重点、指位置、写说明。
///
/// 和马赛克分开建模,因为两者的性质相反:马赛克是**遮蔽**,一旦落到像素上
/// 就该不可逆;标注是**表达**,必须随时能改、能删、能撤。所以标注是一个
/// 有序数组,渲染只在末尾叠加,撤销就是 `items.removeLast()`——不需要历史
/// 栈,也不需要反操作。
///
/// 坐标与尺寸一律归一化,理由同 MosaicStroke:同一份标注要能同时用于 1600px
/// 预览和全尺寸导出。线宽与字号归一化到**画面对角线**而不是宽度——对角线在
/// 90° 旋转下不变,标注随画面转时粗细/字号才不会突变(这也是 MosaicStroke
/// 半径的选择)。
public struct Annotation: Sendable, Equatable, Identifiable {
    /// 给界面层做 ForEach/选中用。撤销靠数组顺序,不靠 id;id 只是身份。
    public let id: UUID
    public var kind: Kind
    public var color: AnnotationColor
    /// 线宽,归一化到画面对角线。文字标注也保留这个值(界面可以拿它当
    /// 下次画形状的默认粗细),渲染文字时不使用。
    public var lineWidth: Double

    /// 形状与它自己的数据长在一起:矩形没有点列、画笔没有矩形,非法状态
    /// 不可表示。界面层拖拽时用下面的 mutating 方法改末尾那一条,不必到处
    /// 写 switch。
    public enum Kind: Sendable, Equatable {
        /// 自由画笔:归一化点列(y 向下,视图习惯)。
        case freehand(points: [CGPoint])
        /// 箭头:尾 → 头,头部三角形随线宽缩放。
        case arrow(from: CGPoint, to: CGPoint)
        /// 矩形描边。归一化矩形按原样存,不做任何长宽比归一——
        /// Shift 约束成正方形是**像素域**的事(归一化域里 w == h 在非方图上
        /// 并不是正方形),界面层用 EditGeometry.applyRatio(anchor:cursor:
        /// pixelRatio: 1, canvas:) 算完再存进来,这里不会跟它打架。
        case rect(CGRect)
        /// 椭圆描边(内接于该矩形)。按截图习惯是描边不是填充。
        case ellipse(CGRect)
        /// 文字:内容、左上角锚点(归一化,y 向下)、字号(归一化到对角线)。
        case text(String, at: CGPoint, fontScale: Double)
    }

    public init(id: UUID = UUID(), kind: Kind, color: AnnotationColor = .red,
                lineWidth: Double = Annotation.defaultLineWidth) {
        self.id = id
        self.kind = kind
        self.color = color
        self.lineWidth = lineWidth
    }

    /// 约 0.3% 对角线:1000×750 的图上约 3.7px,截图上清楚但不糊住内容。
    public static let defaultLineWidth = 0.003
    /// 约 3% 对角线,和水印默认字号量级一致。
    public static let defaultFontScale = 0.03

    // MARK: - 构造

    public static func freehand(points: [CGPoint], color: AnnotationColor = .red,
                                lineWidth: Double = defaultLineWidth) -> Annotation {
        Annotation(kind: .freehand(points: points), color: color, lineWidth: lineWidth)
    }

    public static func arrow(from: CGPoint, to: CGPoint, color: AnnotationColor = .red,
                             lineWidth: Double = defaultLineWidth) -> Annotation {
        Annotation(kind: .arrow(from: from, to: to), color: color, lineWidth: lineWidth)
    }

    public static func rect(_ r: CGRect, color: AnnotationColor = .red,
                            lineWidth: Double = defaultLineWidth) -> Annotation {
        Annotation(kind: .rect(r), color: color, lineWidth: lineWidth)
    }

    public static func ellipse(_ r: CGRect, color: AnnotationColor = .red,
                               lineWidth: Double = defaultLineWidth) -> Annotation {
        Annotation(kind: .ellipse(r), color: color, lineWidth: lineWidth)
    }

    public static func text(_ s: String, at p: CGPoint, color: AnnotationColor = .red,
                            fontScale: Double = defaultFontScale,
                            lineWidth: Double = defaultLineWidth) -> Annotation {
        Annotation(kind: .text(s, at: p, fontScale: fontScale), color: color, lineWidth: lineWidth)
    }

    // MARK: - 拖拽中的原地更新

    /// 画笔续一个点。非画笔标注忽略——调用方在拖拽循环里不必先判类型。
    public mutating func appendPoint(_ p: CGPoint) {
        if case .freehand(let pts) = kind { kind = .freehand(points: pts + [p]) }
    }

    /// 拖拽中更新"活动端":箭头是头,矩形/椭圆是与起点相对的那个角。
    /// 起点由 anchor 给出,这样界面层不用记住自己当初从哪个角开始拖。
    public mutating func dragEnd(to p: CGPoint, anchor: CGPoint) {
        switch kind {
        case .arrow(let from, _): kind = .arrow(from: from, to: p)
        case .rect: kind = .rect(Annotation.rectBetween(anchor, p))
        case .ellipse: kind = .ellipse(Annotation.rectBetween(anchor, p))
        case .freehand, .text: break
        }
    }

    /// 两点定框,永远返回正宽高——拖到锚点左上方时 width 为负会让所有下游
    /// 计算(命中、渲染、旋转)都要各自 standardize 一次。
    public static func rectBetween(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// 归一化包围盒,给命中测试/选中框用。文字给不出真包围盒(要有画布尺寸
    /// 才知道排版结果),返回锚点处的零尺寸框,由界面层按渲染结果补。
    public var normalizedBounds: CGRect {
        switch kind {
        case .freehand(let pts):
            guard let first = pts.first else { return .zero }
            var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
            for p in pts.dropFirst() {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .arrow(let a, let b): return Annotation.rectBetween(a, b)
        case .rect(let r), .ellipse(let r): return r.standardized
        case .text(_, let p, _): return CGRect(origin: p, size: .zero)
        }
    }
}

/// 自带 sRGB 分量,不用 CGColor 当模型:CGColor 带色彩空间、不好比较、
/// 也不便于以后存成配方。渲染时才转成 CGColor。
public struct AnnotationColor: Sendable, Equatable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: max(0, min(1, red)), green: max(0, min(1, green)),
                blue: max(0, min(1, blue)), alpha: max(0, min(1, alpha)))
    }

    /// 标注常用色。挑的是在照片和截图上都压得住的高饱和色,不是品牌色。
    public static let red = AnnotationColor(red: 0.93, green: 0.16, blue: 0.16)
    public static let orange = AnnotationColor(red: 0.98, green: 0.55, blue: 0.09)
    public static let yellow = AnnotationColor(red: 0.98, green: 0.80, blue: 0.08)
    public static let green = AnnotationColor(red: 0.13, green: 0.70, blue: 0.35)
    public static let blue = AnnotationColor(red: 0.15, green: 0.45, blue: 0.96)
    public static let white = AnnotationColor(red: 1, green: 1, blue: 1)
    public static let black = AnnotationColor(red: 0, green: 0, blue: 0)

    public static let palette: [AnnotationColor] = [.red, .orange, .yellow, .green, .blue, .white, .black]
}

// MARK: - 几何

/// 纯几何,不碰像素——和 EditGeometry 同一个用意:KitCheck 能在无渲染
/// 环境里自检,渲染代码里不再藏第二份算法。
public enum AnnotationGeometry {
    public static func diagonal(_ canvas: CGSize) -> Double {
        (canvas.width * canvas.width + canvas.height * canvas.height).squareRoot()
    }

    /// 归一化长度 → 像素。除以对角线是"归一化到对角线"的逆运算,所以同一份
    /// 标注在 1x 与 3x 导出上粗细严格成比例。
    public static func pixels(_ normalizedLength: Double, canvas: CGSize) -> Double {
        normalizedLength * diagonal(canvas)
    }

    /// 归一化点(y 向下)→ CG 像素点(y 向上)。
    public static func point(_ p: CGPoint, canvas: CGSize) -> CGPoint {
        CGPoint(x: p.x * canvas.width, y: (1 - p.y) * canvas.height)
    }

    /// 归一化矩形(y 向下)→ CG 像素矩形(y 向上)。先 standardized,负宽高
    /// 的拖拽中间态也能正确翻转。
    public static func rect(_ r: CGRect, canvas: CGSize) -> CGRect {
        let s = r.standardized
        return CGRect(x: s.minX * canvas.width,
                      y: (1 - s.maxY) * canvas.height,
                      width: s.width * canvas.width,
                      height: s.height * canvas.height)
    }

    /// 箭头头部。全部在**像素域**算:归一化域里横纵尺度不同,直接在那边求
    /// 方向会让非方图上的三角形相对杆身斜掉。
    public struct ArrowHead: Sendable, Equatable {
        public var tip: CGPoint
        public var left: CGPoint
        public var right: CGPoint
        /// 杆该画到哪儿。见下方为什么不是 tip 也不是底边。
        public var shaftEnd: CGPoint
        /// 头部沿轴长度(像素)。
        public var length: Double
        /// 底边半宽(像素)。
        public var halfWidth: Double
    }

    /// 箭头头部三角形。头随线宽缩放(lineWidth 的 lengthRatio 倍长、
    /// widthRatio 倍半宽,约 22° 半角,是常见箭头的观感)。
    ///
    /// 短箭头单独处理:理想头长可能比整根箭头还长,那样画出来就是一个孤零零
    /// 的三角形。所以头长封顶在杆长的一半,并且**宽度同比缩**——只削长度会
    /// 把头压成一把钝斧头。
    ///
    /// 退化(首尾同点)返回 nil,由调用方跳过:一次误点击不该在图上留下东西。
    public static func arrowHead(from: CGPoint, to: CGPoint, lineWidth: Double,
                                 lengthRatio: Double = 3.6, widthRatio: Double = 1.5,
                                 maxLengthFraction: Double = 0.5) -> ArrowHead? {
        let dx = to.x - from.x, dy = to.y - from.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 1e-6, lineWidth > 0 else { return nil }
        let ux = dx / len, uy = dy / len

        let ideal = lineWidth * lengthRatio
        let l = min(ideal, len * maxLengthFraction)
        let k = l / ideal                      // 缩放系数,长宽同乘 → 三角形形状不变
        let hw = lineWidth * widthRatio * k

        let base = CGPoint(x: to.x - ux * l, y: to.y - uy * l)
        let nx = -uy, ny = ux                  // 轴的法线
        // 杆止于底边**稍靠前**处而不是底边或箭尖:停在底边会让圆线帽从三角形
        // 两侧探出小耳朵,画到箭尖则细箭头的杆会盖住尖端形状。咬进去 15%。
        let shaftEnd = CGPoint(x: to.x - ux * l * 0.85, y: to.y - uy * l * 0.85)
        return ArrowHead(tip: to,
                         left: CGPoint(x: base.x + nx * hw, y: base.y + ny * hw),
                         right: CGPoint(x: base.x - nx * hw, y: base.y - ny * hw),
                         shaftEnd: shaftEnd, length: l, halfWidth: hw)
    }

    /// 文字排版可用宽度(像素)。从锚点到右边距,但不低于画面宽的 25%——
    /// 贴着右边缘落笔时那点残宽会把每行挤成一个字,还不如让它排宽一点,
    /// 再由 textBlockRect 把整块往左推回画内。
    public static func textWrapWidth(originX: Double, canvas: CGSize, margin: Double) -> Double {
        max(canvas.width * 0.25, canvas.width - originX * canvas.width - margin)
    }

    /// 文字块落位:给归一化锚点(左上角,y 向下)和已排版好的块尺寸,返回
    /// 夹进画面的 CG 矩形。
    ///
    /// 越界的处理顺序是有讲究的:先把下沿顶回画内,再把上沿压回画内。这样
    /// 当文字块比画面还高时,最后生效的是"上沿不超"——**开头那几行一定看得
    /// 见**,溢出的是结尾。反过来做会让用户只看到一段没头没尾的中间。
    public static func textBlockRect(origin: CGPoint, blockSize: CGSize,
                                     canvas: CGSize, margin: Double) -> CGRect {
        var x = origin.x * canvas.width
        // y 向下 → CG:块顶在 (1 - origin.y) * h,块底再减去块高。
        var y = (1 - origin.y) * canvas.height - blockSize.height

        if x + blockSize.width > canvas.width - margin {
            x = canvas.width - margin - blockSize.width
        }
        x = max(margin, x)
        y = max(margin, y)
        y = min(y, canvas.height - margin - blockSize.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: blockSize)
    }

    /// 整组标注随画面顺时针转 90°。复用 EditGeometry 的点/矩形变换,和
    /// EditSpec.rotateSpecCW 是同一套规则;线宽与字号归一化到对角线,旋转
    /// 不改变对角线,所以原样带过去(翻转同理)。
    public static func rotateQuarterCW(_ items: [Annotation]) -> [Annotation] {
        map(items, point: EditGeometry.rotateQuarterCW, rect: EditGeometry.rotateQuarterCW)
    }

    /// 整组标注随画面水平/垂直翻转。和旋转同一条纪律:标注跟着它标的东西走,
    /// 圈住左边那个人的圈,翻完还得圈着他。
    ///
    /// 矩形不能只翻原点:x → 1-x 会把左上角送到右上角**之外**,框整体越界半个
    /// 身位。所以走 EditGeometry.flipH(CGRect) 那份(它翻的是 maxX),两边共用
    /// 同一份实现,免得哪天只改对一处。
    public static func flipH(_ items: [Annotation]) -> [Annotation] {
        map(items, point: EditGeometry.flipH, rect: EditGeometry.flipH)
    }

    public static func flipV(_ items: [Annotation]) -> [Annotation] {
        map(items, point: EditGeometry.flipV, rect: EditGeometry.flipV)
    }

    /// 三种变换只在"点怎么变、矩形怎么变"上不同,其余(哪些 case 带点、
    /// 线宽字号原样带过)完全一样。抽出来,免得新增一种变换时漏掉某个 case。
    ///
    /// 文字锚点是块的左上角,变换后仍当左上角用——严格说翻转/旋转后原来的
    /// 左上角变成了别的角,但文字块尺寸依赖排版宽度,追求"绝对不动"要先排版
    /// 再变换,得让纯几何依赖 CoreText。宁可差半个块。
    private static func map(_ items: [Annotation],
                            point: (CGPoint) -> CGPoint,
                            rect: (CGRect) -> CGRect) -> [Annotation] {
        items.map { item in
            var out = item
            switch item.kind {
            case .freehand(let pts):
                out.kind = .freehand(points: pts.map(point))
            case .arrow(let a, let b):
                out.kind = .arrow(from: point(a), to: point(b))
            case .rect(let r):
                out.kind = .rect(rect(r.standardized))
            case .ellipse(let r):
                out.kind = .ellipse(rect(r.standardized))
            case .text(let s, let p, let f):
                out.kind = .text(s, at: point(p), fontScale: f)
            }
            return out
        }
    }
}

// MARK: - 渲染

/// 把标注画到图上,返回新图。纯函数:不读全局状态、不写文件、不碰 NSImage,
/// 可以在任意并发域调用(CGImage 不可变)。
///
/// 数组顺序即叠放顺序,后画的盖前面的——于是"撤销"和"删掉数组最后一项"是
/// 同一件事,渲染这边不需要任何配合。
///
/// 出错(建不出上下文、空数组)时原样返回入参而不是 nil:标注是装饰,画不上
/// 去也不该让整条编辑管线失败,更不该逼每个调用点写解包。
public func renderAnnotations(_ items: [Annotation], on image: CGImage) -> CGImage {
    guard !items.isEmpty else { return image }
    let w = image.width, h = image.height
    let canvas = CGSize(width: w, height: h)
    // 画布色彩空间跟着源图走:钉死 sRGB 会让"画了个圈"顺带把广色域源压掉
    // 一档,而标注本该只是叠一层墨。见 ImageEdit.drawingSpace。
    guard w > 0, h > 0,
          let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: ImageEdit.drawingSpace(image),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return image }

    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setShouldAntialias(true)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    for item in items {
        // 线宽至少 1px:全尺寸导出上 0.3% 对角线很粗,但缩略预览上可能不足
        // 一个像素,CG 会画成一条半透明的鬼影。
        let lw = max(1, AnnotationGeometry.pixels(item.lineWidth, canvas: canvas))
        let color = item.color.cgColor
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(lw)

        switch item.kind {
        case .freehand(let pts):
            guard let first = pts.first else { continue }
            let start = AnnotationGeometry.point(first, canvas: canvas)
            if pts.count == 1 {
                // 单点(点一下就松手)也要留痕:描边路径没有面积,直接填个圆点。
                ctx.fillEllipse(in: CGRect(x: start.x - lw / 2, y: start.y - lw / 2,
                                           width: lw, height: lw))
                continue
            }
            ctx.beginPath()
            ctx.move(to: start)
            for p in pts.dropFirst() {
                ctx.addLine(to: AnnotationGeometry.point(p, canvas: canvas))
            }
            ctx.strokePath()

        case .arrow(let a, let b):
            let pa = AnnotationGeometry.point(a, canvas: canvas)
            let pb = AnnotationGeometry.point(b, canvas: canvas)
            guard let head = AnnotationGeometry.arrowHead(from: pa, to: pb, lineWidth: lw) else { continue }
            ctx.beginPath()
            ctx.move(to: pa)
            ctx.addLine(to: head.shaftEnd)
            ctx.strokePath()
            ctx.beginPath()
            ctx.move(to: head.tip)
            ctx.addLine(to: head.left)
            ctx.addLine(to: head.right)
            ctx.closePath()
            ctx.fillPath()

        case .rect(let r):
            let px = AnnotationGeometry.rect(r, canvas: canvas)
            guard px.width > 0, px.height > 0 else { continue }
            ctx.stroke(px)

        case .ellipse(let r):
            let px = AnnotationGeometry.rect(r, canvas: canvas)
            guard px.width > 0, px.height > 0 else { continue }
            ctx.strokeEllipse(in: px)

        case .text(let s, let at, let fontScale):
            guard !s.isEmpty else { continue }
            drawAnnotationText(s, at: at, fontScale: fontScale, color: color, canvas: canvas, in: ctx)
        }
    }
    return ctx.makeImage() ?? image
}

/// 文字标注。用 CTFramesetter 而不是 CTLine(水印用的那个):水印是一行短
/// 署名,标注是用户随手打的一段话,必须**自动换行**,还要认他自己敲的换行。
///
/// 不加阴影/描边衬底:颜色是用户选的,自动加光晕等于改他选的观感;要衬底
/// 就先画一个矩形标注,这样是他的决定。
private func drawAnnotationText(_ text: String, at origin: CGPoint, fontScale: Double,
                                color: CGColor, canvas: CGSize, in ctx: CGContext) {
    // 字号同样归一化到对角线,和线宽一套口径;9px 兜底,再小的字在预览上
    // 已经不是字了。
    let fontSize = max(9, AnnotationGeometry.pixels(fontScale, canvas: canvas))
    // 和水印用同一款字体,度量口径一致;CJK 由 CoreText 的字体级联兜底。
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
    let attributed = NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ])
    let setter = CTFramesetterCreateWithAttributedString(attributed)

    let margin = fontSize * 0.4
    let wrapWidth = AnnotationGeometry.textWrapWidth(originX: origin.x, canvas: canvas, margin: margin)
    var fitRange = CFRange()
    let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
        setter, CFRange(location: 0, length: 0), nil,
        CGSize(width: wrapWidth, height: .greatestFiniteMagnitude), &fitRange)

    // 向上取整并各留 1px:CTFramesetter 给的建议尺寸是浮点,原样当框高会
    // 因为末位误差把最后一行整行丢掉。
    let block = CGSize(width: min(ceil(suggested.width) + 1, wrapWidth),
                       height: min(ceil(suggested.height) + 1,
                                   max(fontSize, canvas.height - margin * 2)))
    let frameRect = AnnotationGeometry.textBlockRect(origin: origin, blockSize: block,
                                                    canvas: canvas, margin: margin)
    // 超出画面的部分交给 CTFrame 自己裁:框只有这么高,排不下的行不会画出去,
    // 也就不会出现半截字母贴在画面边上。
    let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0),
                                         CGPath(rect: frameRect, transform: nil), nil)
    ctx.saveGState()
    ctx.textMatrix = .identity   // 前一步若画过文字会留下文本矩阵,不重置会整体错位
    CTFrameDraw(frame, ctx)
    ctx.restoreGState()
}
