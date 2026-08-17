import SwiftUI
import OpenimgKit

/// 设置页里三个模态表单。用枚举而不是三个 Bool:同一时刻只能开一个,
/// 三个布尔量可以同时为真,那是个装不下的状态。
enum SettingsSheet: Identifiable {
    case password
    case passkey
    /// nil 新建,非 nil 编辑。
    case storage(StorageProfile?)

    var id: String {
        switch self {
        case .password: "password"
        case .passkey: "passkey"
        case .storage(let p): "storage-\(p?.id ?? "new")"
        }
    }
}

/// 改密码 / 设置密码。
///
/// 打开即发码,和网页端的 OtpConfirm 一样——这个窗存在的唯一目的就是收码
/// 改密,让用户再点一次"发送验证码"只是多一道手续。
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
            Button(model.codeCooldown > 0
                   ? L.s.settings.resendIn(model.codeCooldown) : L.s.settings.resendCode) {
                Task { await model.sendCode(.password) }
            }
            .buttonStyle(QuietButton())
            .disabled(model.codeCooldown > 0 || model.busy)

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
        .task { if !model.codeSent { await model.sendCode(.password) } }
    }

    private func close() {
        model.codeSent = false
        onClose()
    }
}

/// 添加 Passkey。同样打开即发码。
struct PasskeySheet: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void

    @State private var code = ""
    @State private var name = ""

    var body: some View {
        FormSheet(
            title: L.s.settings.addPasskey,
            subtitle: model.pkCodeSentTo.isEmpty
                ? L.s.settings.passkeyHint
                : L.s.settings.codeSentTo(model.pkCodeSentTo)
        ) {
            Field(icon: "number") {
                TextField(L.s.settings.codeField, text: $code)
            }
            Field(icon: "pencil") {
                TextField(L.s.settings.passkeyNameField, text: $name)
            }
        } footer: {
            Button(model.pkCodeCooldown > 0
                   ? L.s.settings.resendIn(model.pkCodeCooldown) : L.s.settings.resendCode) {
                Task { await model.sendCode(.passkey) }
            }
            .buttonStyle(QuietButton())
            .disabled(model.pkCodeCooldown > 0 || model.busy)

            Spacer()

            Button(L.s.settings.cancel) { close() }
                .buttonStyle(QuietButton())
                .keyboardShortcut(.cancelAction)

            Button(L.s.settings.addPasskey) {
                Task {
                    if await model.enrollPasskey(code: code,
                                                 name: name.isEmpty ? "Mac" : name) { close() }
                }
            }
            .buttonStyle(BrandButton())
            .keyboardShortcut(.defaultAction)
            .disabled(code.count != 6 || model.busy)
        }
        .task { if !model.passkeyCodeSent { await model.sendCode(.passkey) } }
    }

    private func close() {
        model.passkeyCodeSent = false
        onClose()
    }
}
