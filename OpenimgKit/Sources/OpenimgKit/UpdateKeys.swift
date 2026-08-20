import Foundation

/// 编进 app 的更新清单签名公钥。
///
/// 这是整条更新链路的信任根之一(另一条是 Developer ID 代码签名)。它写死在
/// 二进制里,不从网络取、不从配置读——能被远端换掉的信任根不是信任根。
///
/// ## 轮换
///
/// 表里可以同时有多把。轮换的正确顺序是:
///
///   1. 先发一版把新公钥 k2 **加进**这张表,老的 k1 留着;
///   2. 等大部分用户升上去之后,才开始用 k2 签清单;
///   3. 之后再发一版把 k1 从表里删掉,并在清单的 `revokeKeys` 里列上 k1。
///
/// 顺序反了就断链:先换签名密钥、后发新版本的话,还在跑旧版的客户端认不出 k2,
/// 而它们恰恰是唯一需要收到这次更新的人——**它们再也收不到任何更新了**,而且
/// 服务端没有任何补救办法。
public enum UpdateKeys {
    /// keyId → 32 字节裸公钥。
    public static let publicKeys: [String: Data] = {
        var out: [String: Data] = [:]
        for (id, b64) in raw {
            guard let d = Data(base64Encoded: b64), d.count == 32 else { continue }
            out[id] = d
        }
        return out
    }()

    /// base64 形式,方便肉眼与 `UpdateTool keygen` 的输出对照。
    ///
    /// 私钥在作者本机 `~/.openimg/update-signing-k1.key`,不在版本库里。
    static let raw: [String: String] = [
        "k1": "IvX8rbYuP/nhxwWdbpGptYYXZ7+G1Uc0R49wgGjpoQY=",
    ]

    /// 更新清单的地址。
    ///
    /// 清单放在自己的服务器,安装包放在 GitHub Releases。这个分离不只是省带宽:
    /// 单独拿下任何一边都拿不到代码执行——改了清单过不了代码签名,换了包过不了
    /// 清单里的 sha256。
    ///
    /// 不查 GitHub API:未认证限流是每小时 60 次、按出口 IP 算,在 NAT、机场
    /// WiFi、公司网里一开机就被拒是常态,而那个失败是静默的。
    public static let feedURL = URL(string: "https://openimg.io/api/app/mac/update.json")!
}
