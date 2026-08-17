import SwiftUI
import OpenimgKit

/// AI 修图页。
///
/// 与生成页同一副骨架:选/写、看还剩几次、看历史。多出来的是最上面那一行
/// 原图——修图与文生图的全部差别都在那里。原图从**图库**里选,不是从硬盘:
/// 要改的图早就传上去了,再从本地挑一次等于让人回答一个已经答过的问题。
struct RetouchView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        // 自下而上:输入、额度、结果。与生成页同一套排布,理由见 GenerateView
        // 的头注——结果堆在上方离视线最近,输入压在底部始终在手边。
        VStack(spacing: 14) {
            history
            AIQuotaCard(model: model, footnote: L.s.retouch.landsInGallery)
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 26)
        .padding(.bottom, 18)
        // 与生成页共用同一条轮询,所以进出也走同一对方法——历史是一张表,
        // 分开轮只会让同一份数据被问两遍。
        .task { await model.aiViewAppeared() }
        .onDisappear { model.aiViewDisappeared() }
        .sheet(isPresented: $model.retouchPicking) {
            SourcePicker(model: model)
        }
    }

    // MARK: - 输入

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            sourceRow
            presetRow
            promptField
            optionRow(L.s.retouch.sizeLabel, options: model.aiSizes,
                      label: { $0 }, selection: sizeBinding)
            HStack(spacing: 10) {
                optionRow(L.s.retouch.resolutionLabel, options: model.aiResolutions,
                          label: { $0.uppercased() }, selection: resolutionBinding,
                          followSource: false)
                Spacer(minLength: 12)
                Text(L.s.generate.promptCounter(model.retouchPromptLength, aiPromptLimit))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(model.retouchPromptTooLong ? AnyShapeStyle(Color.orange)
                                                                : AnyShapeStyle(.tertiary))
                submitButton
            }
        }
        .padding(14)
        .panelSurface(12)
        .padding(.top, 4)
    }

    /// 已选的原图,外加一个「加图」方块。空着时那个方块就是整页的起点,所以
    /// 它比缩略图更显眼:虚线框加一句话,而不是一个小加号。
    private var sourceRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(L.s.retouch.sourcesLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 46, alignment: .leading)
                .padding(.top, 22)

            ForEach(model.retouchSources) { img in
                SourceTile(model: model, img: img)
            }

            if model.retouchCanAddSource {
                Button { model.retouchOpenPicker() } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 17, weight: .light))
                        Text(L.s.retouch.addSource)
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

            Spacer(minLength: 0)

            Text(L.s.retouch.sourceCount(model.retouchSources.count, aiEditSourceLimit))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .padding(.top, 22)
        }
    }

    /// 一键预设。点了只是把句子填进输入框,用户仍可接着改——这些是起点,
    /// 不是选项;当成单选按钮会让人以为除此之外没得选。
    private var presetRow: some View {
        HStack(spacing: 10) {
            Text(L.s.retouch.presetsLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 46, alignment: .leading)
            ScrollView(.horizontal) {
                HStack(spacing: 3) {
                    ForEach(L.s.retouch.presets) { preset in
                        Pill(text: preset.label,
                             active: model.retouchPrompt == preset.prompt) {
                            model.retouchPrompt = preset.prompt
                        }
                    }
                }
                .padding(3)
            }
            .scrollIndicators(.never)
        }
    }

    /// TextEditor 没有 placeholder,所以自己叠一层。`allowsHitTesting(false)`
    /// 是关键:否则点在提示文字上不会落到下面的编辑器里。
    private var promptField: some View {
        ZStack(alignment: .topLeading) {
            if model.retouchPrompt.isEmpty {
                Text(L.s.retouch.promptPlaceholder)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $model.retouchPrompt)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .frame(height: 64)
        }
    }

    /// followSource 决定要不要在最前面插一个空档。
    ///
    /// 尺寸可以留空——上游不给 size 时按原图比例出图,这正是「只改这一处」
    /// 想要的。清晰度不行:它是计费档位,留空等于让上游自己挑,而它可能挑
    /// 最贵的 4k。给一个点了没有任何效果的档位,比不给更糟。
    private func optionRow(
        _ title: String,
        options: [String],
        label: @escaping (String) -> String,
        selection: Binding<AIOption>,
        followSource: Bool = true
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 46, alignment: .leading)
            PillRow(items: ((followSource ? [""] : []) + options).map(AIOption.init),
                    label: { $0.value.isEmpty ? L.s.retouch.followSource : label($0.value) },
                    selection: selection)
        }
    }

    private var submitButton: some View {
        Button {
            Task { await model.retouchSubmit() }
        } label: {
            HStack(spacing: 7) {
                if model.retouchSubmitting {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Image(systemName: "wand.and.stars")
                }
                Text(model.retouchSubmitting ? L.s.retouch.retouching : L.s.retouch.retouchAction)
            }
        }
        .buttonStyle(BrandButton())
        .disabled(!model.retouchCanSubmit)
        .help(helpText)
    }

    /// 按钮是灰的时候,悬浮那句话得说清是缺哪一样。
    private var helpText: String {
        if model.retouchSources.isEmpty { return L.s.retouch.needSource }
        if model.retouchPromptTooLong { return L.s.generate.promptTooLong(aiPromptLimit) }
        return L.s.retouch.takesAWhile
    }

    private var sizeBinding: Binding<AIOption> {
        Binding(get: { AIOption(model.retouchSize) },
                set: { model.retouchSize = $0.value })
    }
    /// 读的是派生后的有效值,不是原始存储:这样界面上高亮的那一档,就是
    /// 真正会提交上去的那一档。
    private var resolutionBinding: Binding<AIOption> {
        Binding(get: { AIOption(model.effectiveRetouchResolution) },
                set: { model.retouchResolution = $0.value })
    }

    // MARK: - 历史

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L.s.retouch.historyTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                if model.aiPendingEdit || model.aiLoading {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
                Spacer()
            }
            if model.aiEditGenerations.isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.aiEditGenerations) { gen in
                            RetouchRow(model: model, gen: gen)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.brand.opacity(0.65))
                .frame(width: 76, height: 76)
                .background(Circle().fill(Color.brand.opacity(0.10)))
            Text(L.s.retouch.historyEmpty).font(.title3.weight(.medium))
            Text(L.s.retouch.historyEmptyHint)
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 已选的原图

