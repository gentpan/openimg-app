import SwiftUI
import OpenimgKit

/// 设置页里三个模态表单。用枚举而不是三个 Bool:同一时刻只能开一个,
/// 三个布尔量可以同时为真,那是个装不下的状态。
enum SettingsSheet: Identifiable {
    case password
    /// nil 新建,非 nil 编辑。
    case storage(StorageProfile?)

    var id: String {
        switch self {
        case .password: "password"
        case .storage(let p): "storage-\(p?.id ?? "new")"
        }
    }
}

/// 改密码 / 设置密码。
///
/// 不再打开即发码。原来是"这个窗存在的唯一目的就是收码改密,再点一次只是多
/// 一道手续"——但那意味着误点一次「修改密码」就烧掉一封受频率限制的邮件,
/// 而用户此刻可能只是想看看这里有什么。发信是个有代价的动作,应该由人按下去。
struct PasswordSheet: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void

    @State private var code = ""
    @State private var pw = ""
    @State private var pw2 = ""

    private var hasPassword: Bool { model.account?.hasPassword ?? true }
    private var tooShort: Bool { !pw.isEmpty && pw.count < 8 }
    private var mismatch: Bool { !pw2.isEmpty && pw != pw2 }
    private var ready: Bool { code.count == 6 && pw.count >= 8 && pw == pw2 }

    var body: some View {
        FormSheet(
            title: hasPassword ? L.s.settings.changePassword : L.s.settings.setPassword,
            subtitle: model.codeSentTo.isEmpty
                ? L.s.settings.codeWillSendHint
                : L.s.settings.codeSentTo(model.codeSentTo)
        ) {
            Field(icon: "number") {
                TextField(L.s.settings.codeField, text: $code)
            }
            Field(icon: "lock") {
                SecureField(hasPassword ? L.s.settings.newPasswordField : L.s.settings.passwordField,
                            text: $pw)
            }
            Field(icon: "lock.rotation") {
                SecureField(L.s.settings.repeatPasswordField, text: $pw2)
            }
            if tooShort {
                Text(L.s.settings.passwordTooShort).font(.caption2).foregroundStyle(.orange)
            } else if mismatch {
                Text(L.s.settings.passwordMismatch).font(.caption2).foregroundStyle(.orange)
            }
        } footer: {
            // 没发过是「发送验证码」且是主按钮——此刻它是唯一能往下走的路;
            // 发过之后降级成安静的「重发」,让位给「确认修改」。
            if model.codeSent {
                Button(model.codeCooldown > 0
                       ? L.s.settings.resendIn(model.codeCooldown) : L.s.settings.resendCode) {
                    Task { await model.sendCode(.password) }
                }
                .buttonStyle(QuietButton())
                .disabled(model.codeCooldown > 0 || model.busy)
            } else {
                Button(L.s.settings.sendCode) { Task { await model.sendCode(.password) } }
                    .buttonStyle(BrandButton())
                    .disabled(model.busy)
            }

            Spacer()

            Button(L.s.settings.cancel) { close() }
                .buttonStyle(QuietButton())
                .keyboardShortcut(.cancelAction)

            Button(hasPassword ? L.s.settings.confirmChange : L.s.settings.confirmSet) {
                Task {
                    if await model.changePassword(code: code, newPassword: pw) { close() }
                }
            }
            .buttonStyle(BrandButton())
            .keyboardShortcut(.defaultAction)
            .disabled(!ready || model.busy)
        }

    }

    private func close() {
        model.codeSent = false
        onClose()
    }
}

