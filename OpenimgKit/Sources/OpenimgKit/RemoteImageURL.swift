import Foundation

/// 从一条网址取图时,"这条网址能不能用"和"存成什么文件名"这两件事。
///
/// 单独拎出来是因为它们全是纯字符串/字节判断,而且**错了都不报错**:
///
///   - 放行了 `file://` 之类的协议,等于让粘贴板上的一段文字去读本机文件;
///   - 文件名的扩展名弄错,本地那道格式校验(rejectLocally 只看 pathExtension)
///     会把一张好好的 PNG 拒成"格式不允许",而用户看到的是一句和真实原因无关
///     的错误。CDN 链接常常根本没有扩展名,这不是边角情况。
public enum RemoteImageURL {
    /// 把用户粘的一串东西解成一条能用的 http(s) 网址。解不出来返回 nil。
    public static func parse(_ raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(" "), !s.contains("\n") else { return nil }

        // 没写协议就补 https,但只在它确实像一条网址时补。
        //
        // 判据是**必须带路径**(有 "/" 且后面还有东西),外加 host 至少两段。
        // 光看"有没有点"不够:`photo.png` 和 `a.com` 在结构上一模一样,而前者
        // 是用户手里的本地文件名——补成 https://photo.png 会真的发一次请求出去,
        // 然后失败在一句和原因毫无关系的 DNS 错误上。
        //
        // 代价是裸域名(`example.com`)也补不了,而那本来就取不到图。真要省这
        // 三个字符的用户,浏览器里复制出来的地址本来就带协议。
        var text = s
        if !text.contains("://") {
            guard let slash = text.firstIndex(of: "/"),
                  text.index(after: slash) < text.endIndex else { return nil }
            let host = text[..<slash]
            guard host.split(separator: ".").count >= 2,
                  !host.hasPrefix("."), !host.hasSuffix(".") else { return nil }
            text = "https://" + text
        }

        guard let u = URL(string: text),
              let scheme = u.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = u.host, !host.isEmpty else { return nil }
        return u
    }

    /// 下载下来的临时文件叫什么。
    ///
    /// 扩展名的来源按可靠度排:字节头 > Content-Type > 网址里的路径。字节头最
    /// 可靠——服务器的 Content-Type 经常是 application/octet-stream,而路径里
    /// 的 ".jpg" 可能只是一段假后缀。
    public static func filename(for url: URL, contentType: String?, magic: Data) -> String {
        let ext = imageExtension(magic: magic)
            ?? imageExtension(contentType: contentType)
            ?? sanitizedExtension(url.pathExtension)

        var stem = url.deletingPathExtension().lastPathComponent
        stem = stem.replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        // ".." 之类会顺着 appendingPathComponent 变成上级目录。
        if stem.isEmpty || stem.hasPrefix(".") || stem.contains("..") { stem = "image" }
        if stem.count > 60 { stem = String(stem.prefix(60)) }

        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }

    /// 认字节头。只认这个项目会上传的那几种。
    public static func imageExtension(magic d: Data) -> String? {
        func at(_ i: Int) -> UInt8? { i < d.count ? d[d.startIndex + i] : nil }
        func has(_ bytes: [UInt8], at off: Int = 0) -> Bool {
            for (i, b) in bytes.enumerated() where at(off + i) != b { return false }
            return true
        }
        if has([0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if has([0xFF, 0xD8, 0xFF]) { return "jpeg" }
        if has([0x47, 0x49, 0x46, 0x38]) { return "gif" }
        if has([0x42, 0x4D]) { return "bmp" }
        if has([0x49, 0x49, 0x2A, 0x00]) || has([0x4D, 0x4D, 0x00, 0x2A]) { return "tiff" }
        // RIFF....WEBP
        if has([0x52, 0x49, 0x46, 0x46]), has([0x57, 0x45, 0x42, 0x50], at: 8) { return "webp" }
        // ISO-BMFF:....ftyp<brand>。AVIF 与 HEIC 同族,靠 brand 分。
        if has([0x66, 0x74, 0x79, 0x70], at: 4) {
            let brand = (8..<12).compactMap(at).map { Character(UnicodeScalar($0)) }
            switch String(brand) {
            case "avif", "avis": return "avif"
            case "heic", "heix", "hevc", "mif1", "msf1": return "heic"
            default: return nil
            }
        }
        return nil
    }

    /// 认 Content-Type。带参数的("image/png; charset=..")也要能认。
    public static func imageExtension(contentType: String?) -> String? {
        guard let raw = contentType?.lowercased() else { return nil }
        let mime = raw.split(separator: ";").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        switch mime {
        case "image/png": return "png"
        case "image/jpeg", "image/jpg": return "jpeg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/avif": return "avif"
        case "image/heic", "image/heif": return "heic"
        case "image/bmp", "image/x-ms-bmp": return "bmp"
        case "image/tiff": return "tiff"
        default: return nil
        }
    }

    private static func sanitizedExtension(_ raw: String) -> String {
        let e = raw.lowercased().filter { $0.isLetter || $0.isNumber }
        return e.count <= 5 ? e : ""
    }
}
