import Foundation

/// 登录页与 OAuth 流程的文案。
///
/// 标题拆成 `headerPrefix` + 品牌字（"Open"/"Img" 用 Ubuntu 单独排），所以这里
/// 只放前半句,末尾那个空格是排版的一部分,别顺手删掉。
struct LoginStrings: Sendable {
    let serverSwitch: String
    let serverField: String
    let serverApply: String
    let serverReset: String
    let serverCurrent: @Sendable (String) -> String
    let tagline: String

    let emailPlaceholder: String
    let passwordPlaceholder: String

    let submit: String
    let submitting: String
    let orDivider: String

    /// 第三方登录按钮的无障碍标签,参数是渠道名(Google / GitHub / Passkey)。
    let signInWith: @Sendable (String) -> String


    // 注册。与登录共用邮箱和密码两栏,所以这里只补它多出来的那几样。
    let passkeyFallingBack: String
    let passkeyNotSetUp: String
    let modeSignIn: String
    let modeRegister: String
    let namePlaceholder: String
    /// 密码要求写在占位符里而不是错误提示里:让人先知道,而不是提交完被拒。
    let passwordNewPlaceholder: String
    let codePlaceholder: String
    let sendCode: String
    /// 倒计时中的按钮文案,参数是剩余秒数。
    let resendIn: @Sendable (Int) -> String
    let regCodeSent: @Sendable (String) -> String
    let registerSubmit: String
    let haveAccount: String
    let noAccount: String

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
        tagline: "图片托管与分发",
        emailPlaceholder: "you@example.com",
        passwordPlaceholder: "密码",
        submit: "登录",
        submitting: "登录中…",
        orDivider: "或",
        signInWith: { provider in "使用 \(provider) 登录" },

        passkeyFallingBack: "这台设备上还没有 openimg.io 的 Passkey，先用网页登录；登录后可在「设置 → 登录与安全」里添加。",
        passkeyNotSetUp: "这台设备还没有 Passkey —— 先用其他方式登录，再到「设置 → 登录与安全」添加",
        modeSignIn: "登录",
        modeRegister: "注册",
        namePlaceholder: "昵称",
        passwordNewPlaceholder: "密码（至少 8 位）",
        codePlaceholder: "邮箱验证码（6 位）",
        sendCode: "发送验证码",
        resendIn: { s in "\(s) 秒后重发" },
        regCodeSent: { email in "验证码已发到 \(email)，5 分钟内有效" },
        registerSubmit: "创建账号",
        haveAccount: "已有账号？",
        noAccount: "还没有账号？",
        passwordNote: "密码只用来换取一枚这台设备专用的令牌，不会被保存",
        callbackMissingCode: "登录回调里没有拿到登录码",
        cannotOpenAuthWindow: "无法打开登录窗口")

    static let en = LoginStrings(
        serverSwitch: "Use a self-hosted instance",
        serverField: "Server URL",
        serverApply: "Use this server",
        serverReset: "Back to official",
        serverCurrent: { s in "Server: \(s)" },
        tagline: "Image hosting and delivery",
        emailPlaceholder: "you@example.com",
        passwordPlaceholder: "Password",
        submit: "Sign In",
        submitting: "Signing In…",
        orDivider: "or",
        signInWith: { provider in "Sign in with \(provider)" },

        passkeyFallingBack: "No passkey for openimg.io on this Mac yet — signing in via the web; you can add one in Settings afterwards.",
        passkeyNotSetUp: "No passkey on this Mac yet — sign in another way first, then add one in Settings",
        modeSignIn: "Sign in",
        modeRegister: "Sign up",
        namePlaceholder: "Display name",
        passwordNewPlaceholder: "Password (at least 8 characters)",
        codePlaceholder: "Email code (6 digits)",
        sendCode: "Send code",
        resendIn: { s in "Resend in \(s)s" },
        regCodeSent: { email in "Code sent to \(email) — valid for 5 minutes" },
        registerSubmit: "Create account",
        haveAccount: "Already have an account?",
        noAccount: "No account yet?",
        passwordNote: "Your password is only used to get a token for this Mac — it is never saved",
        callbackMissingCode: "The sign-in callback did not include an authorization code",
        cannotOpenAuthWindow: "Could not open the sign-in window")
}
