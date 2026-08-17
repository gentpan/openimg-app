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
            continuation?.resume(
                throwing: OpenimgError.transport(L.s.settings.passkeyUnknownCredential))
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
