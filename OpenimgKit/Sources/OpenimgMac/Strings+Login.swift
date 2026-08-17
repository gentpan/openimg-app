import Foundation

/// 登录页与 OAuth 流程的文案。
///
/// 标题拆成 `headerPrefix` + 品牌字（"Open"/"img" 用 Ubuntu 单独排），所以这里
/// 只放前半句,末尾那个空格是排版的一部分,别顺手删掉。
struct LoginStrings: Sendable {
    let serverSwitch: String
    let serverField: String
    let serverApply: String
    let serverReset: String
    let serverCurrent: @Sendable (String) -> String
    let headerPrefix: String
    let tagline: String

    let emailPlaceholder: String
    let passwordPlaceholder: String
    let tokenPlaceholder: String

    let submit: String
    let submitting: String
    let orDivider: String

    /// 第三方登录按钮的无障碍标签,参数是渠道名(Google / GitHub / Passkey)。
    let signInWith: @Sendable (String) -> String

    let usePasswordSignIn: String
    let useTokenSignIn: String

    let tokenNote: String
    let passwordNote: String

    let callbackMissingCode: String
    let cannotOpenAuthWindow: String
}

extension LoginStrings {
    static let zh = LoginStrings(
        serverSwitch: "使用自建实例",
        serverField: "服务器地址",
        serverApply: "使用这个地址",
        serverReset: "改回官方",
        serverCurrent: { s in "服务器：\(s)" },
        headerPrefix: "登录 ",
        tagline: "图片托管与分发",
        emailPlaceholder: "you@example.com",
        passwordPlaceholder: "密码",
        tokenPlaceholder: "oimg_…",
        submit: "登录",
        submitting: "登录中…",
        orDivider: "或",
        signInWith: { provider in "使用 \(provider) 登录" },
        usePasswordSignIn: "改用邮箱密码登录",
        useTokenSignIn: "改用访问令牌登录",
        tokenNote: "令牌保存在钥匙串，不写入配置文件",
        passwordNote: "密码只用来换取一枚这台设备专用的令牌，不会被保存",
        callbackMissingCode: "登录回调里没有拿到登录码",
        cannotOpenAuthWindow: "无法打开登录窗口")

    static let en = LoginStrings(
        serverSwitch: "Use a self-hosted instance",
        serverField: "Server URL",
        serverApply: "Use this server",
        serverReset: "Back to official",
        serverCurrent: { s in "Server: \(s)" },
        headerPrefix: "Sign in to ",
        tagline: "Image hosting and delivery",
        emailPlaceholder: "you@example.com",
        passwordPlaceholder: "Password",
        tokenPlaceholder: "oimg_…",
        submit: "Sign In",
        submitting: "Signing In…",
        orDivider: "or",
        signInWith: { provider in "Sign in with \(provider)" },
        usePasswordSignIn: "Use email and password instead",
        useTokenSignIn: "Use an access token instead",
        tokenNote: "The token is stored in the Keychain, never in a config file",
        passwordNote: "Your password is only used to get a token for this Mac — it is never saved",
        callbackMissingCode: "The sign-in callback did not include an authorization code",
        cannotOpenAuthWindow: "Could not open the sign-in window")
}
