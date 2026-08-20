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
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 遮罩与内容共用一个进度:它们必须同时到位。分别各跑一段的话,会看到底
    /// 色已经压暗、框还在半路——那一瞬间像是卡了一下。
    @State private var shown = false

    var body: some View {
        ZStack {
            // 遮罩压暗背景,顺便吃掉穿透的点击。
            Color.black.opacity(shown ? 0.55 : 0)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 6) {
                Text(title).font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(cancelTitle, action: onCancel)
                        .buttonStyle(QuietButton())
                        .keyboardShortcut(.cancelAction)
                    if destructive {
                        Button(confirmTitle, action: onConfirm)
                            .buttonStyle(SolidDangerButton())
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button(confirmTitle, action: onConfirm)
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
            // 0.96 起,不是 0.9:后者看着像"弹出来",而这里要的是它本来就在那
            // 儿、刚对上焦。250ms——弹窗是用户刚点出来的,他已经在等它了,慢一
            // 点就是迟钝。
            .scaleEffect(shown ? 1 : 0.96)
            .opacity(shown ? 1 : 0)
            .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
        }
        .onAppear {
            guard !shown else { return }
            guard !reduceMotion else { shown = true; return }
            withAnimation(ModalEntrance.curve) { shown = true }
        }
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
