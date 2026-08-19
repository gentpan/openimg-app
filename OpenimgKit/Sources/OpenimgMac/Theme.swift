import SwiftUI
import AppKit

/// One scale, and one rule about what goes on it.
///
/// #90FF3A has a relative luminance of 0.778, so white on it is 1.27:1 —
/// unreadable, not merely low. Every filled control therefore takes
/// `Color.brandInk` (14.14:1), and white never appears on a brand surface.
/// That single fact is the whole difference from the violet this replaces,
/// which was 0.135 and carried white at 4.67:1.
/// One height for every control that can sit next to another one.
///
/// Padding maths gave the toolbar three different heights — a pill row at 32,
/// a quiet button at 28, a brand button at 30 — which is invisible in isolation
/// and obvious the moment two of them share a row. A fixed height is also
/// stable across fonts, where padding is not.
enum Metrics {
    /// 独立控件的高度:按钮、Pill、工具格子。
    static let control: CGFloat = 32
    /// 输入行(Field)的高度。
    ///
    /// 比 control 高一档是有意的:输入框要装下光标和一行 callout,挤到 32 会
    /// 显得局促。但**并排放在 Field 旁边的按钮要用这个数,不是 control**
    /// ——同一行里两个高度差六个点,肉眼一看就是没对齐。
    static let field: CGFloat = 38
    /// 侧栏一行的高度。
    ///
    /// 必须是定值:那根发光条靠 index × 行高 定位,行高一变位置就错。原来行
    /// 是内容撑起来的、行间还有 4pt 间距,两者都得去掉——发光条是一段连续
    /// 竖线上的一格,中间断开就不成立了。
    static let navRow: CGFloat = 40
}

/// 品牌色相。与网站的 `data-brand` 同一套取值,两端切换后观感一致。
///
/// 产品固定深色,可切的只有色相——浅色主题在网站上就删掉了(品牌绿在白底
/// 对比度 1.27:1 不可用)。
enum BrandTint: String, CaseIterable, Sendable {
    case green, violet

    /// 静息填充色 = 网站的 `--color-brand-600`。
    var accent: Color {
        switch self {
        case .green: Color(red: 0x90 / 255, green: 0xFF / 255, blue: 0x3A / 255)
        case .violet: Color(red: 0x76 / 255, green: 0x24 / 255, blue: 0xF4 / 255)
        }
    }

    /// 填充之上的前景 = `--color-brand-ink`。绿的相对亮度 0.778,白字在它
    /// 上面只有 1.27:1(不是偏低,是读不了),所以配近黑;紫的 0.116,白字
    /// 6.31:1,配白。整套控件只认这一个变量,换色不用改任何组件。
    var ink: Color {
        switch self {
        case .green: Color(red: 0x0A / 255, green: 0x1B / 255, blue: 0x02 / 255)
        case .violet: .white
        }
    }

    /// 大字与图表用的浅色阶 = `--color-brand-display`。
    var display: Color {
        switch self {
        case .green: Color(red: 0xC8 / 255, green: 0xFF / 255, blue: 0x9C / 255)
        case .violet: Color(red: 0xB4 / 255, green: 0x82 / 255, blue: 0xFF / 255)
        }
    }

    /// 侧栏发光条的强度。
    ///
    /// 绿的相对亮度 0.778,紫的 0.116,差了六倍多。同一组数值紫色是恰到好处
    /// 的一抹光晕,绿色就是一条刺眼的灯管——所以两边分开给,不共用。
    var navGlow: Double {
        switch self {
        case .green: 0.42
        case .violet: 0.85
        }
    }

    /// 这个色相对应的 Dock 图标资源名,nil 表示用 bundle 里的默认图标。
    ///
    /// 只换 Dock 和 ⌘Tab 里那张图。Finder、启动台、以及应用没在运行时
    /// Dock 上的那张,都还是 bundle 里的绿版——`.app` 是签过名的,运行时
    /// 改自己的 Resources 会让签名失效,系统直接拒绝启动。想让那些地方也
    /// 变色只能出两个独立的 .app,那是另一件事。
    var iconResource: String? {
        switch self {
        case .green: nil          // = bundle 的 AppIcon,不用替
        case .violet: "AppIcon-Violet"
        }
    }

