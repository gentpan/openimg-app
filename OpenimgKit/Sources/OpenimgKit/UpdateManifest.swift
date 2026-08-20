import CryptoKit
import Foundation

public enum UpdateError: Error, LocalizedError, Equatable {
    case feedUnavailable(Int)
    /// 拿到的不是 JSON。单列一条是因为它有一个特定的成因,见 parse 里的注释。
    case feedNotJSON(String)
    case feedTooLarge(Int)
    case malformedFeed(String)
    case unknownSigningKey(String)
    case revokedSigningKey(String)
    case badFeedSignature
    case badURL(String)

    public var errorDescription: String? {
        switch self {
        case .feedUnavailable(let s): "检查更新失败(HTTP \(s))"
        case .feedNotJSON(let ct): "更新地址返回的不是更新清单(\(ct))"
        case .feedTooLarge(let n): "更新清单异常地大(\(n) 字节)"
        case .malformedFeed(let why): "更新清单读不懂:\(why)"
        case .unknownSigningKey(let id): "更新清单用了未知的签名密钥 \(id)"
        case .revokedSigningKey(let id): "更新清单用了已作废的签名密钥 \(id)"
        case .badFeedSignature: "更新清单的签名不对"
        case .badURL(let u): "更新清单里的地址不被信任:\(u)"
        }
    }
}

/// 更新清单。
///
/// 外层是一个信封:`{ payload, sig, keyId }`,payload 是清单 JSON 的 base64。
///
/// **签的是原始字节,解析的也是同一串字节。** 这一刀砍掉了整个 JSON 规范化
/// 雷区:不需要约定键顺序、不需要约定数字怎么写、也不存在"验了一份、用了另
/// 一份"的缝隙——那正是更新器最典型的一类漏洞。
///
/// 代价是清单不再是人类可读的。缓解办法是发版时把 pretty 版贴进 release
/// notes,而客户端永远不读它。
public struct UpdateManifest: Sendable, Equatable {
    public let schema: Int
    /// 严格递增的序号,用来挡重放。取值是签发时的 Unix 秒。
    public let seq: Int
    public let issuedAt: Date
    public let expiresAt: Date
    public let channel: String
    public let latest: Release
    /// 低于这个版本的都建议尽快升。只是提示,不能强制。
    public let revokedBelow: SemanticVersion?
    /// 已作废的签名密钥。轮换用。
    public let revokeKeys: [String]
    public let signedByKeyID: String

    public struct Release: Sendable, Equatable {
        public let version: SemanticVersion
        public let build: Int
        public let minimumSystemVersion: SemanticVersion
        public let arch: String
        /// 已经过白名单。
        public let url: URL
        public let size: Int
        public let sha256: String
        /// 已经过白名单。
        public let notesURL: URL?
    }

    /// 清单最大 64 KiB。真实清单不到 1 KiB,这个上限拦的是"服务端出错回了个
    /// 几十兆的东西"。
    public static let maxBytes = 64 * 1024

    /// 解析并验签。**每一条都是硬失败。**
    ///
    /// 这和 `WatchManifest.decode` 的宽容策略正好相反——那边对损坏数据返回空,
    /// 因为最坏代价是重算一遍哈希。这里最坏的代价是把用户装上一份攻击者选的
    /// 代码,所以任何一处对不上都必须停。
    ///
    /// - Parameters:
    ///   - publicKeys: keyId → 32 字节裸公钥。编进 app 里。
    ///   - revokedKeyIDs: 本机已经记下的作废密钥。
    public static func parse(
        _ data: Data,
        contentType: String?,
        status: Int,
        publicKeys: [String: Data],
        revokedKeyIDs: Set<String> = []
    ) throws -> UpdateManifest {
        guard status == 200 else { throw UpdateError.feedUnavailable(status) }

        // 两道闸,缺一不可。
        //
        // 服务端的 SPA 兜底对任何未匹配路径返回 **200 + index.html**。只看状态
        // 码的解析器会把一份 HTML 当成合法清单,表现是「静默地永远没有更新」
        // ——一个不报错的失败模式。这个项目已经为同一个坑立过一次法(见
        // apple_assoc.go 的注释,线上真的返回过 text/html)。
        //
        // Content-Type 能被中间层改写,首字节骗不了人;反过来,首字节检查对一份
        // 恰好以 `{` 开头的 HTML 又无能为力。所以两道都要。
        guard let ct = contentType?.lowercased(), ct.hasPrefix("application/json") else {
            throw UpdateError.feedNotJSON(contentType ?? "(无)")
        }
        guard data.first != UInt8(ascii: "<") else { throw UpdateError.feedNotJSON("HTML") }
        // 上限卡在实际字节数上,不卡在 expectedContentLength —— 后者在 gzip 或
        // chunked 传输下是 -1。
        guard data.count <= maxBytes else { throw UpdateError.feedTooLarge(data.count) }

        struct Envelope: Decodable { let payload: String; let sig: String; let keyId: String }
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw UpdateError.malformedFeed("信封解不开")
        }
        guard let payload = Data(base64Encoded: env.payload),
              let sig = Data(base64Encoded: env.sig) else {
            throw UpdateError.malformedFeed("payload 或 sig 不是合法 base64")
        }

