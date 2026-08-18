import SwiftUI
import OpenimgKit

/// AI 修图页。
///
/// 与生成页同一副骨架:选/写、看还剩几次、看历史。最上面那一行原图是这一页
/// 的起点,而它与生成页的「参考图」是同一个视图(AISourceRow)。
///
/// 原图最终一律是**图库里的一张图**:提交只发 id,图片字节一趟也不经过本机。
/// 硬盘上的图不是不能用——「上传新图」和拖放会先把它按正常流水线传进图库,
/// 拿到 id 再选中;不是编码成 base64 塞进请求。
struct RetouchView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        // 自下而上:输入、额度、结果。与生成页同一套排布,理由见 GenerateView
        // 的头注——结果堆在上方离视线最近,输入压在底部始终在手边。
        VStack(spacing: 14) {
            history
            // 用完了才出现,平时不占版面——数字已经在输入区底排说清了。
            AIQuotaNotice(model: model)
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 26)
        .padding(.bottom, 18)
        // 与生成页共用同一条轮询,所以进出也走同一对方法——历史是一张表,
        // 分开轮只会让同一份数据被问两遍。
        .task { await model.aiViewAppeared() }
        .onDisappear { model.aiViewDisappeared() }
        // 选图面板与生成页共用一个(见 AISourceRow.swift),靠 slot 认篮子。
        .sheet(item: $model.aiPicking) { slot in
            AISourcePicker(model: model, slot: slot)
        }
    }

    // MARK: - 输入

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 原图那一行与生成页的参考图是同一个视图:同样从图库选、同样能
            // 直接传一张进来。这里不收窄——没有原图就没有下一步,那个框就是
            // 整页的起点。
            AISourceRow(model: model, slot: .retouch, label: L.s.retouch.sourcesLabel)
            presetRow
            promptField
            optionRow(L.s.retouch.sizeLabel, options: model.aiSizes,
                      label: { $0 }, selection: sizeBinding)
            HStack(spacing: 10) {
                optionRow(L.s.retouch.resolutionLabel, options: model.aiResolutions,
                          label: { $0.uppercased() }, selection: resolutionBinding,
                          followSource: false)
                Spacer(minLength: 12)
                // 底排本来空着一大片,而「还剩几次」正是按下生成之前最后要
                // 确认的事——放在按钮边上比放在页面顶部一张卡里更该看见。
                AIQuotaInline(model: model)
                Spacer(minLength: 8)
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

    /// 一键预设。点了只是把句子填进输入框,用户仍可接着改——这些是起点,
    /// 不是选项;当成单选按钮会让人以为除此之外没得选。
    private var presetRow: some View {
        HStack(spacing: 10) {
            Text(L.s.retouch.presetsLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 46, alignment: .leading)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(L.s.retouch.presets) { preset in
                        Pill(text: preset.label,
                             active: model.retouchPrompt == preset.prompt,
                             bordered: true) {
                            // 再点一次取消:点错了不必去输入框里手动清空。
                            model.retouchPrompt =
                                model.retouchPrompt == preset.prompt ? "" : preset.prompt
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
                    .padding(.leading, 9)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $model.retouchPrompt)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(height: 64)
        }
        // 原来没有边框,和面板底色连成一片,看不出哪里可以打字。
        //
        // 描边加一层极淡的底,而不是压一块实色:这套界面是半透明叠层,实底
        // 会在它上面显脏。超长时描边转橙,和右下角那个字数计数说的是同一件
        // 事——两处一起变,用户不必去数字符。
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.black.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(model.retouchPromptTooLong ? Color.orange.opacity(0.75)
                                        : .white.opacity(0.12),
                              lineWidth: 1)
        )
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
