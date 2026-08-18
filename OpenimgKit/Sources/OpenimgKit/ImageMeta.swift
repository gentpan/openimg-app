import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// 一张照片里可展示的拍摄信息。字段缺失是常态而非异常——截图没有相机型号,
/// 微信转发过的图 EXIF 早被清空,手机关了定位就没有 GPS。所以全部可选,
/// 调用方按"有就显示"处理,不要给缺失值编默认值。
public struct ExifInfo: Sendable, Equatable {
    public var cameraMake: String?
    public var cameraModel: String?
    public var lensModel: String?
    /// 光圈 f 值(2.8 表示 f/2.8)。
    public var aperture: Double?
    /// 快门时间,秒。1/250 秒存 0.004——分数形式是展示层的事。
    public var shutterSeconds: Double?
    public var iso: Int?
    /// 实际焦距,毫米。
    public var focalLength: Double?
    /// 等效 35mm 焦距,毫米。手机镜头只看实际焦距没意义,这个才是可比的。
    public var focalLength35mm: Int?
    public var captureDate: Date?
    public var latitude: Double?
    public var longitude: Double?
    /// 海拔,米。低于海平面为负。
    public var altitude: Double?
    /// 写入这张图的软件(相机固件或修图 App)。
    public var software: String?

    public init() {}

    public var hasLocation: Bool { latitude != nil && longitude != nil }

    /// 能指认拍摄者身份或设备的部分。GPS 最要命,但机身序列号同样能把同一
    /// 账号下的多张图串成一条线。
    public var hasIdentifyingInfo: Bool {
        hasLocation || altitude != nil || cameraMake != nil || cameraModel != nil
            || lensModel != nil || software != nil
    }

    /// 有任何可展示内容。全空时界面不必开这一栏。
    public var isEmpty: Bool {
        !hasIdentifyingInfo && aperture == nil && shutterSeconds == nil && iso == nil
            && focalLength == nil && focalLength35mm == nil && captureDate == nil
    }
}

/// 图片的基本情况 + 拍摄信息。像素尺寸和字节数从头部读,不解码整幅图。
public struct ImageMeta: Sendable, Equatable {
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// UTType 标识符(public.jpeg 等)。ImageIO 认不出格式时为 nil。
    public var typeIdentifier: String?
    public var byteCount: Int
    /// CGImagePropertyOrientation 原始值,1 为正立。
    public var orientation: Int
    /// 帧数。大于 1 即动图——剥离与编辑都会绕开它们。
    public var frameCount: Int
    public var exif: ExifInfo

    public var pixelSize: CGSize { CGSize(width: pixelWidth, height: pixelHeight) }
    public var utType: UTType? { typeIdentifier.flatMap(UTType.init(_:)) }
    public var isAnimated: Bool { frameCount > 1 }
}

/// 剥离力度。分级不是为了给用户旋钮玩,而是因为"删干净"和"还能用"确实冲突:
/// 摄影者常想留下光圈快门 ISO(那是作品的一部分),但没人想留下住址。
public enum StripLevel: String, Sendable, CaseIterable {
    /// 不剥,原样上传。
    case none
    /// 只删定位(GPS + IPTC 里的地点副本)。曝光参数、机型全留。
    case location
    /// 删定位 + 设备身份(厂商/机型/镜头/序列号/软件/作者)+ 各家 MakerNote。
    /// 保留曝光参数与色彩描述。默认档。
    case identifying
    /// 除方向外全删。方向必须留——JPEG 的像素常是躺着存的,删掉方向标签
    /// 整张图就横过来了,那不是隐私保护是毁图。
    case all

    /// 这一档承诺删掉的东西是否真的没了。
    ///
    /// 校验必须按档位判定,不能一律要求"全干净":.location 是故意留着机型的,
    /// 拿统一标准去卡它会把每一次剥离都判成失败。
    public func isSatisfied(by residual: MetadataResidual) -> Bool {
        switch self {
        case .none: true
        case .location: !residual.hasLocation
        case .identifying, .all: residual.isPrivacyClean
        }
    }
}