        guard !revokedKeyIDs.contains(env.keyId) else {
            throw UpdateError.revokedSigningKey(env.keyId)
        }
        guard let raw = publicKeys[env.keyId] else {
            throw UpdateError.unknownSigningKey(env.keyId)
        }
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
              key.isValidSignature(sig, for: payload) else {
            throw UpdateError.badFeedSignature
        }

        // 解析的就是刚刚验过签的那串字节。
        return try decode(payload, signedBy: env.keyId)
    }

    /// 只解析,不验签。给签名工具在签完之后自检用。
    public static func decode(_ payload: Data, signedBy keyID: String) throws -> UpdateManifest {
        struct Raw: Decodable {
            struct Release: Decodable {
                let version: String
                let build: Int
                let minimumSystemVersion: String
                let arch: String
                let url: String
                let size: Int
                let sha256: String
                let notesURL: String?
            }
            let schema: Int
            let seq: Int
            let issuedAt: String
            let expiresAt: String
            let channel: String
            let latest: Release
            let revokedBelow: String?
            let revokeKeys: [String]?
        }

        guard let r = try? JSONDecoder().decode(Raw.self, from: payload) else {
            throw UpdateError.malformedFeed("payload 结构不对")
        }
        guard r.schema == 1 else {
            throw UpdateError.malformedFeed("不认识的 schema \(r.schema)")
        }
        guard let version = SemanticVersion(r.latest.version) else {
            throw UpdateError.malformedFeed("版本号解不出:\(r.latest.version)")
        }
        guard let minSystem = SemanticVersion(r.latest.minimumSystemVersion) else {
            throw UpdateError.malformedFeed("最低系统版本解不出:\(r.latest.minimumSystemVersion)")
        }
        // 时间用 ISO8601,不带小数秒——它是签名工具生成的,格式由我们自己定。
        let fmt = ISO8601DateFormatter()
        guard let issued = fmt.date(from: r.issuedAt), let expires = fmt.date(from: r.expiresAt) else {
            throw UpdateError.malformedFeed("时间戳解不出")
        }
        guard let url = UpdateURL.check(r.latest.url) else {
            throw UpdateError.badURL(r.latest.url)
        }
        var notes: URL?
        if let n = r.latest.notesURL {
            guard let ok = UpdateURL.check(n) else { throw UpdateError.badURL(n) }
            notes = ok
        }
        // sha256 是 64 个十六进制字符。长度不对就不是哈希,而这个值将来要拿去
        // 比对下载物——现在不拦,到那时会变成一个"永远对不上"的哑失败。
        let sha = r.latest.sha256.lowercased()
        guard sha.count == 64, sha.allSatisfy({ $0.isHexDigit }) else {
            throw UpdateError.malformedFeed("sha256 不是 64 位十六进制")
        }
        guard r.latest.size > 0 else { throw UpdateError.malformedFeed("size 必须为正") }
        guard r.seq > 0 else { throw UpdateError.malformedFeed("seq 必须为正") }

        var revoked: SemanticVersion?
        if let rb = r.revokedBelow, !rb.isEmpty {
            guard let v = SemanticVersion(rb) else {
                throw UpdateError.malformedFeed("revokedBelow 解不出:\(rb)")
            }
            revoked = v
        }

        return UpdateManifest(
            schema: r.schema, seq: r.seq, issuedAt: issued, expiresAt: expires,
            channel: r.channel,
            latest: Release(version: version, build: r.latest.build,
                            minimumSystemVersion: minSystem, arch: r.latest.arch,
                            url: url, size: r.latest.size, sha256: sha, notesURL: notes),
            revokedBelow: revoked, revokeKeys: r.revokeKeys ?? [],
            signedByKeyID: keyID)
    }
}
