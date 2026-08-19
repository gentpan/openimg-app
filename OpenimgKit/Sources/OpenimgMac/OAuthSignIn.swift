import AppKit
import AuthenticationServices
import OpenimgKit

/// Google / GitHub sign-in through the system's web authentication sheet.
///
/// `ASWebAuthenticationSession` rather than opening the default browser: the
/// sheet is scoped to this app, tells us when it finished, and — importantly —
/// does not leave the user logged into the site in a browser they did not ask
/// to open. The cost is that the flow must end at a URL scheme we own, which
/// is why the server takes `?native=1` and redirects to `openimg://auth?code=`
/// instead of its usual redirect to `/`.
///
/// What comes back is a single-use code, not a credential. It expires in a
/// minute and is consumed on first use, so the value that crosses the process
/// boundary is worthless to anyone who intercepts it after the fact.
@MainActor
final class OAuthSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }

    /// Returns the one-time code, or nil when the user closed the sheet.
    func start(provider: String, server: String) async throws -> String? {
        try await run("\(server)/auth/\(provider)/start?native=1")
    }

    /// Opens the site's own sign-in page, which hands back a code once any
    /// method succeeds. Used for passkey, where the credential ceremony has to
    /// happen in a web context.
    func startWebLogin(server: String) async throws -> String? {
        try await run("\(server)/login?native=1")
    }

    private func run(_ address: String) async throws -> String? {
        guard let url = URL(string: address) else { throw OpenimgError.badServerURL }

        return try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(
                url: url, callbackURLScheme: OpenimgAuth.nativeScheme
            ) { callback, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    cont.resume(returning: nil) // 用户关掉了窗口，不是错误
                    return
                }
                if let error { cont.resume(throwing: error); return }
                guard let callback,
                      let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                          .queryItems?.first(where: { $0.name == "code" })?.value
                else {
                    cont.resume(throwing: OpenimgError.transport(L.s.login.callbackMissingCode))
                    return
                }
                cont.resume(returning: code)
            }
            s.presentationContextProvider = self
            // 复用 Safari 的登录态,不开无痕会话。
            //
            // 原来是 true,理由是"共用 cookie 会默默沿用上次在这台 Mac 上登录
            // 的账号"。那个顾虑成立,但代价被低估了:无痕意味着每一次点
            // Google 都要从头输一遍密码加二次验证,而这个窗口的尺寸是系统定
            // 的、改不了——于是每次登录都是一个又大又慢的全流程。
            //
            // 复用之后多数时候是一闪而过。想换账号就去 Safari 里退出,这是一
            // 次性的、可恢复的;而每次重输密码是每次都要付的成本。
            session = s
            if !s.start() {
                cont.resume(throwing: OpenimgError.transport(L.s.login.cannotOpenAuthWindow))
            }
        }
    }
}
