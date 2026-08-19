import Foundation

/// Signs in with an email and password, and comes back with a long-lived API
/// token rather than a session.
///
/// The session cookie is deliberately not what gets kept. It expires after
/// seven days and the server has no refresh endpoint, so an app that stored it
/// would silently log the user out every week — the opposite of staying signed
/// in. A personal access token has no such clock, and it is also the only
/// credential the upload and gallery routes accept.
///
/// So the password buys a session, the session mints a token, and the session
/// is then thrown away. This is the same exchange a CLI tool does at `login`.
///
/// What a token cannot do is equally deliberate on the server side: minting
/// more tokens, changing the password, and deleting the account are all
/// cookie-only. A leaked token cannot escalate into an account takeover.
public enum OpenimgAuth {
    /// The private URL scheme the OAuth callback redirects to. Must match
    /// CFBundleURLSchemes in the app bundle, and `NativeScheme` on the server.
    public static let nativeScheme = "openimg"


    /// Named per device so signing in again replaces this Mac's token instead
    /// of adding another. The server caps a user at ten, and without this a
    /// handful of re-logins would exhaust the allowance with dead entries.
    public static func tokenName(device: String) -> String { "Openimg for Mac · \(device)" }

    public static func signIn(
        server: URL,
        email: String,
        password: String,
        device: String,
        expiresInDays: Int = 365,
        session: URLSession = .shared
    ) async throws -> (token: String, account: Account) {
        try validate(server)

        // 1. Password → session cookie. URLSession stores it for us and sends
        //    it on the follow-up calls to the same host.
        let account: Account = try await post(
            server: server, path: "auth/login", session: session,
            body: ["email": email, "password": password]
        )

        // 2. Retire any token this device left behind, so the ten-token budget
        //    does not fill with entries from previous sign-ins.
        let name = tokenName(device: device)
        if let existing: TokenList = try? await get(server: server, path: "api/tokens", session: session) {
            for t in existing.tokens where t.name == name && !t.revoked {
                _ = try? await delete(server: server, path: "api/tokens/\(t.id)", session: session)
            }
        }

        // 3. Mint the credential the app will actually live on.
        let minted: MintedToken = try await post(
            server: server, path: "api/tokens", session: session,
            body: ["name": name, "expires_in_days": expiresInDays]
        )

        // 4. Drop the session. The app does not use it after this, and leaving
        //    it in the shared cookie store means a credential lying around that
        //    nothing is watching the lifetime of.
        clearCookies(for: server, session: session)

        return (minted.plain, account)
    }

    /// 退出时令牌**会**在服务器上作废。
    ///
    /// 这曾经做不到:删令牌那条路只认 cookie 会话,而这个客户端拿的是令牌。
    /// 那道边界的用意是别让一枚泄露的令牌去改动账号凭据——用意是对的,但它
    /// 连"注销自己"也一并挡住了,于是退出只是本机抹掉,服务器上那枚照旧有效。
    /// 提示语让用户去网站删,现实是没人会去。
    ///
    /// 现在多了一条 DELETE /api/tokens/current,只能删调用者自己那一枚。方向
    /// 是收权不是放权,原来那道边界完好:任意删别人那条仍然只认 cookie。
    ///
    /// 撤销走网络,所以可能失败。失败不阻断退出——用户要的是从这台机器下线,
    /// 网络出问题时把他卡在登录态毫无道理——但要如实说,而不是笼统报"已退出"。
    public static let signedOutAndRevoked = """
        已退出，这枚令牌也已在服务器上作废。
        """

    /// 撤销没成时的说法。别把它写成"已退出"就完事:服务器上那枚还能用,
    /// 用户有权知道,也有权自己去补一刀。
    public static let signOutIsLocalOnly = """
        已从这台设备退出，但没能在服务器上作废那枚令牌（网络问题）。\
        它仍然有效，可以在网站的「账号设置 → API Token」里手动删除。
        """

    /// Trades the one-time code an OAuth callback handed back for a token.
    ///
    /// The code is single-use and expires in a minute; it grants nothing on its
    /// own, which is why it is safe to carry in a URL that other processes on
    /// the machine could in principle observe.
    public static func exchange(
        server: URL, code: String, device: String, session: URLSession = .shared
    ) async throws -> (token: String, account: Account) {
        try validate(server)
        struct Result: Decodable {
            let plain: String
            let user: Account
        }
        let r: Result = try await post(
            server: server, path: "auth/native/exchange", session: session,
            body: ["code": code, "device": device]
        )
        return (r.plain, r.user)
    }

    // MARK: - Plumbing

    static func validate(_ server: URL) throws {
        guard let host = server.host, !host.isEmpty else { throw OpenimgError.badServerURL }
        let loopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        if server.scheme != "https" && !loopback { throw OpenimgError.insecureServer(host: host) }
    }

    private static func clearCookies(for server: URL, session: URLSession) {
        let store = session.configuration.httpCookieStorage ?? .shared
        store.cookies(for: server)?.forEach(store.deleteCookie)
    }

    private static func decode<T: Decodable>(_ data: Data, _ resp: URLResponse) throws -> T {
        guard let http = resp as? HTTPURLResponse else { throw OpenimgError.transport("没有 HTTP 响应") }
        guard (200..<300).contains(http.statusCode) else {
            throw signInFailure(status: http.statusCode, body: data, headers: http)
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601WithFractionalSeconds
        do { return try dec.decode(T.self, from: data) } catch {
            throw OpenimgError.transport("响应解析失败：\(error.localizedDescription)")
        }
    }

    /// The server answers a wrong password with the English string
    /// "invalid credentials", which is not something to show a user.
    static func signInFailure(status: Int, body: Data, headers: HTTPURLResponse) -> OpenimgError {
        let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let raw = obj["error"] as? String ?? ""
        switch (status, raw) {
        case (401, _), (_, "invalid credentials"):
            return .rejected(status: status, message: "邮箱或密码不对")
        case (403, "account suspended"):
            return .rejected(status: status, message: "账号已被停用")
        case (403, _) where (obj["code"] as? String) == "email_unverified":
            return .rejected(status: status, message: "请先在网站上验证邮箱")
        default:
            return OpenimgClient.failure(status: status, body: body, headers: headers)
        }
    }

    private static func request(_ method: String, server: URL, path: String) -> URLRequest {
        var req = URLRequest(url: server.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private static func post<T: Decodable>(server: URL, path: String, session: URLSession,
                                           body: [String: Any]) async throws -> T {
        var req = request("POST", server: server, path: path)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        return try decode(data, resp)
    }

    private static func get<T: Decodable>(server: URL, path: String, session: URLSession) async throws -> T {
        let (data, resp) = try await session.data(for: request("GET", server: server, path: path))
        return try decode(data, resp)
    }

    private static func delete(server: URL, path: String, session: URLSession) async throws -> Bool {
        let (_, resp) = try await session.data(for: request("DELETE", server: server, path: path))
        return (resp as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
    }

    struct MintedToken: Decodable { let plain: String }
    struct TokenList: Decodable {
        let tokens: [Item]
        struct Item: Decodable {
            let id: String
            let name: String
            let revoked: Bool
        }
    }
}
