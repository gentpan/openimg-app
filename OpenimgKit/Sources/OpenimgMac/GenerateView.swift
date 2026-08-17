import SwiftUI
import AppKit
import OpenimgKit

/// 文生图页。
///
/// 三段自下而上:写描述、看还剩几次、看历史。输入压在底部、结果堆在上方,
/// 是对话式的排布——刚生成的图出现在离视线最近的地方,而输入框始终在手边,
/// 连着生成好几张时不必来回找。额度卡紧贴输入框上方:这是一件**次数有限**
/// 的事,按下按钮之前就该知道还剩几次,以及用完之后是等明天还是去签到。
struct GenerateView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            history
            // 额度卡与修图页共用一份:同一个额度池,不该有两处各自的说法。
            AIQuotaCard(model: model, footnote: L.s.generate.landsInGallery)
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 26)
        .padding(.bottom, 18)
        // 取状态、拉历史、按需起轮询,都在 aiViewAppeared 里;这里只管把页面
        // 的出现与离开如实告诉 model——轮询以「页面在不在」为总闸。
        .task { await model.aiViewAppeared() }
        .onDisappear { model.aiViewDisappeared() }
    }

    // MARK: - 输入

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            promptField
            optionRow(L.s.generate.sizeLabel, options: model.aiSizes,
                      label: { $0 }, selection: sizeBinding)
            HStack(spacing: 10) {
                optionRow(L.s.generate.resolutionLabel, options: model.aiResolutions,
                          label: { $0.uppercased() }, selection: resolutionBinding)
                Spacer(minLength: 12)
                Text(L.s.generate.promptCounter(model.aiPromptLength, aiPromptLimit))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(model.aiPromptTooLong ? AnyShapeStyle(Color.orange)
                                                           : AnyShapeStyle(.tertiary))
                submitButton
            }
        }
        .padding(14)
        .panelSurface(12)
    }

    /// TextEditor 没有 placeholder,所以自己叠一层。`allowsHitTesting(false)`
    /// 是关键:否则点在提示文字上不会落到下面的编辑器里。
    private var promptField: some View {
        ZStack(alignment: .topLeading) {
            if model.aiPrompt.isEmpty {
                Text(L.s.generate.promptPlaceholder)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $model.aiPrompt)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .frame(height: 76)
        }
    }

    private func optionRow(
        _ title: String,
        options: [String],
        label: @escaping (String) -> String,
        selection: Binding<AIOption>
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 46, alignment: .leading)
            PillRow(items: options.map(AIOption.init),
                    label: { label($0.value) },
                    selection: selection)
        }
    }

    private var submitButton: some View {
        Button {
            Task { await model.aiGenerate() }
        } label: {
            HStack(spacing: 7) {
                if model.aiSubmitting {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(model.aiSubmitting ? L.s.generate.generating : L.s.generate.generateAction)
            }
        }
        .buttonStyle(BrandButton())
        .disabled(!model.aiCanSubmit)
        .help(model.aiPromptTooLong ? L.s.generate.promptTooLong(aiPromptLimit)
                                    : L.s.generate.takesAWhile)
    }

    private var sizeBinding: Binding<AIOption> {
        Binding(get: { AIOption(model.aiSize) }, set: { model.aiSize = $0.value })
    }
    private var resolutionBinding: Binding<AIOption> {
        Binding(get: { AIOption(model.aiResolution) }, set: { model.aiResolution = $0.value })
    }

    // MARK: - 历史

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L.s.generate.historyTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                if model.aiPendingText || model.aiLoading {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
                Spacer()
            }
            // 只看文生图那一半。修图记录混进来,那句「用这句再生成」会丢掉原图,
            // 重来一次得到的是另一件事。
            if model.aiTextGenerations.isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.aiTextGenerations) { gen in
                            GenerationRow(model: model, gen: gen)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.brand.opacity(0.65))
                .frame(width: 76, height: 76)
                .background(Circle().fill(Color.brand.opacity(0.10)))
            Text(L.s.generate.historyEmpty).font(.title3.weight(.medium))
            Text(L.s.generate.historyEmptyHint)
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 历史行

private struct GenerationRow: View {
    @ObservedObject var model: AppModel
    let gen: AIGeneration

    private var image: RemoteImage? { gen.imageID.flatMap { model.aiImages[$0] } }

    var body: some View {
        HStack(spacing: 11) {
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
                    // 照实显示上游给的原因。失败会退还次数(后端做的),所以
                    // 这里不必再补一句「已退还」以外的解释。
                    Text(e).font(.caption2).foregroundStyle(.orange).lineLimit(2)
                }
            }

            actions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .panelSurface(10)
        // 描述在行里只显示两行,悬浮给全文;模型名跟在后面——它是「这张图
        // 怎么来的」的一部分,但不值得占据本就拥挤的那行元信息。
        .help("\(gen.prompt)\n\(L.s.generate.modelLabel(gen.model))")
    }

    @ViewBuilder
    private var preview: some View {
        if let img = image {
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
            if gen.status == .completed, image != nil {
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
            ToolTile(icon: "arrow.uturn.backward", help: L.s.generate.usePrompt) {
                model.aiReuse(gen)
            }
            if let img = image {
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
