import SwiftUI
import AppKit
import OpenimgKit

/// 只为了拿到 applicationDidFinishLaunching 这一个时机。
///
/// 图标要在启动时就摆正:UserDefaults 里存着紫,但 bundle 里的图标是绿的,
/// 不主动设一次就得等用户去设置里切一下才对得上。
///
/// 不能放在 `App.init()` 里——那时 NSApp 还没建出来,而它是隐式解包可选,
/// 一访问就 trap(EXC_BREAKPOINT,栈停在 applyAppIcon)。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        BrandTint.current.applyAppIcon()
    }
}

@main
struct OpenimgMacApp: App {
    @StateObject private var model = AppModel.shared

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() { BrandFont.register() }

    var body: some Scene {
        Window("OpenImg", id: "main") {
            RootView(model: model)
                .tint(.brand)
                // Dark regardless of the system setting. See Theme.swift: the
                // translucency this design is built on only reads as glass over
                // a dark base, and following the appearance would mean carrying
                // two sets of every surface value.
                .preferredColorScheme(.dark)
        }
        // Sized so a default page of 50 lands on tiles around 95pt rather than
        // 73pt. The gallery fills whatever it is given, so the default window
        // is what decides how big a thumbnail the app opens on.
        .defaultSize(width: 1240, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L.s.nav.uploadImages) {
                    model.section = .upload
                    Task { await model.pickAndUpload() }
                }
                .keyboardShortcut("u")
                .disabled(!model.connected)
            }
            CommandGroup(after: .toolbar) {
                // 走和按钮同一条路,⌘R 也要让图标转起来——两条入口做同一件
                // 事却只有一条给反馈,用键盘的人会以为快捷键没生效。
                Button(L.s.common.refresh) { model.refreshTapped() }
                    .keyboardShortcut("r")
                    .disabled(!model.connected)
            }
        }
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            // restoring 也走主界面:钥匙串里有令牌,几乎可以肯定这次能连上,
            // 各页自己的占位符会顶住验证的那几百毫秒。令牌真失效时 restoring
            // 落回 false、connected 仍是 false,这里自然换到登录页——那才是
            // 该看到登录页的时刻。
            if model.connected || model.restoring {
                HStack(spacing: 0) {
                    // 入场顺序 = 视觉层级:侧栏 → 顶栏 → 卡片(从上到下)。
                    // 顺序本身就是在替眼睛排落点。
                    Sidebar(model: model).frame(width: 224).entrance(0)
                    content
                }
            } else {
                LoginView(model: model)
            }
            toast
        }
        .frame(minWidth: 900, minHeight: 560)
        .windowSurface()
        // 文案取自 L.s 这个静态量而非各视图观察的属性,单靠 objectWillChange
        // 只会刷新恰好在读 model 的视图。换语言时把 epoch 挂上 .id 让整树
        // 重建——代价是回到默认页,但换语言本就是一次性动作。
        .id("\(model.langEpoch)-\(model.brandEpoch)")
        .task {
            await model.restore()
            // 查更新与登录无关:没登录的人也该知道有新版。放在 restore 之后而
            // 不是并行,是因为它完全不急——一天一次的东西,晚几百毫秒无所谓,
            // 而并行会和首屏的几个请求抢带宽。
            await model.updates.checkIfDue()
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            TopBar(model: model).entrance(1)
            Group {
                switch model.section {
                case .overview: OverviewView(model: model)
                case .gallery:  GalleryView(model: model)
                case .upload:   UploadView(model: model)
                case .generate: GenerateView(model: model)
                case .retouch:  RetouchView(model: model)
                case .editor:   EditorPage(model: model)
                case .settings: SettingsView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentSurface()
        // Its own rounded plane, so the two columns separate by surface rather
        // than by a hairline.
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 0.8)
        )
        .padding(.vertical, 8)
        .padding(.trailing, 8)
    }

    @ViewBuilder
    private var toast: some View {
        if !model.status.isEmpty {
            Text(model.status)
                .font(.callout)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .chromeSurface(Capsule())
                .shadow(color: .black.opacity(0.4), radius: 14, y: 5)
                .padding(.bottom, 26)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { model.status = "" }
        }
    }
}