    /// 当前色相。做成静态量而不是 Environment:`Color.brand` 在 55 处被
    /// 直接引用(含 ButtonStyle 这类拿不到 Environment 的地方),改成环境值
    /// 要动全部调用点。AppModel 改它时会同时发布变更,观察 model 的视图
    /// 重绘时自然读到新值。
    nonisolated(unsafe) static var current: BrandTint = {
        BrandTint(rawValue: UserDefaults.standard.string(forKey: "brandTint") ?? "") ?? .green
    }()
}

extension BrandTint {
    /// 把 Dock 图标换成当前色相那张。
    ///
    /// 启动时也要调一次:UserDefaults 里存着紫,但 bundle 的图标是绿的,
    /// 不主动设一次的话要等用户去设置里切一下才对得上。
    @MainActor func applyAppIcon() {
        guard let name = iconResource else {
            // nil 而不是重新加载 AppIcon.icns:nil 是"恢复 bundle 默认",
            // 由系统去取,不会因为找不到资源变成空白图标。
            NSApplication.shared.applicationIconImage = nil
            return
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "icns"),
              let image = NSImage(contentsOf: url) else {
            NSApplication.shared.applicationIconImage = nil
            return
        }
        NSApplication.shared.applicationIconImage = image
    }
}

extension Color {
    /// Same value as the site's `--color-brand-600`.
    static var brand: Color { BrandTint.current.accent }
    static var brandDisplay: Color { BrandTint.current.display }

    /// What goes *on* a brand fill. Near-black with a trace of the brand hue,
    /// so it reads as part of the control rather than as borrowed body text.
    /// The grey the toolbar's plain tiles resolve to, as a concrete Color so it
    /// can be handed to `.tint`, which does not take a hierarchical style.
    static let secondaryLabel = Color(nsColor: .secondaryLabelColor)

    static var brandInk: Color { BrandTint.current.ink }
    /// 侧栏发光条的强度,随色相走。
    static var brandGlow: Double { BrandTint.current.navGlow }

    /// "It worked" — kept at a distinctly different hue (teal, 173°) from the
    /// brand (101°) so a success message never reads as brand chrome.
    static let success = Color(red: 0x14 / 255, green: 0xB8 / 255, blue: 0xA6 / 255)
}

// MARK: - Surfaces
//
// The app is dark regardless of the system setting, and that is the whole
// premise rather than a preference. Translucent chrome only reads as glass over
// something darker than itself; on a light desktop the same materials stack up
// into a white wall, which is exactly what the first attempt produced. Every
// value below assumes a dark base, so following the system appearance would
// mean maintaining two sets of them.

extension View {
    /// The window's own backdrop. Dark enough that the layers above it have
    /// something to separate from, translucent enough to pick up the desktop.
    func windowSurface() -> some View {
        background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color.black.opacity(0.38))
            }
            .ignoresSafeArea()
        }
    }

    /// Floating chrome: toolbar clusters, pill rows, the toast.
    ///
    /// A visible top edge and a darker fill, because on a dark base a shadow
    /// alone does not separate anything — the lift has to come from the rim
    /// catching light, which is what the reference does.
    func chromeSurface<S: InsettableShape>(_ shape: S, elevated: Bool = true) -> some View {
        let tint: Color = .black.opacity(elevated ? 0.28 : 0.16)
        return self
            .background(shape.fill(tint))
            .background(shape.fill(.ultraThinMaterial))
            .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8))
    }

    /// Panels that hold content: dashboard cards, drop zones, the login card.
    /// Quieter than chrome — a container should not compete with the controls
    /// floating over it.
    func panelSurface(_ radius: CGFloat = 14) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(shape.fill(Color.white.opacity(0.045)))
            .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8))
    }

    /// The reading area to the right of the sidebar, one step lighter so the
    /// two columns read as distinct planes without a divider between them.
    func contentSurface() -> some View {
        background(Color.white.opacity(0.03))
    }
}

