import SwiftUI
import AppKit
import OpenimgKit

struct GalleryView: View {
    @ObservedObject var model: AppModel
    private static let spacing: Double = 12

    var body: some View {
        VStack(spacing: 0) {
            if model.images.isEmpty {
                EmptyState(model: model)
            } else {
                grid
            }
            statusBar
        }
        // A full-window overlay rather than an inspector column: the point of
        // opening a picture is to see it bigger, and a 320pt column cannot.
        .overlay {
            if let img = model.detail {
                Lightbox(model: model, img: img)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.detail?.id)
    }

    /// A page sized to the window rather than the other way round.
    ///
    /// `GeometryReader` sits outside the `ScrollView` on purpose — a scroll view
    /// proposes unbounded height to its content, so measuring from inside would
    /// report infinity and the solver would hand back one enormous row.
    ///
    /// The `ScrollView` stays even when everything fits: nothing scrolls when
    /// the content is exactly as tall as the port, and it is what catches the
    /// small-window case where the solver gives up and falls back to `minCell`.
    private var grid: some View {
        GeometryReader { geo in
            let fit = GridFit.solve(count: model.images.count, in: geo.size,
                                    spacing: Self.spacing, minCell: 72)
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(fit.cellWidth),
                                                       spacing: Self.spacing),
                                   count: fit.columns),
                    spacing: Self.spacing
                ) {
                    ForEach(model.images) {
                        Card(model: model, img: $0,
                             width: fit.cellWidth, height: fit.cellHeight)
                    }
                }
                .frame(maxWidth: .infinity)
                // 竖向余量对半分。正方形格子装不满高度是几何事实,余量堆在底
                // 下读作"少了一行",对半分到上下读作页边距。滚动时 minHeight
                // 不起作用,内容本来就更高。
                .frame(minHeight: geo.size.height)
            }
            .scrollDisabled(!fit.scrolls)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    /// 整库导出到本地目录。放在常驻的状态栏而不是 filters 行——搜索无结果
    /// 时 filters 整行消失,进行中的进度和「取消」不能跟着蒸发。
    @ViewBuilder private var exportControl: some View {
        if let e = model.export, !e.finished {
            HStack(spacing: 6) {
                ProgressView(value: e.total > 0
                             ? min(Double(e.processed), Double(e.total)) / Double(e.total) : 0)
                    .frame(width: 90)
                Text("\(min(e.processed, e.total))/\(e.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button(L.s.common.cancel) { model.exportCancel() }
                    .buttonStyle(QuietButton())
            }
        } else {
            Button {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.prompt = L.s.gallery.exportPanelPrompt
                if panel.runModal() == .OK, let url = panel.url {
                    model.exportDismiss()
                    Task { await model.exportAll(to: url) }
                }
            } label: {
                Label(L.s.gallery.exportAll, systemImage: "square.and.arrow.down")
            }
            .buttonStyle(QuietButton())
            .help(L.s.gallery.exportHelp)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text(L.s.common.imageCount(model.total))
            if let q = model.quota {
                Text("·").foregroundStyle(.quaternary)
                Text(L.s.gallery.usedSpace(model.bytes(q.usedBytes)))
            }
            Spacer()
            // 选中操作紧挨「全选本页」左边:点了全选,下一步(删除/取消)就出
            // 现在手边,不用抬头去页面顶上找。
            if !model.selection.isEmpty {
                Text(L.s.gallery.selectedCount(model.selection.count))
                    .font(.callout).foregroundStyle(.white)
                Button(L.s.common.delete) { Task { await model.deleteSelected() } }
                    .buttonStyle(DangerButton())
                Button(L.s.common.cancel) { model.selection = [] }
                    .buttonStyle(QuietButton())
            }
            // 三颗同款(icon + 名字),因为它们是同一类事:对当前这一页做点什么。
            // 原来「全选本页」在上面那排、「每页张数」在顶栏,三件同类的事分散
            // 在三个地方,每次要找。
            Button {
                model.toggleAll()
            } label: {
                let all = model.selection.count == model.images.count
                Label(all ? L.s.gallery.deselectAll : L.s.gallery.selectAll,
                      systemImage: all ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .buttonStyle(QuietButton())
            .disabled(model.images.isEmpty)

            QuietMenu(title: L.s.nav.perPageCount(model.pageSize),
                      icon: "square.grid.2x2") {
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

            exportControl
            if model.pageCount > 1 {
                ToolCluster {
                    ToolTile(icon: "chevron.left", help: L.s.gallery.prevPage,
                             disabled: model.page == 0 || model.busy) {
                        Task { await model.go(to: model.page - 1) }
                    }
                    Text("\(model.page + 1) / \(model.pageCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 46)
                    ToolTile(icon: "chevron.right", help: L.s.gallery.nextPage,
                             disabled: model.page >= model.pageCount - 1 || model.busy) {
                        Task { await model.go(to: model.page + 1) }
                    }
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .animation(.easeInOut(duration: 0.16), value: model.selection.isEmpty)
    }
}

// MARK: - Card

/// A contact-sheet tile: the picture is the whole cell.
///
/// The old card carried a permanent caption strip under the thumbnail. At the
/// tile sizes a full page needs, that strip costs about a third of the cell to
/// print a filename too narrow to read — so the name moved onto the picture,
/// where it only appears under the pointer, and onto the tooltip, which stays
/// legible no matter how small the tile gets.
private struct Card: View {
    @ObservedObject var model: AppModel
    let img: RemoteImage
    let width: Double
    let height: Double
    @State private var hovering = false

    private var selected: Bool { model.selection.contains(img.id) }
    private var active: Bool { model.detail?.id == img.id }
    /// Below this the caption is a few truncated characters and a format chip
    /// wider than the word it holds. The tooltip carries the name instead.
    private var showsCaption: Bool { width >= 118 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Thumbnail(url: img.thumbURL, client: try? model.client())

            if hovering && showsCaption {
                caption
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)
            }

            if hovering || selected || !model.selection.isEmpty {
                Button { model.toggle(img.id) } label: {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(selected ? Color.brandInk : .white,
                                         selected ? Color.brand : .black.opacity(0.45))
                        .shadow(color: .black.opacity(0.35), radius: 2)
                }
                .buttonStyle(.plain)
                .padding(6)
                .transition(.opacity)
            }
        }
        .frame(width: width, height: height)
        .panelSurface(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected || active ? Color.brand : .clear, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: selected)
        .hoverLift()
        .onHover { hovering = $0 }
        .help("\(img.origName) · \(img.ext.uppercased())")
        .contentShape(Rectangle())
        .onTapGesture { model.detail = active ? nil : img }
        .contextMenu {
            ForEach(LinkFormat.allCases, id: \.self) { f in
                let name = L.s.gallery.linkLabel(f)
                Button(L.s.gallery.copyFormat(name)) {
                    model.copy(f.render(img)); model.announce(L.s.gallery.copiedFormat(name))
                }
            }
            Divider()
            Button(L.s.gallery.editImage) {
                Task { await model.editFromGallery(img) }
            }
            Button(L.s.gallery.openInBrowser) {
                if let u = URL(string: img.shortURL ?? img.url) { NSWorkspace.shared.open(u) }
            }
            Divider()
            Button(L.s.common.delete, role: .destructive) { Task { await model.delete(img) } }
        }
    }

    /// A flat bar rather than a scrim. A gradient over a photograph reads as
    /// part of the photograph.
    private var caption: some View {
        HStack(spacing: 5) {
            Text(img.origName)
                .font(.caption2).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            Text(img.ext.uppercased())
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.62))
    }
}

// MARK: - Empty state

private struct EmptyState: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            if model.busy {
                ProgressView()
            } else if !model.search.isEmpty {
                icon("magnifyingglass")
                Text(L.s.gallery.noMatches(model.search)).font(.title3.weight(.medium))
                Button(L.s.gallery.clearSearch) {
                    model.search = ""
                    Task { await model.load(resetPage: true) }
                }
                .buttonStyle(QuietButton())
            } else {
                icon("photo.on.rectangle.angled")
                Text(L.s.gallery.emptyTitle).font(.title3.weight(.medium))
                Text(L.s.gallery.emptyHint)
                    .font(.callout).foregroundStyle(.secondary)
                Button(L.s.gallery.uploadFirst) { model.section = .upload }
                    .buttonStyle(BrandButton())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 40, weight: .light))
            .foregroundStyle(Color.brand.opacity(0.65))
            .frame(width: 84, height: 84)
            .background(Circle().fill(Color.brand.opacity(0.10)))
    }
}
