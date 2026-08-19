import SwiftUI

/// App 自己的确认框。
///
/// 系统的 `confirmationDialog` 在这里不合用:它的底衬是半透明材质,压在编辑
/// 画布上时后面的图会透过来,字和按钮都糊;按钮配色也归系统管,和 App 其余
/// 部分对不上。自己画一个:实心底、看得清、按钮用 App 已有的那三种样式。
struct ConfirmDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    /// 破坏性操作用加深的红,其余用品牌色。
    var destructive = true
    let cancelTitle: String
    /// 可选的附加勾选项。给出标题就多一行复选框,确认时把它的值交回去。
    ///
    /// 做成对话框自己的 @State 而不是外部 Binding:它的生命周期就是这次对话
    /// 的生命周期,交给外面存反而要记得在每次弹出前清掉——忘一次,用户上次
    /// 勾的「连图一起删」就会在下一次对话里默认选中。
    var toggleTitle: String? = nil
    let onConfirm: (Bool) -> Void
    let onCancel: () -> Void

    @State private var toggleOn = false

    var body: some View {
        ZStack {
            // 遮罩压暗背景,顺便吃掉穿透的点击。
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 6) {
                Text(title).font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let toggleTitle {
                    Toggle(isOn: $toggleOn) { Text(toggleTitle).font(.callout) }
                        .toggleStyle(.checkbox)
                        .padding(.top, 10)
                }

                HStack(spacing: 10) {
                    Button(cancelTitle, action: onCancel)
                        .buttonStyle(QuietButton())
                        .keyboardShortcut(.cancelAction)
                    if destructive {
                        Button(confirmTitle) { onConfirm(toggleOn) }
                            .buttonStyle(SolidDangerButton())
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button(confirmTitle) { onConfirm(toggleOn) }
                            .buttonStyle(BrandButton())
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
            .frame(maxWidth: 360)
            // 实心底而不是材质:这层就该挡住后面的图。
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.13, green: 0.13, blue: 0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
        }
        .transition(.opacity)
    }
}

/// 实心的危险按钮。
///
/// 既有的 DangerButton 是"淡红底 + 红字",给设置页里那种不常按的退出用刚好;
/// 但确认框里它就是主操作,得一眼看出按哪个——实心红底配白字。
struct SolidDangerButton: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        let base = Color(red: 0.83, green: 0.24, blue: 0.24)
        return configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: Metrics.control)
            .background(shape.fill(
                configuration.isPressed ? base.opacity(0.82) : hovering ? base.opacity(0.92) : base
            ))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.1), value: hovering)
    }
}