/// 一份文件里还剩什么可识别身份的东西。写文件这条链上任何一环出岔子都可能
/// "看起来成功但元数据还在",所以不信任写入返回值,一律回读为准。
///
/// 它扫的不止 EXIF:同一份住址在一个文件里最多有三处拷贝(EXIF GPS、IPTC 的
/// City/Sub-location、XMP 里的 exif:GPS* 与 photoshop:City),只查其中一处
/// 等于没查——那正好会给出"已剥干净"的假保证,比不查更糟。
public struct MetadataResidual: Sendable, Equatable {
    public var hasLocation: Bool
    public var hasDeviceInfo: Bool
    public var isPrivacyClean: Bool { !hasLocation && !hasDeviceInfo }
}

/// 剥不成的原因。分开列是因为调用方要拿它讲人话:"动图不支持"和"文件读不出来"
/// 对用户是两件事,前者他能换张图,后者他得先修文件。
public enum StripUnsupportedReason: String, Sendable, Equatable, CaseIterable {
    /// ImageIO 打不开:文件损坏,或根本不是它认得的图片。
    case unreadable
    /// 多帧动图。整个模块与 LocalResize 同一纪律:不碰动图。
    case animated
    /// 读得了写不回同一格式。转格式是明令禁止的那件事,宁可不剥。
    case unwritableFormat
    /// 建临时文件或落盘失败:磁盘满、临时目录没权限之类。
    case writeFailed
}

/// 剥离的结果。
///
/// 之前这里返回 `URL?`,nil 同时表示"不用剥"和"剥失败"——两者在调用方眼里
/// 长得一模一样,只能一律原样上传。于是"回读发现 GPS 还在、产物已删"这个
/// 最该拦住的情况,反而变成把带 GPS 的原件直接传上公网。类型本身必须能把
/// 这两种分开,注释里写"宁可让调用方知道没剥成"是补不上的。
public enum StripOutcome: Sendable, Equatable {
    /// 这一档下本来就没有要删的东西(或档位是 .none)。原样上传是安全的。
    case notNeeded
    /// 剥好了,传这份临时文件。用完连它所在的整个目录一起删。
    case stripped(URL)
    /// 有该删的东西,但这个文件剥不了。**不允许**原样上传。
    case unsupported(StripUnsupportedReason)
    /// 剥完回读发现该删的还在,产物已删。**不允许**原样上传。
    case verificationFailed(MetadataResidual)

    /// 能不能把原件原样发出去。只有 notNeeded 能,两种失败都必须被拦下来
    /// ——调用方要是把它们当"没做,照旧传"处理,就退回了当初那个洞。
    public var allowsOriginal: Bool { self == .notNeeded }

    /// 剥离产物;没有产物时为 nil(包括两种失败)。
    public var strippedURL: URL? {
        if case .stripped(let u) = self { return u }
        return nil
    }
}

/// EXIF 读取与剥离。
///
/// 剥离是这个模块存在的理由:图床往外发的是公开链接,一张带 GPS 的照片等于
/// 把住址挂到公网上。所以这里的默认姿态是"先剥再传",而不是"想剥的人自己去
/// 设置里找"。
///
/// 与 LocalResize 头注的纪律并不矛盾:剥元数据走 CGImageDestinationAddImageFromSource,
/// 压缩数据整段抄过去、不重新编码,像素逐位不变,只是容器里的标签少了几段。
/// 代价是文件字节变了、SHA 变了,秒传去重会落空——这笔账值得,隐私优先。
public enum ImageMetadata {

    // MARK: - 读

