import Foundation
import CoreGraphics

/// 目标像素尺寸。
public struct PixelSize: Sendable, Equatable, Hashable {
    public var width: Int
    public var height: Int

    public init(_ width: Int, _ height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
    }

    /// 宽高比。裁剪几何一律按像素比算——归一化坐标系里的"比例"会被画布的
    /// 长宽比扭曲,见 EditGeometry.applyRatio。
    public var pixelRatio: Double { Double(width) / Double(height) }
}

/// 尺寸意图。这里区分的是两件常被混为一谈的事:
///
/// - `ratio` 只约束**裁剪框的形状**。用户裁多大随他,导出多少像素也随他;
///   选 16:9 的人要的是构图,不是"给我 1600×900"。
/// - `exact` 除形状外还隐含**导出缩放**:裁剪框按同一比例,导出再锁到这个
///   宽度。选"小红书竖版"的人要的是一张能直接发出去的 1080×1440。
///
/// 混淆的代价很实在:把 ratio 当 exact 会把一张 4000px 的原图偷偷缩到 1600px;
/// 把 exact 当 ratio 会让用户以为自己拿到了平台尺寸,发出去才发现被二次压缩。
public enum SizeIntent: Sendable, Equatable {
    case ratio(Double)
    case exact(PixelSize)

    public var pixelRatio: Double {
        switch self {
        case .ratio(let r): max(0.0001, r)
        case .exact(let s): s.pixelRatio
        }
    }

    /// 导出宽度上限;nil 表示这个意图不管导出,别去动用户已有的设置。
    public var exportWidth: Int? {
        switch self {
        case .ratio: nil
        case .exact(let s): s.width
        }
    }

    /// 给定裁剪出的像素尺寸,导出后实际会是多大。
    ///
    /// 注意不放大:EditSpec.exportMaxWidth 只在源比目标宽时才缩。源图不够大时
    /// 拿到的是"比例对但像素不足"的结果,插值放大只会糊,不如把差距如实告诉
    /// 用户(用 needsUpscale 判断)。
    public func resultPixels(cropped: CGSize) -> CGSize {
        guard case .exact(let target) = self else { return cropped }
        guard cropped.width > Double(target.width) else { return cropped }
        return CGSize(width: Double(target.width),
                      height: (cropped.height * Double(target.width) / cropped.width).rounded())
    }

    /// 裁剪出来的尺寸够不够目标像素。界面据此提示"源图偏小",而不是默默交付
    /// 一张不足尺寸的图。
    public func needsUpscale(cropped: CGSize) -> Bool {
        guard case .exact(let target) = self else { return false }
        return cropped.width < Double(target.width)
    }
}

/// 裁剪比例。只约束形状,不含像素——这是它和 SizePreset 的分界。
public enum CropRatio: String, Sendable, CaseIterable, Identifiable {
    case free
    case square
    case landscape4x3
    case landscape3x2
    case landscape16x9
    case portrait3x4
    case portrait9x16

    public var id: String { rawValue }

    /// 宽/高;自由裁剪没有比例。
    public var pixelRatio: Double? {
        switch self {
        case .free: nil
        case .square: 1
        case .landscape4x3: 4.0 / 3
        case .landscape3x2: 3.0 / 2
        case .landscape16x9: 16.0 / 9
        case .portrait3x4: 3.0 / 4
        case .portrait9x16: 9.0 / 16
        }
    }

    public var intent: SizeIntent? { pixelRatio.map { .ratio($0) } }
}

/// 数值可靠度。平台很少把像素写进正式文档,大多是后台裁剪框的提示或第三方
/// 指南的共识;把这个差别标出来,免得下游把"业界通行"当成"平台保证"。
public enum PresetConfidence: String, Sendable {
    /// 平台自家界面/文档里直接给出的数值。
    case platformStated
    /// 各家指南高度一致、且与平台的展示比例吻合,但平台未直接明说。
    case communityConsensus
    /// 各处说法不一,取了其中较稳妥的一个,详见该项注释。
    case disputed
}

public enum SocialPlatform: String, Sendable, CaseIterable, Identifiable {
    case wechatMP        // 微信公众号
    case xiaohongshu
    case douyin
    case instagram
    case x               // X(原 Twitter)

    public var id: String { rawValue }
}

/// 一条社媒尺寸预设。不带任何界面文案——展示名与说明在 OpenimgMac 层按 id
/// 查表,Kit 只负责数值与语义。
public struct SizePreset: Sendable, Equatable, Identifiable {
    /// 稳定标识。界面用它做选中态与持久化,改名会让用户已保存的选择失效,
    /// 所以这串字符是接口的一部分,别随手改。
    public let id: String
    public let platform: SocialPlatform
    public let intent: SizeIntent
    public let confidence: PresetConfidence

    public var pixels: PixelSize? {
        if case .exact(let s) = intent { return s }
        return nil
    }
}

/// 社媒尺寸目录。
///
/// 数值核对于 2026-08。平台改版比代码发版勤,过一年请重新核一遍,别把这里
/// 当常量看待——confidence 字段就是给这件事留的提醒。
public enum SizePresets {