// MARK: - Pills

/// The capsule filter row from the reference: the active segment carries a
/// solid fill, the rest stay transparent until hovered.
struct PillRow<T: Hashable & Identifiable>: View {
    let items: [T]
    let label: (T) -> String
    var icon: ((T) -> String)? = nil
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items) { item in
                Pill(
                    text: label(item),
                    icon: icon?(item),
                    active: item == selection
                ) { selection = item }
            }
        }
        .padding(3)
        .chromeSurface(Capsule(), elevated: false)
    }
}

struct Pill: View {
    let text: String
    var icon: String? = nil
    let active: Bool
    /// 独立使用时描个边。
    ///
    /// PillRow 里的那些不需要:外圈容器本身就把它们框成了一组分段控件。而
    /// 单独摆一排的(修图预设)没有那层容器,未选中时背景全透明,看起来就是
    /// 一行普通文字——用户不知道那是可以点的。
    var bordered = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 10.5)) }
                Text(text)
            }
            .font(.callout.weight(active ? .medium : .regular))
            .foregroundStyle(active ? AnyShapeStyle(Color.brandInk) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 12)
            .frame(height: Metrics.control - 6)   // 减去 PillRow 外圈的 3pt 内边距
            .background {
                Capsule().fill(
                    active ? AnyShapeStyle(Color.brand)
                           : AnyShapeStyle(Color.white.opacity(hovering ? 0.08 : 0))
                )
            }
            .overlay {
                if bordered, !active {
                    Capsule().strokeBorder(.white.opacity(hovering ? 0.28 : 0.16), lineWidth: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: active)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// A toolbar button shaped like the reference's: a square-ish glass tile that
/// groups with its neighbours rather than a bare system button.
struct ToolTile: View {
    let icon: String
    var help: String = ""
    var disabled = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(disabled ? .tertiary : .secondary)
                .frame(width: 30, height: Metrics.control - 6)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.white.opacity(hovering && !disabled ? 0.10 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
    }
}

/// Wraps a run of tiles into one floating cluster.
struct ToolCluster<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        HStack(spacing: 1) { content }
            .padding(3)
            .chromeSurface(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Hover

/// A card that lifts slightly under the pointer. Without it a grid of pictures
/// reads as decoration rather than as something clickable.
struct HoverLift: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.02 : 1)
            .shadow(color: .black.opacity(hovering ? 0.35 : 0), radius: hovering ? 10 : 0, y: 4)
            .animation(.easeOut(duration: 0.14), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverLift() -> some View { modifier(HoverLift()) }
}

// MARK: - Brand typeface

/// Ubuntu, bundled with the app. The site sets its wordmark in Ubuntu, and a
/// client that renders the same name in the system face reads as a different
/// product. Latin only, so it goes on the wordmark rather than whole strings.
enum BrandFont {
    static func register() {
        for name in ["Ubuntu-Regular", "Ubuntu-Medium", "Ubuntu-Bold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    static func brand(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let face = switch weight {
        case .bold, .heavy, .black: "Ubuntu-Bold"
        case .medium, .semibold: "Ubuntu-Medium"
        // 常规档的 PostScript 名是 Ubuntu-Regular,不是 Ubuntu(实测三个 ttf 的
        // name 表确认过)。写错的后果不是崩溃而是**静默回落系统字体**——下面
        // 那道 NSFont(name:) 守卫会接住它——所以打进包里的 Ubuntu-Regular.ttf
        // 一直没有任何路径能用到。今天两个调用点都用 .bold,所以看不出来。
        default: "Ubuntu-Regular"
        }
        return NSFont(name: face, size: size) != nil
            ? .custom(face, size: size)
            : .system(size: size, weight: weight, design: .rounded)
    }
}