// MARK: - Top bar

/// Hand-built rather than a `.toolbar`.
///
/// The reference groups controls into floating clusters with gaps between them;
/// a system toolbar lays its items on one continuous strip, so the pieces exist
/// but the shape does not. Building it here also lets the bar change with the
/// section instead of every control living on every page.
struct TopBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Text(L.s.nav.section(model.section))
                .font(.title3.weight(.semibold))

            Spacer(minLength: 12)

            // 图库那一组撤了。
            //
            // 排序在下面那排 tabs 里已经有了,同一件事摆两个入口,读者会以为它
            // 们不一样;每页张数挪到了底部,和「全选本页」「导出全部」放在一起
            // ——三件事都是"对这一页做点什么",本来就该在同一个地方,原来却分散
            // 在顶栏、筛选行、底栏三处,每次都要找。
            //
            // 刷新留在这儿:它每一页都在,跟着页面内容跑会让它在切页时移位。

            ToolCluster {
                ToolTile(icon: "arrow.clockwise", help: L.s.common.refresh,
                         spinning: model.refreshing) {
                    model.refreshTapped()
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

// MARK: - Sidebar

/// Hand-drawn instead of `List(.sidebar)`.
///
/// The system list brings its own selection shape, insets and hover behaviour,
/// none of which match the reference's rounded highlight — and overriding them
/// costs more than drawing four rows.
struct Sidebar: View {
    @ObservedObject var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 字标居中且放大:侧栏顶部那块留白本来就是留给它的,17pt 靠左
            // 时那块地方看着是空的而不是宽松的。
            HStack(spacing: 0) {
                Text("Open").font(.brand(26, .bold))
                Text("Img").font(.brand(26, .bold)).foregroundStyle(Color.brand)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 12)
            .padding(.bottom, 18)

            search
                .padding(.horizontal, 10)
                .padding(.bottom, 10)

            // visibleSections 而不是 allCases:没配 AI 的部署里「生成」和
            // 「修图」整行不存在,而不是灰着。见 AppModel.visibleSections。
            NavRail(count: model.visibleSections.count,
                    index: model.visibleSections.firstIndex(of: model.section)) {
                // spacing 0:发光条是一段连续竖线上的一格,行间留缝就对不上了。
                VStack(spacing: 0) {
                    ForEach(model.visibleSections) { s in
                        SidebarRow(
                            section: s,
                            active: model.section == s,
                            // 转圈按种类分:两页共用一张历史表,不分开的话在修图
                            // 时「生成」那行也会跟着转,像是自己动了起来。
                            busy: (s == .upload && model.uploading)
                                || (s == .generate && model.aiPendingText)
                                || (s == .retouch && model.aiPendingEdit),
                            // 有新版时在「设置」那行点一个小圆点。
                            //
                            // 不弹窗、不横幅:更新是件不急的事,而打断正在做的事
                            // 去说一件不急的事,换来的是用户学会无视这类提示。
                            // 一个圆点足够被看见,又不要求当场处理。
                            dot: s == .settings && model.updates.hasUpdate
                        ) { model.section = s }
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()
            account
        }
        .padding(.top, 42) // clears the traffic lights
        // 搜索框默认**不**带光标,点了才聚焦。
        //
        // 它是窗口里第一个文本框,AppKit 在窗口成为 key 时自动把第一响应者给
        // 它——于是每次打开 app,侧栏搜索框都亮着一根闪烁的光标,像是在催人
        // 打字。defaultFocus 声明它不参与默认焦点;下面那句是兜底:初始第一
        // 响应者的指派发生在 SwiftUI 焦点系统接管之前,单靠声明有时拦不住,
        // 启动后把响应者退掉一次才保险。只在出现时做一次,不影响之后的点击。
        .defaultFocus($searchFocused, false)
        .onAppear {
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    /// Search lives here rather than in the toolbar.
    ///
    /// In the toolbar it only existed on the gallery page, so looking for a
    /// picture from anywhere else meant first navigating to the place that has
    /// the search box. As a permanent sidebar row it is an entry point: typing
    /// into it goes to the gallery, because searching is what the gallery is
    /// for.
    private var search: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(searchFocused ? .secondary : .tertiary)
            TextField(L.s.nav.searchPlaceholder, text: $model.search)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onChange(of: model.search) {
                    if !model.search.isEmpty { model.section = .gallery }
                    model.searchChanged()
                }
                .onSubmit { model.section = .gallery }
            if !model.search.isEmpty {
                Button {
                    model.search = ""
                    Task { await model.load(resetPage: true) }
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(searchFocused ? 0.09 : 0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(searchFocused ? 0.16 : 0.07), lineWidth: 0.8)
        }
        .animation(.easeOut(duration: 0.12), value: searchFocused)
        .onTapGesture { searchFocused = true }
    }

    @ViewBuilder
    private var account: some View {
        if let a = model.account {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    Avatar(account: a, size: 30, client: try? model.client())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a.name.isEmpty ? a.email : a.name)
                            .font(.callout).lineLimit(1)
                        if let q = model.quota {
                            Text(L.s.nav.availableSpace(model.bytes(q.availableBytes)))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    Button {
                        model.signOut()
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L.s.nav.signOutHelp)
                }
                if let q = model.quota, q.quotaBytes > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.10))
                            Capsule().fill(Color.brand)
                                .frame(width: max(3, geo.size.width *
                                    min(1, Double(q.usedBytes) / Double(q.quotaBytes))))
                        }
                    }
                    .frame(height: 4)
                }
            }
            .padding(12)
            .panelSurface(12)
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
    }
}

