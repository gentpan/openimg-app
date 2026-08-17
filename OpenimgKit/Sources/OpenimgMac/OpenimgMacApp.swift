import SwiftUI
import AppKit
import OpenimgKit

@main
struct OpenimgMacApp: App {
    @StateObject private var model = AppModel.shared

    init() { BrandFont.register() }

    var body: some Scene {
        Window("Openimg", id: "main") {
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
                Button(L.s.common.refresh) { Task { await model.refreshCurrent() } }
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
            if model.connected {
                HStack(spacing: 0) {
                    Sidebar(model: model).frame(width: 224)
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
        .id(model.langEpoch)
        .task { await model.restore() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            TopBar(model: model)
            Group {
                switch model.section {
                case .overview: OverviewView(model: model)
                case .gallery:  GalleryView(model: model)
                case .upload:   UploadView(model: model)
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

            if model.section == .gallery {
                ToolCluster {
                    menuTile("arrow.up.arrow.down", L.s.nav.sort) {
                        ForEach(SortKey.allCases) { s in
                            Button {
                                model.sort = s
                                Task { await model.load(resetPage: true) }
                            } label: {
                                Label(L.s.gallery.sortLabel(s),
                                      systemImage: model.sort == s ? "checkmark" : s.icon)
                            }
                        }
                    }
                    menuTile("square.grid.2x2", L.s.nav.perPage) {
                        ForEach(model.pageSizes, id: \.self) { n in
                            Button {
                                model.pageSize = n
                                Task { await model.load(resetPage: true) }
                            } label: {
                                Label(L.s.nav.perPageCount(n),
                                      systemImage: model.pageSize == n ? "checkmark" : "square.grid.2x2")
                            }
                        }
                    }
                }
            }

            ToolCluster {
                ToolTile(icon: "arrow.clockwise", help: L.s.common.refresh, disabled: model.busy) {
                    Task { await model.refreshCurrent() }
                }
                ToolTile(icon: "arrow.up.circle", help: L.s.nav.uploadHelp) {
                    model.section = .upload
                    Task { await model.pickAndUpload() }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    /// A tile that opens a menu, keeping the tile's own look instead of the
    /// system menu button's chrome.
    private func menuTile<C: View>(_ icon: String, _ help: String,
                                   @ViewBuilder items: () -> C) -> some View {
        Menu {
            items()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // A borderless menu paints its label with the *accent* colour, which
        // this app sets to the brand green — so these two came out green while
        // the plain tiles beside them stayed grey. Tinting the menu itself is
        // what actually overrides it; a .foregroundStyle on the label does not.
        .tint(Color.secondaryLabel)
        .help(help)
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
            HStack(spacing: 0) {
                Text("Open").font(.brand(17, .bold))
                Text("img").font(.brand(17, .bold)).foregroundStyle(Color.brand)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)

            search
                .padding(.horizontal, 10)
                .padding(.bottom, 10)

            VStack(spacing: 4) {
                ForEach(Section_.allCases) { s in
                    SidebarRow(
                        section: s,
                        active: model.section == s,
                        busy: s == .upload && model.uploading
                    ) { model.section = s }
                }
            }
            .padding(.horizontal, 10)

            Spacer()
            account
        }
        .padding(.top, 42) // clears the traffic lights
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
                Text(L.s.nav.section(section)).font(.system(size: 15))
                Spacer(minLength: 0)
            }
            .foregroundStyle(active ? AnyShapeStyle(Color.brandInk) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(active ? AnyShapeStyle(Color.brand.opacity(0.85))
                                 : AnyShapeStyle(Color.white.opacity(hovering ? 0.07 : 0)))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: active)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