    /// 裁剪比例下拉的完整选项。
    public static let ratios: [CropRatio] = CropRatio.allCases

    public static let all: [SizePreset] = [
        // 微信公众号
        //
        // 头条封面 900×383(≈2.35:1)。公众号后台的封面裁剪框直接标着这个
        // 数值,属平台明示。要留意的是历史消息列表与转发卡片会按中心 1:1
        // 再裁一刀,关键信息得压在中间的方形区里——这条是排版纪律,不是
        // 尺寸问题,所以不在这里表达。
        SizePreset(id: "wechat.mp.cover.head", platform: .wechatMP,
                   intent: .exact(PixelSize(900, 383)), confidence: .platformStated),
        // 次条/分享封面 1:1。数值有分歧:老资料写 200×200(那是当年的显示
        // 尺寸),近年指南普遍写 383×383(与头条封面的高度对齐,高清屏够用)。
        // 取 383×383——大了可以被缩,小了补不回来。
        SizePreset(id: "wechat.mp.cover.square", platform: .wechatMP,
                   intent: .exact(PixelSize(383, 383)), confidence: .disputed),

        // 小红书
        //
        // 竖版 1080×1440(3:4)。平台没出过尺寸文档,但 3:4 是信息流里占位
        // 最大的比例,各家指南一致推荐,1080 宽也对得上主流手机的物理像素。
        SizePreset(id: "xhs.note.portrait", platform: .xiaohongshu,
                   intent: .exact(PixelSize(1080, 1440)), confidence: .communityConsensus),
        // 方版 1080×1080,多图笔记里保持主页网格整齐时用。
        SizePreset(id: "xhs.note.square", platform: .xiaohongshu,
                   intent: .exact(PixelSize(1080, 1080)), confidence: .communityConsensus),

        // 抖音
        //
        // 1080×1920(9:16)。竖屏 9:16 是抖音的播放器比例,这条属平台层面的
        // 硬约束;1080 宽是与之配套的通行分辨率。图文笔记的封面同此尺寸。
        // 界面上的点赞/评论会盖住下缘,安全区那套留给 OpenimgMac 提示。
        SizePreset(id: "douyin.cover", platform: .douyin,
                   intent: .exact(PixelSize(1080, 1920)), confidence: .platformStated),

        // Instagram
        //
        // 竖版 feed 1080×1350(4:5)是当前占屏最多的贴文比例。
        SizePreset(id: "instagram.feed.portrait", platform: .instagram,
                   intent: .exact(PixelSize(1080, 1350)), confidence: .communityConsensus),
        SizePreset(id: "instagram.feed.square", platform: .instagram,
                   intent: .exact(PixelSize(1080, 1080)), confidence: .communityConsensus),
        // 横版 1080×566(≈1.91:1),即链接卡片那套比例。
        SizePreset(id: "instagram.feed.landscape", platform: .instagram,
                   intent: .exact(PixelSize(1080, 566)), confidence: .communityConsensus),
        // Story / Reels 共用 1080×1920(9:16),是全屏播放器的比例。
        SizePreset(id: "instagram.story", platform: .instagram,
                   intent: .exact(PixelSize(1080, 1920)), confidence: .platformStated),

        // X(原 Twitter)
        //
        // 单图贴文 1600×900(16:9):时间线里给到最大预览且两端都不裁。另有
        // 1200×675 的说法,同为 16:9,只是分辨率低一档——取高的那个。
        SizePreset(id: "x.post.single", platform: .x,
                   intent: .exact(PixelSize(1600, 900)), confidence: .communityConsensus),
    ]

    public static func presets(for platform: SocialPlatform) -> [SizePreset] {
        all.filter { $0.platform == platform }
    }

    public static func preset(id: String) -> SizePreset? {
        all.first { $0.id == id }
    }
}

public extension EditSpec {
    /// 把尺寸意图落到配方上。
    ///
    /// canvas 必须是**旋转后**的画布尺寸(EditGeometry.rotatedSize(源尺寸,
    /// quarters: rotationQuarters)):裁剪框定义在旋转后的画面里,拿源尺寸算
    /// 会让竖拍照片的比例反过来。
    ///
    /// 比例只重塑裁剪框;像素尺寸额外锁死导出宽度——裁剪框已按同一比例,
    /// 限宽之后高度自然落在目标值上(取整误差 ±1 像素)。这也是 ratio 与
    /// exact 唯一的实现差别。
    mutating func apply(_ intent: SizeIntent, canvas: CGSize) {
        let base = crop ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        crop = EditGeometry.applyRatio(base, pixelRatio: intent.pixelRatio, canvas: canvas)
        // ratio 分支刻意不碰 exportMaxWidth:用户可能已经自己设了限宽,选个
        // 构图比例不该把它清掉。
        if let w = intent.exportWidth { exportMaxWidth = w }
    }

    /// 套用裁剪比例;free 表示解除约束,裁剪框保持原样。
    mutating func apply(_ ratio: CropRatio, canvas: CGSize) {
        guard let intent = ratio.intent else { return }
        apply(intent, canvas: canvas)
    }
}
