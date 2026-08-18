import SwiftUI
import OpenimgKit

/// 输入区顶上那一行「给 AI 几张图」。
///
/// 修图页管它叫「原图」、生成页管它叫「参考图」,可要用户做的事一模一样:
/// 挑几张图库里的图,或者现传几张。所以两页共用这一个视图——各写一份的话,
/// 「上传」这个入口迟早只有一边有。
///
/// 三条进图的路并排摆着,因为它们各自解决一种处境:图早就传过了(从图库
/// 选)、图还在硬盘上(上传 / 拖进来)、图是刚刚才传的(最近上传)。
struct AISourceRow: View {
    @ObservedObject var model: AppModel
    let slot: AISourceSlot
    /// 那一行的称呼。两页不同,也只有这一处不同。
    let label: String
    /// 一张都没选时是否收成一行。
    ///
    /// 生成页给 true:参考图在那边是可选项,空着时摆一个 64pt 高的虚线框会
    /// 把提示词框挤下去,让一件可以不做的事看起来像必填。修图页给 false——
    /// 那边没有原图就没有下一步,那个框就是整页的起点。
    var compactWhenEmpty = false
    /// 空着时的一句话。生成页用它说清「可以不给」。
    var emptyHint: String?

    @State private var dropping = false

    private var sources: [RemoteImage] { model.aiSources(slot) }
    private var canAdd: Bool { model.aiCanAddSource(slot) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 46, alignment: .leading)
                .padding(.top, collapsed ? 4 : 22)

            if collapsed { collapsedControls } else { tiles }

            Spacer(minLength: 0)

            Text(L.s.aiSource.sourceCount(sources.count, aiEditSourceLimit))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .padding(.top, collapsed ? 4 : 22)
        }
        .contentShape(Rectangle())
        // 整行都是拖放目标,不只是那个虚线框:选满四张之后框就没了,而那时
        // 拖进来仍然该有个说法(下面 aiUploadSources 会说「先取消一张」)。
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            Task { await model.aiUploadSources(await DroppedFiles.urls(from: providers), into: slot) }
            return true
        }
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.brand, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .padding(-4)
            }
        }
        .animation(.easeOut(duration: 0.15), value: dropping)
    }

    private var collapsed: Bool { compactWhenEmpty && sources.isEmpty }

    // MARK: - 空着时的一行

    /// 两个文字按钮加一句话,高度与一行正文相当,不占地方。
    private var collapsedControls: some View {
        HStack(spacing: 10) {
            Button(L.s.aiSource.pickFromGallery) { model.aiOpenPicker(slot) }
                .buttonStyle(LinkButton())
                .font(.caption)
            Text("·").font(.caption).foregroundStyle(.quaternary)
            Button {
                Task { await model.aiPickAndUploadSource(into: slot) }
            } label: {
                if model.aiSourceUploading {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small).scaleEffect(0.6)
                        Text(L.s.aiSource.uploading)
                    }
                } else {
                    Text(L.s.aiSource.uploadNew)
                }
            }
            .buttonStyle(LinkButton())
            .font(.caption)
            .disabled(model.aiSourceUploading)
            if let emptyHint {
                Text(emptyHint).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 2)
        .help(L.s.aiSource.dropHint)
    }

    // MARK: - 选了图之后

    private var tiles: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(sources) { img in
                AISourceTile(model: model, slot: slot, img: img)
            }

            if canAdd {
                addTile(icon: "photo.badge.plus", title: L.s.aiSource.pickFromGallery) {
                    model.aiOpenPicker(slot)
                }
                addTile(icon: model.aiSourceUploading ? nil : "arrow.up.doc",
                        title: model.aiSourceUploading ? L.s.aiSource.uploading
                                                       : L.s.aiSource.uploadNew) {
                    Task { await model.aiPickAndUploadSource(into: slot) }
                }
                .disabled(model.aiSourceUploading)
                .help(L.s.aiSource.dropHint)
            }

            // 快捷条摆在两个入口右边那片空地上,而不是另起一行:它是这一行的
            // 延伸——「去选一张 / 传一张 / 就用刚传的这几张」是同一个决定的三
            // 个选项,拆成两行读起来就成了两件事。那片地方本来也空着。
            if canAdd, !model.aiRecent(slot).isEmpty {
                recentStrip
            }
        }
    }

    /// 虚线框加一句话,而不是一个小加号:空着时它是整页的起点,得比缩略图
    /// 更显眼。
    private func addTile(icon: String?, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 17, weight: .light))
                } else {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
                Text(title)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .frame(width: 96, height: 64)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.14),
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 最近上传的十张,一点就进这一行。
    ///
    /// 大多数修图针对的就是刚传上去那张,为它开一次选图窗、再从头找一遍,
    /// 步骤全花在"找回自己五秒前传的图"上。方块比原图小一半:它是捷径不是
    /// 主角,尺寸上就该分得出来。
    private var recentStrip: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L.s.aiSource.recentLabel)
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(model.aiRecent(slot)) { img in
                        Button { model.aiToggleSource(img, in: slot) } label: {
                            Thumbnail(url: img.thumbURL, client: try? model.client())
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(img.origName)
                    }
                }
                .padding(.vertical, 1)
            }
            // 不限宽:右边那片空地能铺多少铺多少,窗口窄了才横向滚。
        }
    }
}

