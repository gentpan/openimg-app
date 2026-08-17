import SwiftUI
import AppKit
import OpenimgKit

/// 文生图页。
///
/// 三段:写描述、看还剩几次、看历史。额度放在输入框正下方而不是折进设置里
/// ——这是一件**次数有限**的事,用户按下按钮之前就该知道自己还剩几次,以及
/// 用完之后是等明天还是去签到。
struct GenerateView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            composer
            quotaCard
            history
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
        .padding(.top, 4)
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

    /// 选项包一层,只为满足 PillRow 的 `Hashable & Identifiable`——尺寸与
    /// 清晰度的取值由服务器给,是字符串而不是本地枚举,不能写死。
    struct AIOption: Hashable, Identifiable {
        let value: String
        init(_ value: String) { self.value = value }
        var id: String { value }
    }

    private var sizeBinding: Binding<AIOption> {
        Binding(get: { AIOption(model.aiSize) }, set: { model.aiSize = $0.value })
    }
    private var resolutionBinding: Binding<AIOption> {
        Binding(get: { AIOption(model.aiResolution) }, set: { model.aiResolution = $0.value })
    }

    // MARK: - 额度

    @ViewBuilder
    private var quotaCard: some View {
        if let s = model.aiStatus {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 22) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.s.generate.remainingLabel)
                            .font(.caption2).foregroundStyle(.tertiary)
                        Text(L.s.generate.times(s.remaining))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(s.remaining > 0 ? AnyShapeStyle(Color.brandDisplay)
                                                             : AnyShapeStyle(Color.orange))
                    }
                    stat(L.s.generate.todayLabel, L.s.generate.todayValue(s.usedToday, s.dailyLimit))
                    stat(L.s.generate.monthlyLabel, L.s.generate.monthlyValue(s.credits, s.monthly))
                    Spacer(minLength: 12)
                    exhaustedNote(s)
                }
                if s.dailyLimit > 0 {
                    ProgressBar(
                        tint: s.remaining > 0 ? .brand : .orange,
                        value: Double(s.usedToday) / Double(s.dailyLimit)
                    )
                    .frame(height: 4)
                }
                Text(L.s.generate.landsInGallery)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(14)
            .panelSurface(12)
        }
    }

    /// 用完了要说清是哪一种用完。
    ///
    /// 本月余额先判:余额为零时明天也一样生成不了,说「明天再来」是句会让人
    /// 白等一天的话。今日上限则相反,睡一觉就有。
    @ViewBuilder
    private func exhaustedNote(_ s: AIStatus) -> some View {
        if s.remaining <= 0 {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption).foregroundStyle(.orange)
                if s.monthlyExhausted {
                    Text(L.s.generate.monthlyExhausted)
                        .font(.caption).foregroundStyle(.secondary)
                    Button(L.s.generate.goCheckin) { model.section = .overview }
                        .buttonStyle(LinkButton())
                        .font(.caption)
                } else if s.dailyExhausted {
                    // dailyExhausted 而不是 else:每日上限为 0 的部署里
                    // remaining 也是 0,那句「今天的 0 次已经用完」是胡话。
                    Text(L.s.generate.dailyExhausted(s.dailyLimit))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func stat(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.callout.weight(.medium).monospacedDigit())
        }
    }

    // MARK: - 历史

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L.s.generate.historyTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                if model.aiPending || model.aiLoading {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
                Spacer()
            }
            if model.aiGenerations.isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.aiGenerations) { gen in
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
            statusChip
            Text(gen.size)
            Text("·").foregroundStyle(.quaternary)
            Text(gen.resolution.uppercased())
            Text("·").foregroundStyle(.quaternary)
            Text(ago(gen.doneAt ?? gen.createdAt))
            if gen.status == .completed, image != nil {
                Text("·").foregroundStyle(.quaternary)
                Text(L.s.generate.inLibrary)
            }
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    private var statusChip: some View {
        Text(L.s.generate.statusLabel(gen.status))
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(chipColor)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(Capsule().fill(chipColor.opacity(0.16)))
    }

    private var chipColor: Color {
        switch gen.status {
        case .completed: .success
        case .failed: .orange
        case .charging, .pending, .running: .brand
        }
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

    /// 「3 分钟前」。formatter 每次现造:界面语言是可切的静态量,缓存一份
    /// 会把切换前的 locale 一直带下去。行数不过 30,不值得为它加缓存。
    private func ago(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = L.locale
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
