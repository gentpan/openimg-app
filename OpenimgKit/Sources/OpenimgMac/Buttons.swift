import SwiftUI

/// One button vocabulary for the whole app.
///
/// Before this each view reached for `.borderedProminent`, `.bordered` or
/// `.plain` as it went, so the same weight of action looked different on every
/// page — which is most of what made the app read as rough rather than as one
/// product. Three roles, used consistently: brand for the one action a screen
/// is for, quiet for everything else, danger for the irreversible.
struct BrandButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            // Disabled takes a neutral fill rather than a faded brand one:
            // fading only the background leaves the label at full strength on a
            // surface that no longer supports it.
            .foregroundStyle(enabled ? AnyShapeStyle(Color.brandInk)
                                     : AnyShapeStyle(.tertiary))
            .padding(.horizontal, 15)
            .frame(height: Metrics.control)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(enabled ? AnyShapeStyle(Color.brand)
                                  : AnyShapeStyle(Color.white.opacity(0.08)))
                    .opacity(configuration.isPressed ? 0.78 : 1)
            )
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct QuietButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return configuration.label
            .font(.callout)
            .foregroundStyle(enabled ? .primary : .tertiary)
            .padding(.horizontal, 13)
            .frame(height: Metrics.control)
            .background(shape.fill(.white.opacity(
                configuration.isPressed ? 0.14 : hovering && enabled ? 0.09 : 0.05
            )))
            .overlay(shape.strokeBorder(.white.opacity(0.09), lineWidth: 0.8))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.1), value: hovering)
    }
}

struct DangerButton: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.42))
            .padding(.horizontal, 13)
            .frame(height: Metrics.control)
            .background(shape.fill(.red.opacity(configuration.isPressed ? 0.24 : hovering ? 0.18 : 0.12)))
            .overlay(shape.strokeBorder(.red.opacity(0.28), lineWidth: 0.8))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.1), value: hovering)
    }
}

/// The one text-field shape used everywhere, so login, search and settings do
/// not each invent their own.
struct Field<C: View>: View {
    let icon: String
    @ViewBuilder let content: C

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(width: 15)
            content
                .textFieldStyle(.plain)
                .font(.callout)
        }
        .padding(.horizontal, 12)
        .frame(height: Metrics.field)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.8)
        )
    }
}


/// A text-only action, in the brand colour.
///
/// `.buttonStyle(LinkButton())` would be the one-liner and it paints with the *system*
/// accent — blue on a default Mac — which is the one colour this product does
/// not use. Small enough that a full button would shout, so it stays text.
struct LinkButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? AnyShapeStyle(Color.brand) : AnyShapeStyle(.tertiary))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .underline(hovering && enabled)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.1), value: hovering)
    }
}

/// 长得和 QuietButton 一模一样的菜单。
///
/// Menu 不吃 ButtonStyle:套上 `.buttonStyle(QuietButton())` 不会把描边和底色
/// 画出来,只会改标签字体。所以这里把 QuietButton 那几个数照抄一遍——它们必须
/// 一致,否则和「导出全部」「全选本页」并排放着,一眼就看得出是两种东西。
///
/// `.tint` 那一行不是装饰:borderless 菜单会用**强调色**画自己的标签,而这个
/// App 把强调色设成了品牌绿——不压住的话,这一颗会绿着,旁边两颗是白的。
struct QuietMenu<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return Menu {
            content
        } label: {
            Label(title, systemImage: icon)
                .font(.callout)
                .padding(.horizontal, 13)
                .frame(height: Metrics.control)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // 外层再钉一次高度。
        //
        // 只钉标签不够:Menu 会按自己的算法定尺寸,标签上的 frame 只影响标签,
        // 结果这一颗比旁边两颗矮一截——而代码里写的是同一个 Metrics.control,
        // 光看代码看不出来。背景和描边挂在这一层之后,才和 QuietButton 一样高。
        .frame(height: Metrics.control)
        .tint(Color.primaryLabel)
        .background(shape.fill(.white.opacity(hovering ? 0.09 : 0.05)))
        .overlay(shape.strokeBorder(.white.opacity(0.09), lineWidth: 0.8))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
    }
}
