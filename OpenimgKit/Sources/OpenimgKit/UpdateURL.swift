import Foundation

/// 更新清单里那些地址的白名单。
///
/// 清单是签过名的,但私钥万一泄露,攻击者能签一份把用户送去任意站点的清单。
/// 下载物本身还有代码签名兜底(见 UpdateValidator),可「查看发布说明」那个
/// 按钮是直接开浏览器的——它没有第二道闸,所以地址必须在这里就卡死。
public enum UpdateURL {
    /// 只认这两个前缀。写成前缀而不是域名,理由见下面 `check` 的注释。
    public static let allowedPrefixes = [
        "https://github.com/gentpan/openimg-app/releases/download/",
        "https://github.com/gentpan/openimg-app/releases/tag/",
    ]

    /// 校验并返回。任何一条不满足就是 nil,不做"修一修再用"。
    ///
    /// **只校验 host 是无效的。** 下面这个串的 host 就是 github.com:
    ///
    ///     https://github.com/gentpan/openimg-app/releases/tag/../../../evil/repo/releases/tag/v9
    ///
    /// 浏览器会先规范化再请求,于是它落在 github.com/evil/repo 上——一个攻击者
    /// 控制的仓库,页面上摆着一个他自己的下载链接。所以三件事都要做:
    ///
    ///   1. 前缀必须命中(把路径的前几段钉死)
    ///   2. 规范化之后必须与原串**逐字相同**(`..` 一旦改变了含义就露馅)
    ///   3. 路径里不能有 `..` 段(第 2 条在某些写法下会漏,这条兜底)
    ///
    /// 第 2 条单独看似乎已经够了,但它依赖 URL 规范化的实现细节;第 3 条是显式
    /// 的、读得懂的,两条一起才不用去赌某个 Foundation 版本的行为。
    public static func check(_ raw: String) -> URL? {
        guard let url = URL(string: raw) else { return nil }
        guard allowedPrefixes.contains(where: { raw.hasPrefix($0) }) else { return nil }
        guard url.standardized.absoluteString == raw else { return nil }
        guard !url.pathComponents.contains("..") else { return nil }
        // 明文 http 在前缀里就被排除了,这里再确认一次:前缀是常量,但常量会被改。
        guard url.scheme?.lowercased() == "https" else { return nil }
        return url
    }
}
