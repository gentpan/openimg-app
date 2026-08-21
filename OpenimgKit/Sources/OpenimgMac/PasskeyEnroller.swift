import AppKit
import AuthenticationServices
import OpenimgKit

/// 原生 Passkey 注册仪式(Touch ID / iPhone 确认)。
///
/// 真签名构建带着 `webcredentials:openimg.io` 的 associated-domains
/// entitlement,系统据此确认「这个 App 有资格替该域名注册凭证」;ad-hoc
/// 构建无法证明域名归属,系统会以 ASAuthorizationError 拒绝——调用方
/// 拿到错误后解释原因并指去网站,而不是装作没有这个功能。
final class PasskeyEnroller: NSObject, @unchecked Sendable,
                             ASAuthorizationControllerDelegate,
                             ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationPlatformPublicKeyCredentialRegistration, Error>?
    private var assertContinuation: CheckedContinuation<ASAuthorizationPlatformPublicKeyCredentialAssertion, Error>?
    private var controller: ASAuthorizationController?

    func register(rpID: String, challenge: Data, userID: Data,
                  userName: String) async throws
        -> ASAuthorizationPlatformPublicKeyCredentialRegistration {
        try await withCheckedThrowingContinuation { cont in
            continuation = cont
            let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
                relyingPartyIdentifier: rpID)
            let request = provider.createCredentialRegistrationRequest(
                challenge: challenge, name: userName, userID: userID)
            let c = ASAuthorizationController(authorizationRequests: [request])
            c.delegate = self
            c.presentationContextProvider = self
            controller = c
            c.performRequests()
        }
    }

    /// 登录用的断言仪式。
    ///
    /// 与注册同一个 provider,差别只在请求类型:注册是"造一把新钥匙",登录是
    /// "用已有的钥匙签一下挑战"。所以复用同一个 controller 与同一套回调。
    ///
    /// 不传 allowedCredentials:让系统把这台设备上、这个域名下的凭证都列出来
    /// 由用户挑。传了的话就得先问服务器"这个邮箱有哪些凭证",而那一问本身
    /// 会泄露某个邮箱注册过没有。
    func assert(rpID: String, challenge: Data, immediateOnly: Bool = true) async throws
        -> ASAuthorizationPlatformPublicKeyCredentialAssertion {
        try await withCheckedThrowingContinuation { cont in
            assertContinuation = cont
            let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
                relyingPartyIdentifier: rpID)
            let request = provider.createCredentialAssertionRequest(challenge: challenge)
            let c = ASAuthorizationController(authorizationRequests: [request])
            c.delegate = self
            c.presentationContextProvider = self
            controller = c
            // 两条路,差别在于「要不要跨设备」。
            //
            // immediateOnly:只认这台机器上立即可用的凭证,没有就**立刻失败**,
            // 而不是弹一个空面板让用户对着发呆。用在完全不知道有没有 Passkey
            // 的时候——没有它,"还没创建过"和"用户按了取消"在调用方看来一模
            // 一样,只能笼统回落。
            //
            // 完整流程:系统会把「用附近设备上的 Passkey」也列出来(扫码 / 蓝牙)。
            // 已知账号有 Passkey 时必须走这条——凭证很可能在 iPhone 上,而
            // immediateOnly 会把那条路一并挡掉。
            if immediateOnly {
                c.performRequests(options: .preferImmediatelyAvailableCredentials)
            } else {
                c.performRequests()
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        if let asr = authorization.credential
            as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            assertContinuation?.resume(returning: asr)
            assertContinuation = nil
            return
        }
        if let reg = authorization.credential
            as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
            continuation?.resume(returning: reg)
        } else {
            continuation?.resume(
                throwing: OpenimgError.transport(L.s.settings.passkeyUnknownCredential))
        }
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        assertContinuation?.resume(throwing: error)
        assertContinuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
        }
    }
}

extension AppModel {
    /// 完整注册流:OTP → begin(拿挑战) → 系统仪式 → finish(交凭证)。
    /// rp.id 用服务器下发的值而不是写死——自建实例换域名时 Kit 不用改。
    func enrollPasskey(code: String, name: String) async -> Bool {
        guard let account else { return false }
        do {
            let begin = try await client().passkeyEnrollBegin(code: code)
            let pk = begin.options.publicKey
            guard let challenge = Data(base64URL: pk.challenge),
                  let userID = Data(base64URL: pk.user.id) else {
                announce(L.s.settings.passkeyChallengeUnreadable)
                return false
            }
            let reg = try await PasskeyEnroller().register(
                rpID: pk.rp.id,
                challenge: challenge,
                userID: userID,
                userName: pk.user.name ?? account.email)
            guard let att = reg.rawAttestationObject else {
                announce(L.s.settings.passkeyNoCredential)
                return false
            }
            try await client().passkeyEnrollFinish(
                flow: begin.flow,
                name: name,
                credential: WebAuthnRegistration(credentialID: reg.credentialID,
                                                 attestationObject: att,
                                                 clientDataJSON: reg.rawClientDataJSON))
            await loadPasskeys()
            hasLocalPasskey = true
            passkeyCodeSent = false
            announce(L.s.settings.passkeyAdded)
            return true
        } catch let e as ASAuthorizationError where e.code == .canceled {
            return false // 用户自己关掉的,不聒噪
        } catch is ASAuthorizationError {
            // ad-hoc 构建走到这:无 entitlement,系统拒绝为域名创建凭证
            announce(L.s.settings.passkeyUnsignedBuild, seconds: 9)
            return false
        } catch {
            announce(message(error))
            return false
        }
    }
}
