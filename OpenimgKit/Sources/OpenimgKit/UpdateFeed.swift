import Foundation

/// 去拉一次更新清单。
///
/// 只做"取回来并验",不做任何决策——决策在 `UpdatePolicy`,那是纯函数、测得到。
/// 这里唯一的职责是把网络这一层的怪相挡在外面。
public struct UpdateFeed: Sendable {
    private let session: URLSession
    private let url: URL
    private let publicKeys: [String: Data]

    public init(url: URL = UpdateKeys.feedURL,
                publicKeys: [String: Data] = UpdateKeys.publicKeys,
                session: URLSession? = nil) {
        self.url = url
        self.publicKeys = publicKeys
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            // 不用共享缓存:清单的新鲜度由服务端的短 TTL 管,再叠一层本地缓存
            // 只会让"撤回一个坏版本"更难推出去。
            cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
            cfg.timeoutIntervalForRequest = 15
            cfg.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: cfg)
        }
    }

    /// 取回并验签。任何一步不对都抛。
    public func fetch(revokedKeyIDs: Set<String> = []) async throws -> UpdateManifest {
        // 明文 http 直接拒,与 Client 的纪律一致。这条地址是编进二进制的常量,
        // 但常量会被改,而改错的表现是一条可被中间人替换的更新通道。
        guard url.scheme?.lowercased() == "https" else {
            throw UpdateError.badURL(url.absoluteString)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw UpdateError.feedUnavailable(0)
        }
        return try UpdateManifest.parse(
            data,
            contentType: http.value(forHTTPHeaderField: "Content-Type"),
            status: http.statusCode,
            publicKeys: publicKeys,
            revokedKeyIDs: revokedKeyIDs)
    }
}