private struct SourceTile: View {
    @ObservedObject var model: AppModel
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
                    Button { model.retouchRemoveSource(img) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .help(L.s.retouch.removeSource)
                }
            }
            .onHover { hovering = $0 }
            .help(img.origName)
    }
}

// MARK: - 选图面板

/// 从图库里选 1~4 张。
///
/// 自己拉一页而不是借图库页的 `images`:那是用户翻到的一页,借来做搜索会把
/// 他的位置和选中状态一并冲掉。
private struct SourcePicker: View {
    @ObservedObject var model: AppModel

    private let columns = Array(repeating: GridItem(.adaptive(minimum: 96), spacing: 8), count: 1)

    var body: some View {
        FormSheet(
            title: L.s.retouch.pickTitle,
            subtitle: L.s.retouch.pickSubtitle(aiEditSourceLimit),
            width: 620
        ) {
            searchField
            if model.retouchLibrary.isEmpty {
                Text(model.retouchLibraryLoading ? L.s.common.loading : L.s.retouch.pickEmpty)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(model.retouchLibrary) { img in
                        pickTile(img)
                    }
                }
            }
        } footer: {
            Text(L.s.retouch.sourceCount(model.retouchSources.count, aiEditSourceLimit))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Button(L.s.retouch.pickDone) { model.retouchPicking = false }
                .buttonStyle(BrandButton())
                .keyboardShortcut(.defaultAction)
        }
        // `.task(id:)` 在 id 变化时取消上一轮,所以这一句 sleep 就是去抖:
        // 连着敲的每个字母都会把前一次请求连同它的等待一起取消掉。
        .task(id: model.retouchSearch) {
            if !model.retouchSearch.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            await model.retouchLoadLibrary()
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
            TextField(L.s.retouch.pickSearchPlaceholder, text: $model.retouchSearch)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if model.retouchLibraryLoading {
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
        let picked = model.retouchIsPicked(img)
        return Button {
            model.retouchToggleSource(img)
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

// MARK: - 历史行

private struct RetouchRow: View {
    @ObservedObject var model: AppModel
    let gen: AIGeneration

    private var result: RemoteImage? { gen.imageID.flatMap { model.aiImages[$0] } }
    /// 原图从 aiImages 里取:提交那一刻就存进去了,之后的轮询也只会往里加。
    /// 取不到说明那张图后来在图库里被删了。
    private var sources: [RemoteImage] { gen.sourceIDs.compactMap { model.aiImages[$0] } }

    var body: some View {
        HStack(spacing: 11) {
            sourceStrip
            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
            preview
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(gen.prompt)
                    .font(.callout)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                meta
                if let e = gen.error, !e.isEmpty {
                    // 照实显示上游给的原因。失败会退还次数(后端做的)。
                    Text(e).font(.caption2).foregroundStyle(.orange).lineLimit(2)
                }
            }

            actions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .panelSurface(10)
        .help("\(gen.prompt)\n\(L.s.generate.modelLabel(gen.model))")
    }

    /// 原图。最多摆两张,余下的写成「+2」——一行里挤四张缩略图,每张都小到
    /// 认不出是什么。
    private var sourceStrip: some View {
        HStack(spacing: 3) {
            if sources.isEmpty {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(0.06)))
                    .help(L.s.retouch.sourcesGone)
            } else {
                ForEach(sources.prefix(2)) { img in
                    Thumbnail(url: img.thumbURL, client: try? model.client())
                        .frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .help(img.origName)
                }
                if sources.count > 2 {
                    Text(L.s.retouch.moreSources(sources.count - 2))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let img = result {
            Thumbnail(url: img.thumbURL, client: try? model.client())
        } else {
            ZStack {
                Rectangle().fill(.white.opacity(0.06))
                switch gen.status {
                case .charging, .pending, .running:
                    ProgressView().controlSize(.small)
                case .failed:
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 15)).foregroundStyle(.orange)
                case .completed:
                    // 完成了却没有图:那张图后来在图库里被删了。
                    Image(systemName: "photo").font(.system(size: 15)).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var meta: some View {
        HStack(spacing: 6) {
            AIStatusChip(status: gen.status)
            Text(gen.size)
            Text("·").foregroundStyle(.quaternary)
            Text(gen.resolution.uppercased())
            Text("·").foregroundStyle(.quaternary)
            Text(aiAgo(gen.doneAt ?? gen.createdAt))
            if gen.status == .completed, result != nil {
                Text("·").foregroundStyle(.quaternary)
                Text(L.s.generate.inLibrary)
            }
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    private var actions: some View {
        ToolCluster {
            ToolTile(icon: "arrow.uturn.backward", help: L.s.retouch.reuse) {
                model.retouchReuse(gen)
            }
            if let img = result {
                ToolTile(icon: "link", help: L.s.common.copyLink) {
                    model.copy(model.linkFormat.render(img))
                    model.announce(L.s.common.copied)
                }
                ToolTile(icon: "photo.on.rectangle", help: L.s.generate.viewInGallery) {
                    model.section = .gallery
                    model.detail = img
                }
            }
        }
    }
}