// MARK: - 已选的一张

private struct AISourceTile: View {
    @ObservedObject var model: AppModel
    let slot: AISourceSlot
    let img: RemoteImage
    @State private var hovering = false

    var body: some View {
        Thumbnail(url: img.thumbURL, client: try? model.client())
            .frame(width: 96, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .topTrailing) {
                // 移除按钮只在悬浮时出现:四张缩略图上各挂一个常驻的叉,那一
                // 行看起来像是出了错。
                if hovering {
                    Button { model.aiRemoveSource(img, in: slot) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .help(L.s.aiSource.removeSource)
                }
            }
            .onHover { hovering = $0 }
            .help(img.origName)
    }
}

// MARK: - 选图面板

/// 从图库里选 1~4 张。两页共用,靠 `slot` 知道自己在往哪个篮子里放。
///
/// 自己拉一页而不是借图库页的 `images`:那是用户翻到的一页,借来做搜索会把
/// 他的位置和选中状态一并冲掉。
struct AISourcePicker: View {
    @ObservedObject var model: AppModel
    let slot: AISourceSlot

    private let columns = Array(repeating: GridItem(.adaptive(minimum: 96), spacing: 8), count: 1)

    var body: some View {
        FormSheet(
            title: L.s.aiSource.pickTitle,
            subtitle: L.s.aiSource.pickSubtitle(aiEditSourceLimit),
            width: 620
        ) {
            searchField
            if model.aiLibrary.isEmpty {
                Text(model.aiLibraryLoading ? L.s.common.loading : L.s.aiSource.pickEmpty)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(model.aiLibrary) { img in
                        pickTile(img)
                    }
                }
                if model.aiLibraryMore {
                    // 触底加载。网格在 ScrollView 里,这块要滚到底才渲染,
                    // 它的出现本身就是"到底了"的信号。
                    //
                    // .id 挂在条数上是必需的:同一个视图身份的 task 只跑一次,
                    // 装完一页后这块还在视野里也不会再触发,于是只能多加载
                    // 一页就卡住。换个 id 相当于换个新视图,继续往下装。
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .id(model.aiLibrary.count)
                    .task { await model.aiLoadMoreLibrary() }
                }
            }
        } footer: {
            Text(L.s.aiSource.sourceCount(model.aiSources(slot).count, aiEditSourceLimit))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            // 面板里也放一个上传:开着窗才发现"这张还没传上去",关掉窗再去
            // 找入口是白走一趟。它走的是同一个方法,传完照样自动选中。
            Button {
                Task { await model.aiPickAndUploadSource(into: slot) }
            } label: {
                if model.aiSourceUploading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                        Text(L.s.aiSource.uploading)
                    }
                } else {
                    Label(L.s.aiSource.uploadNew, systemImage: "arrow.up.doc")
                }
            }
            .buttonStyle(QuietButton())
            .disabled(model.aiSourceUploading || !model.aiCanAddSource(slot))
            Spacer()
            Button(L.s.aiSource.pickDone) { model.aiPicking = nil }
                .buttonStyle(BrandButton())
                .keyboardShortcut(.defaultAction)
        }
        // `.task(id:)` 在 id 变化时取消上一轮,所以这一句 sleep 就是去抖:
        // 连着敲的每个字母都会把前一次请求连同它的等待一起取消掉。
        .task(id: model.aiLibrarySearch) {
            if !model.aiLibrarySearch.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            await model.aiLoadLibrary()
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
            TextField(L.s.aiSource.pickSearchPlaceholder, text: $model.aiLibrarySearch)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if model.aiLibraryLoading {
                ProgressView().controlSize(.small).scaleEffect(0.6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.8)
        }
    }

    private func pickTile(_ img: RemoteImage) -> some View {
        let picked = model.aiIsPicked(img, in: slot)
        return Button {
            model.aiToggleSource(img, in: slot)
        } label: {
            Thumbnail(url: img.thumbURL, client: try? model.client())
                .frame(height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(picked ? Color.brand : .white.opacity(0.08),
                                      lineWidth: picked ? 2 : 0.8)
                }
                .overlay(alignment: .topTrailing) {
                    if picked {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.brandInk, Color.brand)
                            .padding(4)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(img.origName)
    }
}