private struct SidebarRow: View {
    let section: Section_
    let active: Bool
    /// Upload keeps working while the user browses elsewhere, so the row is
    /// where that shows — a spinner buried on the upload page tells nobody
    /// anything once they have navigated away.
    var busy = false
    /// 右端的小圆点。有事发生但不急时点亮。
    var dot = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: active ? section.iconFilled : section.icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22)
                    // Outline morphs into solid on selection.
                    .contentTransition(.symbolEffect(.replace.downUp))
                    // A small bounce when it becomes the active one. Tied to
                    // `active` rather than fired on tap so re-tapping the
                    // current row does not jiggle for no reason.
                    .symbolEffect(.bounce.up.byLayer, value: active)
                    // And a slow pulse while an upload is running.
                    .symbolEffect(.pulse, isActive: busy)
                Text(L.s.nav.section(section))
                    .font(.system(size: 15))
                    // 只放大文字,不放大整行。整行一起缩放的话图标也跟着变大,
                    // 那一列的对齐就散了——而图标列是这一栏唯一的竖直基准。
                    // scaleEffect 不参与布局,所以右端那颗小圆点不会被推走。
                    //
                    // **不排除激活行。** 排除的话点下去那一刻条件立刻为假,而
                    // 指针还停在上面——文字当场缩回去,每次点击都要看一次收缩。
                    // 放大是"指针在这儿"的反馈,和"这是不是当前页"无关。
                    .scaleEffect(hovering ? 1.1 : 1, anchor: .leading)
                Spacer(minLength: 0)
                if dot {
                    Circle()
                        .fill(Color.brand)
                        .frame(width: 6, height: 6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            // 选中不再是一块实心圆角底,而是文字本身变成品牌色——发光条已经
            // 在左边指明了是哪一行,再压一块实底就是同一件事说两遍,而且那块
            // 底会把发光条的光吃掉一半。
            .foregroundStyle(active ? AnyShapeStyle(Color.brand)
                                    : AnyShapeStyle(hovering ? .primary : .secondary))
            .padding(.horizontal, 12)
            .frame(height: Metrics.navRow)
            // 悬浮不画任何底:这一栏里唯一的边是最左那根轨道,给行加底就是又
            // 引入一种形状。变白加文字放大已经够说明"指着的是这一行"。
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: active)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
