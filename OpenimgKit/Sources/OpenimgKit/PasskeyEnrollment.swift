import Foundation

/// WebAuthn 注册的传输模型,与后端 go-webauthn 的
/// `protocol.CredentialCreation` / `CredentialCreationResponse` 逐字段对齐;
/// 二进制字段一律无填充 base64url(WebAuthn 线格式)。
///
/// 只声明原生仪式用得到的字段——`options` 里还有 pubKeyCredParams、
/// timeout 等,Apple 的 ASAuthorization 不收它们,解了也没处放。
public struct PasskeyEnrollStart: Codable, Sendable {
    public let flow: String
    public let options: CreationOptions

    public struct CreationOptions: Codable, Sendable {
        public let publicKey: PublicKey
    }

    public struct PublicKey: Codable, Sendable {
        public let challenge: String
        public let rp: RP
        public let user: User

        public struct RP: Codable, Sendable {
            public let id: String
            public let name: String?
        }
        public struct User: Codable, Sendable {
            public let id: String
            public let name: String?
            public let displayName: String?
        }
    }
}

/// `navigator.credentials.create` 结果的等价物,后端
/// `protocol.CredentialCreationResponse` 按此形状解析。
public struct WebAuthnRegistration: Encodable, Sendable {
    public let id: String
    public let rawId: String
    public var type = "public-key"
    public let response: Response

    public struct Response: Encodable, Sendable {
        public let attestationObject: String
        public let clientDataJSON: String
    }

    public init(credentialID: Data, attestationObject: Data, clientDataJSON: Data) {
        id = credentialID.base64URLEncoded
        rawId = credentialID.base64URLEncoded
        response = Response(attestationObject: attestationObject.base64URLEncoded,
                            clientDataJSON: clientDataJSON.base64URLEncoded)
    }
}

public extension Data {
    /// 无填充 base64url。
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// 接受无填充与带填充两种写法——go-webauthn 发无填充,别处来的
    /// 字符串可能带,都认。
    init?(base64URL s: String) {
        var b = s.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b.append("=") }
        self.init(base64Encoded: b)
    }
}

/// 登录仪式的 begin 响应。
///
/// 与注册那份的形状不同:登录不需要 user 段(用哪把钥匙由系统和用户决定),
/// 只要挑战和 rp.id。单独一个类型而不是把 user 改成可选——两件事拿到的东西
/// 本来就不一样,共用一个可选字段满地的模型只会让调用点到处解包。
public struct PasskeyLoginStart: Codable, Sendable {
    public let flow: String
    public let options: RequestOptions

    public struct RequestOptions: Codable, Sendable {
        public let publicKey: PublicKey
    }
    public struct PublicKey: Codable, Sendable {
        public let challenge: String
        public let rpId: String?
    }
}

/// 交回服务器的断言。字段名与 WebAuthn 的 JSON 表示一致。
public struct WebAuthnAssertion: Encodable, Sendable {
    public let id: String
    public let rawId: String
    public let type: String
    public let response: Response

    public struct Response: Encodable, Sendable {
        public let clientDataJSON: String
        public let authenticatorData: String
        public let signature: String
        public let userHandle: String?

        public init(clientDataJSON: String, authenticatorData: String,
                    signature: String, userHandle: String?) {
            self.clientDataJSON = clientDataJSON
            self.authenticatorData = authenticatorData
            self.signature = signature
            self.userHandle = userHandle
        }
    }

    public init(id: String, rawId: String, type: String = "public-key", response: Response) {
        self.id = id
        self.rawId = rawId
        self.type = type
        self.response = response
    }
}