    /// 读一张图的基本信息与拍摄信息。读不出(文件损坏 / 非图片)返回 nil。
    public static func read(_ url: URL) -> ImageMeta? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let frames = CGImageSourceGetCount(src)
        guard frames >= 1,
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let pw = props[kCGImagePropertyPixelWidth] as? Int,
              let ph = props[kCGImagePropertyPixelHeight] as? Int else { return nil }

        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ImageMeta(
            pixelWidth: pw,
            pixelHeight: ph,
            typeIdentifier: CGImageSourceGetType(src) as String?,
            byteCount: bytes,
            orientation: props[kCGImagePropertyOrientation] as? Int ?? 1,
            frameCount: frames,
            exif: parseExif(props))
    }

    /// 只要拍摄信息。读不出时给一份空的而不是 nil——"这张图没 EXIF"和"这文件
    /// 打不开"在界面上是同一种呈现,调用方不必分开处理。
    public static func exif(_ url: URL) -> ExifInfo {
        read(url)?.exif ?? ExifInfo()
    }

    /// 从 ImageIO 的属性字典里挑出可展示的部分。抽成独立函数是为了让回读校验
    /// 和正常读取走同一条解析路径——校验用的解析要是和展示用的不一样,就等于
    /// 没校验。
    static func parseExif(_ props: [CFString: Any]) -> ExifInfo {
        var info = ExifInfo()
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let aux = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]

        info.cameraMake = nonEmpty(tiff[kCGImagePropertyTIFFMake] as? String)
        info.cameraModel = nonEmpty(tiff[kCGImagePropertyTIFFModel] as? String)
        info.software = nonEmpty(tiff[kCGImagePropertyTIFFSoftware] as? String)
        // 镜头名在两个地方,Exif 标准位优先,苹果旧机型只写 Aux。
        info.lensModel = nonEmpty(exif[kCGImagePropertyExifLensModel] as? String)
            ?? nonEmpty(aux[kCGImagePropertyExifAuxLensModel] as? String)

        // FNumber 是直接的 f 值;没有时从 APEX 的 ApertureValue 换算 f = 2^(Av/2)。
        if let f = exif[kCGImagePropertyExifFNumber] as? Double, f > 0 {
            info.aperture = f
        } else if let av = exif[kCGImagePropertyExifApertureValue] as? Double, av > 0 {
            info.aperture = pow(2, av / 2)
        }
        if let t = exif[kCGImagePropertyExifExposureTime] as? Double, t > 0 {
            info.shutterSeconds = t
        }
        // ISOSpeedRatings 是数组(多段感光度的老规范),取首项;Exif 2.3 起
        // 另有单值的 ISOSpeed,两边都认。
        if let arr = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let first = arr.first {
            info.iso = first
        } else if let s = exif[kCGImagePropertyExifISOSpeed] as? Int {
            info.iso = s
        }
        if let fl = exif[kCGImagePropertyExifFocalLength] as? Double, fl > 0 {
            info.focalLength = fl
        }
        if let fl35 = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int, fl35 > 0 {
            info.focalLength35mm = fl35
        }
        info.captureDate = parseCaptureDate(exif: exif, tiff: tiff)

        // GPS 存的是无符号度数 + 单独的半球标记,合成有符号值才是坐标。
        if let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
           let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            let latRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased()
            let lonRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased()
            info.latitude = latRef == "S" ? -lat : lat
            info.longitude = lonRef == "W" ? -lon : lon
        }
        if let alt = gps[kCGImagePropertyGPSAltitude] as? Double {
            // AltitudeRef:0 海平面以上,1 以下。
            let below = (gps[kCGImagePropertyGPSAltitudeRef] as? Int) == 1
            info.altitude = below ? -alt : alt
        }
        return info
    }

    /// EXIF 的时间是 "yyyy:MM:dd HH:mm:ss",本身不带时区。新规范补了
    /// OffsetTimeOriginal,有就用它;没有只能按本机时区解释——这是相册类
    /// 应用的通行做法,总比丢掉时间好。
    private static func parseCaptureDate(exif: [CFString: Any], tiff: [CFString: Any]) -> Date? {
        let raw = (exif[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif[kCGImagePropertyExifDateTimeDigitized] as? String)
            ?? (tiff[kCGImagePropertyTIFFDateTime] as? String)
        guard let raw, !raw.isEmpty else { return nil }

        // DateFormatter 不是 Sendable,做不成 static let 常量;每次现建的开销
        // 对"读一次文件元数据"这种频次可以忽略,不值得为它引入锁。
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let offset = (exif[kCGImagePropertyExifOffsetTimeOriginal] as? String)
            ?? (exif[kCGImagePropertyExifOffsetTime] as? String)
        if let offset, !offset.isEmpty {
            fmt.dateFormat = "yyyy:MM:dd HH:mm:ssZZZZZ"
            if let d = fmt.date(from: raw + offset) { return d }
        }
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return fmt.date(from: raw)
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }

    // MARK: - 剥离

    /// 剥离元数据,产出一份临时文件。结果四选一,见 `StripOutcome`——只有
    /// `.notNeeded` 允许调用方原样上传,两种失败都必须拦住。
    ///
    /// 默认开启回读校验:剥完再读一遍,该档承诺删掉的东西还在就删产物、报
    /// `.verificationFailed`。关掉校验只在自检里用(要拿到脏产物才能断言校验
    /// 本身有效)。
    public static func strippedCopy(of url: URL,
                                    level: StripLevel = .identifying,
                                    verify: Bool = true) -> StripOutcome {
        guard level != .none else { return .notNeeded }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(src) >= 1 else { return .unsupported(.unreadable) }

        // 先看这张图到底有没有该删的东西。没有就别动它:重写容器会换掉字节
        // 与 SHA,秒传去重和监控目录的清单都跟着落空;截图、微信转发过的图、
        // 已经缩放过的临时文件都属于这一类,占了上传量的大半。
        //
        // .all 不走这条捷径:它承诺"除方向外全删",比 residual 衡量的隐私口径
        // 宽(曝光参数不算隐私但归它删),拿隐私口径给它放行会漏掉那一批。
        if level != .all, level.isSatisfied(by: residual(url)) { return .notNeeded }

        // 到这里说明确实有东西要删。以下任何一步过不去都是阻断性的:剥不掉又
        // 传出去,正是这个函数存在要防的事。
        guard CGImageSourceGetCount(src) == 1 else { return .unsupported(.animated) }
        guard let uti = CGImageSourceGetType(src) else { return .unsupported(.unwritableFormat) }
        // 写不回同一格式就别写:转格式是 LocalResize 头注明令禁止的那件事。
        let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        guard writable.contains(uti as String) else { return .unsupported(.unwritableFormat) }

        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            return .unsupported(.unreadable)
        }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("openimg-strip-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 保留原文件名:上传拿 lastPathComponent 当展示名。
        let out = dir.appendingPathComponent(url.lastPathComponent)

        guard let dst = CGImageDestinationCreateWithURL(out as CFURL, uti, 1, nil) else {
            try? FileManager.default.removeItem(at: dir)
            return .unsupported(.writeFailed)
        }
        // AddImageFromSource 而非 AddImage:前者整段搬运已压缩的数据,像素逐位
        // 不变;后者会解码再编码,给 JPEG 白叠一代有损。
        CGImageDestinationAddImageFromSource(
            dst, src, 0,
            removalProperties(level: level, sourceKeys: Set(props.keys), orientation: orientation) as CFDictionary)
        guard CGImageDestinationFinalize(dst) else {
            try? FileManager.default.removeItem(at: dir)
            return .unsupported(.writeFailed)
        }

        if verify {
            let left = residual(out)
            if !level.isSatisfied(by: left) {
                try? FileManager.default.removeItem(at: dir)
                return .verificationFailed(left)
            }
        }
        return .stripped(out)
    }

    /// 残留扫描:这份文件里还剩什么能指认地点或身份的东西。
    ///
    /// 不复用 `parseExif`——那份解析是给界面展示用的,只认 {Exif}/{TIFF}/
    /// {ExifAux}/{GPS} 四本字典。拿它当回读校验,IPTC 的 City/Sub-location 和
    /// XMP 里的 photoshop:City 全在视野之外:removalProperties 明明在删 IPTC,
    /// 校验却看不见它,一旦哪天删漏了就会给出"已剥干净"的假保证。所以这里
    /// 直读属性字典 + 单独扫一遍 XMP,与展示路径彻底分开。
    public static func residual(_ url: URL) -> MetadataResidual {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(src) >= 1 else {
            // 读不出来就谈不上残留。真正要紧的"读不出来"由 strippedCopy 单独
            // 报 .unreadable,不在这里混成"干净"。
            return MetadataResidual(hasLocation: false, hasDeviceInfo: false)
        }
        var location = false
        var device = false

        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            // GPS 只要这本字典还在且非空就算有:里面每个键都是坐标的一部分,
            // 逐键点名反而会漏掉只写了 GPSAreaInformation 之类的怪文件。
            if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any], !gps.isEmpty {
                location = true
            }

            let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
            for key in iptcLocationKeys where hasValue(iptc[key]) { location = true }
            for key in iptcIdentityKeys where hasValue(iptc[key]) { device = true }

            let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
            for key in exifIdentityKeys where hasValue(exif[key]) { device = true }

            let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            for key in tiffIdentityKeys where hasValue(tiff[key]) { device = true }

            let aux = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]
            for key in auxIdentityKeys where hasValue(aux[key]) { device = true }

            // MakerNote 是私有二进制块,内容不可知——不可知就当作有身份信息。
            if props.keys.contains(where: { ($0 as String).hasPrefix("{Maker") }) { device = true }
        }

        // XMP 是与 EXIF 并存的第二套元数据,属性字典未必映射得全(自定义命名
        // 空间根本没有对应键),必须单独走一遍标签。
        if let md = CGImageSourceCopyMetadataAtIndex(src, 0, nil) {
            CGImageMetadataEnumerateTagsUsingBlock(
                md, nil,
                [kCGImageMetadataEnumerateRecursively: kCFBooleanTrue!] as CFDictionary
            ) { path, tag in
                // 和属性字典那一路一样要过 hasValue,而不是只看路径存不存在。
                //
                // ImageIO 在为 PNG 重建 XMP 时会凭空写进一个**空的** dc:rights
                // ——源文件里本来没有。只比路径的话,每张剥过的 PNG 回读都会被
                // 判成"没剥干净",产物删掉、永久拒传。空壳不是残留。
                guard hasValue(CGImageMetadataTagCopyValue(tag)) else { return true }
                let p = (path as String).lowercased()
                if p.hasPrefix("exif:gps") || xmpLocationPaths.contains(p) { location = true }
                if xmpIdentityPaths.contains(p) { device = true }
                return true
            }
        }

        return MetadataResidual(hasLocation: location, hasDeviceInfo: device)
    }

    // 残留扫描的键表。分成"地点"与"身份"两组,因为 .location 档只承诺删前者
    // ——两组混在一起会把每一次 .location 剥离都判成失败。

    private static var iptcLocationKeys: [CFString] { [
        kCGImagePropertyIPTCCity,
        kCGImagePropertyIPTCSubLocation,
        kCGImagePropertyIPTCProvinceState,
        kCGImagePropertyIPTCCountryPrimaryLocationName,
        kCGImagePropertyIPTCCountryPrimaryLocationCode,
    ] }

    private static var iptcIdentityKeys: [CFString] { [
        kCGImagePropertyIPTCByline,
        kCGImagePropertyIPTCBylineTitle,
        kCGImagePropertyIPTCCredit,
        kCGImagePropertyIPTCSource,
        kCGImagePropertyIPTCContact,
        kCGImagePropertyIPTCCopyrightNotice,
    ] }

    // ExifSubjectLocation 不在列:它是画面里主体的像素坐标,不是地理位置,
    // 名字骗人。
    private static var exifIdentityKeys: [CFString] { [
        kCGImagePropertyExifBodySerialNumber,
        kCGImagePropertyExifCameraOwnerName,
        kCGImagePropertyExifUserComment,
        kCGImagePropertyExifLensMake,
        kCGImagePropertyExifLensModel,
        kCGImagePropertyExifLensSerialNumber,
    ] }

    private static var tiffIdentityKeys: [CFString] { [
        kCGImagePropertyTIFFMake,
        kCGImagePropertyTIFFModel,
        kCGImagePropertyTIFFSoftware,
        kCGImagePropertyTIFFArtist,
        kCGImagePropertyTIFFCopyright,
        kCGImagePropertyTIFFHostComputer,
    ] }

    private static var auxIdentityKeys: [CFString] { [
        kCGImagePropertyExifAuxLensModel,
        kCGImagePropertyExifAuxSerialNumber,
        kCGImagePropertyExifAuxLensSerialNumber,
        kCGImagePropertyExifAuxOwnerName,
    ] }

    /// XMP 里的地点。dc:coverage 是 Dublin Core 的空间/时间范围,写地名的人
    /// 不少;photoshop:* 与 Iptc4xmpCore:* 是 IPTC 地点字段的 XMP 镜像。
    private static let xmpLocationPaths: Set<String> = [
        "dc:coverage",
        "photoshop:city", "photoshop:state", "photoshop:country",
        "iptc4xmpcore:location", "iptc4xmpcore:countrycode",
        "iptc4xmpext:locationshown", "iptc4xmpext:locationcreated",
    ]

    /// XMP 里的身份。dc:creator 走的是自定义命名空间,属性字典里没有对应键
    /// ——它是"只查属性字典查不全"最直接的证据。
    private static let xmpIdentityPaths: Set<String> = [
        "dc:creator", "dc:contributor", "dc:publisher", "dc:rights",
        "tiff:make", "tiff:model", "tiff:artist", "tiff:software",
        "exif:usercomment", "exifex:bodyserialnumber", "exifex:cameraownername",
        "aux:serialnumber", "aux:lensserialnumber", "aux:lens", "aux:ownername",
    ]

    /// 键存在还不够——空串和空数组是 ImageIO 常留下的空壳,当成残留会把每次
    /// 剥离都判成失败。
    private static func hasValue(_ v: Any?) -> Bool {
        guard let v else { return false }
        if let s = v as? String { return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if let d = v as? Data { return !d.isEmpty }
        if let a = v as? [Any] { return !a.isEmpty }
        return true
    }

    /// 构造交给 ImageIO 的"删除清单"。
    ///
    /// ImageIO 的语义是合并而非替换:属性字典里没提到的键会原样保留,所以删除
    /// 必须显式把键置成 kCFNull——靠"不写进去"是删不掉的。整本删就把字典本身
    /// 置 null,只删几项就在子字典里逐键置 null。
    private static func removalProperties(level: StripLevel,
                                          sourceKeys: Set<CFString>,
                                          orientation: Int) -> [CFString: Any] {
        var p: [CFString: Any] = [:]
        guard level != .none else { return p }

        // GPS 整本删,每一档都删——这是整个功能的存在理由,没有"轻一点"的档位。
        p[kCGImagePropertyGPSDictionary] = kCFNull as Any
        // IPTC 里有 City / Sub-location / Country 这套地点字段,是 GPS 之外的
        // 第二份住址;它同时还存作者与版权,连带删掉。
        p[kCGImagePropertyIPTCDictionary] = kCFNull as Any

        switch level {
        case .none:
            break
        case .location:
            break
        case .identifying:
            // TIFF 里 Orientation 也在,所以不能整本删,逐键点名。
            p[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFMake: kCFNull as Any,
                kCGImagePropertyTIFFModel: kCFNull as Any,
                kCGImagePropertyTIFFSoftware: kCFNull as Any,
                kCGImagePropertyTIFFArtist: kCFNull as Any,
                kCGImagePropertyTIFFCopyright: kCFNull as Any,
                kCGImagePropertyTIFFHostComputer: kCFNull as Any,
            ]
            // 序列号是最阴的一类:不写型号也能把同一台机器拍的所有图串起来。
            p[kCGImagePropertyExifDictionary] = [
                kCGImagePropertyExifLensModel: kCFNull as Any,
                kCGImagePropertyExifLensMake: kCFNull as Any,
                kCGImagePropertyExifLensSerialNumber: kCFNull as Any,
                kCGImagePropertyExifBodySerialNumber: kCFNull as Any,
                kCGImagePropertyExifCameraOwnerName: kCFNull as Any,
                kCGImagePropertyExifUserComment: kCFNull as Any,
                kCGImagePropertyExifSubjectLocation: kCFNull as Any,
            ]
            p[kCGImagePropertyExifAuxDictionary] = kCFNull as Any
        case .all:
            p[kCGImagePropertyExifDictionary] = kCFNull as Any
            p[kCGImagePropertyExifAuxDictionary] = kCFNull as Any
            p[kCGImagePropertyTIFFDictionary] = kCFNull as Any
            // TIFF 整本删会把方向一起带走,顶层补回来。顶层 Orientation 由
            // ImageIO 落回容器的方向标签,是这里唯一能既清空字典又保住方向的写法。
            p[kCGImagePropertyOrientation] = orientation
        }

        // 各家 MakerNote 是私有二进制块,里面装什么全凭厂商:苹果往里塞过
        // 场景分类与人脸框,不少机型塞序列号。挨个枚举厂商必然漏,按键名扫
        // ——ImageIO 把它们统一命名成 {MakerApple}、{MakerNikon} 这一族。
        for key in sourceKeys where (key as String).hasPrefix("{Maker") {
            p[key] = kCFNull as Any
        }
        return p
    }
}

// 删 XMP 不必单独写代码,查 XMP 必须。实测(Xcode-beta / macOS 27 SDK):只要给
// AddImageFromSource 传了属性字典,ImageIO 就按属性重建整份 XMP,源文件里
// 的 XMP 标签——包括 dc:creator 这类自定义命名空间——不会被抄过去。曾想过
// 额外塞 kCGImageDestinationMetadata + MergeMetadata=false 兜底,对照实验
// 表明两者产出完全一致,那段代码是纯噪声,故删。
// 若哪天换了系统版本行为变了,ImageMeta 的自检会先炸(见 KitCheck)。
//
// 但"删"能靠系统行为,"查"不行:residual 必须自己去翻 XMP 标签。校验的全部
// 意义就是不信任上面这段实测结论——拿同一条假设既去删又去查,等于没查。
