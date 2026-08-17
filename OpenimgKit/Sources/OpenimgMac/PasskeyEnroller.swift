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

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        if let reg = authorization.credential
            as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
            continuation?.resume(returning: reg)
        } else {
            continuation?.resume(throwing: OpenimgError.transport("系统返回了未知的凭证类型"))
        }
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
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
                announce("服务器返回的注册挑战无法解析")
                return false
            }
            let reg = try await PasskeyEnroller().register(
                rpID: pk.rp.id,
                challenge: challenge,
                userID: userID,
                userName: pk.user.name ?? account.email)
            guard let att = reg.rawAttestationObject else {
                announce("系统未返回注册凭证")
                return false
            }
            try await client().passkeyEnrollFinish(
                flow: begin.flow,
                name: name,
                credential: WebAuthnRegistration(credentialID: reg.credentialID,
                                                 attestationObject: att,
                                                 clientDataJSON: reg.rawClientDataJSON))
            await loadPasskeys()
            passkeyCodeSent = false
            announce("Passkey 已添加")
            return true
        } catch let e as ASAuthorizationError where e.code == .canceled {
            return false // 用户自己关掉的,不聒噪
        } catch is ASAuthorizationError {
            // ad-hoc 构建走到这:无 entitlement,系统拒绝为域名创建凭证
            announce("系统拒绝创建：此构建未正式签名，无法证明域名归属。请先在网站上添加，正式签名版发布后 App 内即可直接添加。", seconds: 9)
            return false
        } catch {
            announce(message(error))
            return false
        }
    }
}
