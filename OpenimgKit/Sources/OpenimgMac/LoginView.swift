import SwiftUI
import OpenimgKit

/// Sign-in as its own screen rather than a section inside settings: it is the
/// one thing a new user must do, and burying it under a heading gave it the
/// same weight as everything they cannot do yet.
struct LoginView: View {
    @ObservedObject var model: AppModel
    @State private var showServer = false
    @State private var serverDraft = ""

    var body: some View {
        ZStack {
            // A wash of brand colour so the card has something to be
            // translucent against rather than flat black.
            RadialGradient(colors: [Color.brand.opacity(0.28), .clear],
                           center: .init(x: 0.5, y: 0.15), startRadius: 30, endRadius: 560)
                .ignoresSafeArea()
            card
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var card: some View {
        VStack(spacing: 16) {
            header

            VStack(spacing: 8) {
                Field(icon: "envelope.fill") {
                    TextField(L.s.login.emailPlaceholder, text: $model.email)
                }
                Field(icon: "lock.fill") {
                    SecureField(model.registering ? L.s.login.passwordNewPlaceholder
                                                  : L.s.login.passwordPlaceholder,
                                text: $model.password)
                        .onSubmit { Task { await model.primaryAction() } }
                }
                if model.registering {
                    Field(icon: "person.fill") {
                        TextField(L.s.login.namePlaceholder, text: $model.regName)
                    }
                    // 验证码与"发送"并排:分成两行的话,用户填完邮箱要往下
                    // 找按钮、发完再往上填码,顺序是拧的。
                    HStack(spacing: 8) {
                        Field(icon: "number") {
                            TextField(L.s.login.codePlaceholder, text: $model.regCode)
                                .onSubmit { Task { await model.primaryAction() } }
                        }
                        Button(model.regCooldown > 0
                               ? L.s.login.resendIn(model.regCooldown)
                               : L.s.login.sendCode) {
                            Task { await model.sendRegisterCode() }
                        }
                        .buttonStyle(QuietButton())
                        .frame(height: Metrics.field)
                        .disabled(!model.canSendRegCode)
                    }
                }
            }

            // 登录 / 注册切换。
            Picker("", selection: Binding(
                get: { model.registering },
                set: { model.registering = $0 }
            )) {
                Text(L.s.login.modeSignIn).tag(false)
                Text(L.s.login.modeRegister).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .padding(.bottom, 2)

            Button {
                Task { await model.primaryAction() }
            } label: {
                HStack(spacing: 7) {
                    if model.busy { ProgressView().controlSize(.small).tint(.white) }
                    Text(model.busy ? L.s.login.submitting
                         : (model.registering ? L.s.login.registerSubmit : L.s.login.submit))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(BrandButton())
            .disabled(model.busy || !model.canSubmit)
            .keyboardShortcut(.defaultAction)

            divider

            // Three equal tiles. Icon-only because the marks carry the meaning
            // better than a label does at this size, and three full-width rows
            // would make the alternatives outrank the main path.
            HStack(spacing: 8) {
                ForEach(SignInMethod.allCases) { m in
                    Button { Task { await model.signIn(with: m) } } label: {
                        m.mark
                            .frame(width: 20, height: 20)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(QuietButton())
                    .disabled(model.busy)
                    .help(m.title)
                    .accessibilityLabel(L.s.login.signInWith(m.title))
                }
            }

            // Said before the field is filled in, not after: "we store a token,
            // not your password" only reassures in advance.
            Text(L.s.login.passwordNote)
                .font(.caption2).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            serverRow
        }
        .padding(26)
        .frame(width: 348)
        .panelSurface(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial)
        )
        .shadow(color: .black.opacity(0.45), radius: 28, y: 12)
    }

    /// 自建实例入口。
    ///
    /// 默认折叠:后端是 MIT 开源可自建的,把地址写死等于告诉自建者"这个 App
    /// 不是给你的";但给普通用户一个常驻输入框,只会招来一个填错的地址。
    /// 所以默认只显示当前连的是哪儿,想改的人点一下展开。
    @ViewBuilder private var serverRow: some View {
        if showServer {
            VStack(spacing: 6) {
                Field(icon: "server.rack") {
                    TextField(L.s.login.serverField, text: $serverDraft)
                        .onSubmit { model.setServer(serverDraft) }
                }
                HStack(spacing: 8) {
                    Button(L.s.login.serverApply) { model.setServer(serverDraft) }
                        .buttonStyle(QuietButton())
                        .disabled(serverDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    if model.server != AppModel.officialServer {
                        Button(L.s.login.serverReset) {
                            model.setServer(AppModel.officialServer)
                            serverDraft = AppModel.officialServer
                        }
                        .buttonStyle(LinkButton()).font(.caption2)
                    }
                }
            }
            .padding(.top, 2)
        } else {
            Button {
                serverDraft = model.server
                withAnimation(.easeOut(duration: 0.15)) { showServer = true }
            } label: {
                Text(model.server == AppModel.officialServer
                     ? L.s.login.serverSwitch
                     : L.s.login.serverCurrent(model.server))
                    .font(.caption2)
            }
            .buttonStyle(LinkButton())
        }
    }

    private var header: some View {
        VStack(spacing: 9) {
            // 字标是这一页唯一的品牌元素(图标去掉了),所以比原来大一档——
            // 21pt 是当初配着上面那个 56pt 图标定的,单独站着就偏小了。
            //
            // Ubuntu 只用在字标上:它没有中文覆盖,让它在句子中间回落会把两种
            // 字体并进同一行。
            HStack(spacing: 0) {
                Text("Open").font(.brand(34, .bold))
                Text("Img").font(.brand(34, .bold)).foregroundStyle(Color.brand)
            }
            Text(L.s.login.tagline).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.bottom, 2)
    }

    private var divider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
            Text(L.s.login.orDivider).font(.caption2).foregroundStyle(.tertiary)
            Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
        }
    }
}

enum SignInMethod: String, CaseIterable, Identifiable {
    case google, github, passkey
    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: "Google"
        case .github: "GitHub"
        case .passkey: "Passkey"
        }
    }

    @ViewBuilder
    var mark: some View {
        switch self {
        case .google: GoogleMark()
        case .github: GitHubMark()
        case .passkey:
            // Touch ID is the shape people associate with a passkey on a Mac,
            // and being a system symbol it carries no brand restrictions.
            Image(systemName: "touchid")
                .font(.system(size: 19))
                .foregroundStyle(Color.brand)
        }
    }
}
