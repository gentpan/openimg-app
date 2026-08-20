import SwiftUI
import UniformTypeIdentifiers
import OpenimgKit

struct UploadView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            if model.queue.isEmpty {
                // The drop target takes the room rather than floating in it.
                // A small dashed box centred in a large empty page reads as an
                // afterthought; on this screen it is the whole point.
                dropZone
                fetchList
                urlRow
                editRow
                settingsHint
                formatRow
                limits
            } else {
                batchHeader
                queueList
                // The drop zone stays reachable while a batch is on screen, so
                // adding more files does not mean clearing the list first.
                dropZone.frame(maxHeight: 76)
                fetchList
                urlRow
                editRow
                formatRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 26)
        .padding(.bottom, 18)
        // Cmd+V。走 onPasteCommand 而不是给按钮挂快捷键:前者participates in
        // 响应者链,焦点在输入框里时系统会先把 Cmd+V 交给输入框,不会把地址栏
        // 里的粘贴劫走。
        .onPasteCommand(of: [.fileURL, .image, .url, .plainText]) { _ in
            Task { await model.pasteAndUpload() }
        }
    }

    // MARK: - 网址取图

    /// 地址栏 + 粘贴。
    ///
    /// 摆在拖放区下面而不是塞进拖放区里:拖放区是一块"往这儿扔"的靶子,里面
    /// 放一个要点进去打字的输入框,两种交互会互相干扰——点输入框会先触发靶子
    /// 自己的点击(选文件)。
    private var urlRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
            TextField(L.s.upload.urlPlaceholder, text: $model.urlDraft)
                .textFieldStyle(.plain)
                .font(.callout)
                .onSubmit { model.fetchFromURL(model.urlDraft) }
            Button(L.s.upload.urlFetch) { model.fetchFromURL(model.urlDraft) }
                .buttonStyle(QuietButton())
                .controlSize(.small)
                .disabled(model.urlDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            Button(L.s.upload.pasteButton) { Task { await model.pasteAndUpload() } }
                .buttonStyle(QuietButton())
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .frame(height: Metrics.field)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var fetchList: some View {
        if !model.fetches.isEmpty {
            VStack(spacing: 6) {
                ForEach(model.fetches) { fetchRow($0) }
            }
        }
    }

    private func fetchRow(_ f: AppModel.RemoteFetch) -> some View {
        let bad = f.failed != nil
        return HStack(spacing: 10) {
            Image(systemName: bad ? "exclamationmark.triangle.fill" : "arrow.down.circle")
                .font(.system(size: 14))
                .foregroundStyle(bad ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Color.brand))
            VStack(alignment: .leading, spacing: 4) {
                Text(f.name).font(.callout).lineLimit(1).truncationMode(.middle)
                if let why = f.failed {
                    Text(why).font(.caption).foregroundStyle(.orange).lineLimit(2)
                } else if let frac = f.fraction {
                    ProgressBar(value: frac).frame(height: 4)
                    Text("\(model.bytes(f.received)) / \(model.bytes(f.total))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                } else {
                    // 对方没给 Content-Length。**不画进度条**——没有分母的进度
                    // 条只能瞎猜一个位置,而那是在骗人。转圈加已下载字节说的是
                    // 实话:还在下,已经下了这么多。
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(L.s.upload.fetchingUnknownSize(model.bytes(f.received)))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            Button(bad ? L.s.upload.dismissFetch : L.s.upload.cancelFetch) {
                model.dropFetch(f.id)
            }
            .buttonStyle(QuietButton())
            .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.04))
        )
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(model.dropping ? Color.brand.opacity(0.14) : .white.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(model.dropping ? Color.brand : .white.opacity(0.14),
                                  style: StrokeStyle(lineWidth: model.dropping ? 2 : 1.2, dash: [7, 5]))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { zoneContent }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !model.uploading else { return }
                Task { await model.pickAndUpload() }
            }
            .onDrop(of: [.fileURL], isTargeted: $model.dropping) { providers in
                // Dropped folders expand the same way a picked one does.
                // handleDrop 里再分流:开了"单张先编辑"且恰好一张静态图时
                // 进编辑器,其余直接上传。
                Task { await model.handleDrop(await DroppedFiles.urls(from: providers)) }
                return true
            }
            .animation(.easeOut(duration: 0.15), value: model.dropping)
    }

    /// 编辑入口:显式按钮 + 可选的"单张拖入先编辑"。
    private var editRow: some View {
        HStack(spacing: 14) {
            Button {
                model.pickAndEdit()
            } label: {
                Label(L.s.upload.editThenUpload, systemImage: "crop")
            }
            .buttonStyle(QuietButton())
            .help(L.s.upload.editHelp)
            Toggle(L.s.upload.editOnDrop, isOn: Binding(
                get: { model.editOnDrop },
                set: { model.editOnDrop = $0; model.saveWatermarkPrefs() }
            ))
            .toggleStyle(.checkbox)
            .font(.callout)
        }
    }

    @ViewBuilder
    private var zoneContent: some View {
        if model.queue.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "arrow.up.doc")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Color.brand)
                    .frame(width: 88, height: 88)
                    .background(Circle().fill(Color.brand.opacity(0.12)))
                Text(L.s.upload.dropTitle).font(.title2.weight(.medium))
                Text(L.s.upload.dropHint)
                    .font(.callout).foregroundStyle(.secondary)
            }
        } else {
            Label(L.s.upload.addMore, systemImage: "plus")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: - Batch

    private var batchHeader: some View {
        VStack(spacing: 9) {
            HStack {
                if model.uploading {
                    ProgressView().controlSize(.small)
                    Text(L.s.upload.uploadingProgress(
                        model.queue.filter { $0.state == .done }.count, model.queue.count))
                        .font(.callout)
                } else {
                    let ok = model.queue.filter { $0.state == .done }.count
                    let bad = model.queue.count - ok
                    Image(systemName: bad == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(bad == 0 ? .green : .orange)
                    Text(bad == 0 ? L.s.upload.allDone(ok) : L.s.upload.partlyDone(ok, bad))
                        .font(.callout)
                }
                Spacer()
                Button(model.uploading ? L.s.upload.uploadingBusy : L.s.upload.clearList) { model.clearQueue() }
                    .buttonStyle(QuietButton())
                    .disabled(model.uploading)
            }
            ProgressBar(value: model.batchProgress)
                .frame(height: 5)
        }
        .padding(14)
        .panelSurface(12)
        .padding(.top, 4)
    }

    private var queueList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(model.queue) { QueueRow(item: $0, bytes: model.bytes) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Bits

    private var formatRow: some View {
        VStack(spacing: 7) {
            Text(L.s.upload.copyAfterUpload).font(.caption).foregroundStyle(.secondary)
            PillRow(items: LinkFormat.allCases, label: { L.s.gallery.linkLabel($0) },
                    selection: $model.linkFormat)
        }
    }

    /// Conversion settings, here rather than only in settings: this is where
    /// the user is about to upload, and it is the moment they care whether the
    /// file gets re-encoded. The same values live on the account, so a change
    /// made here shows up on the website too.
    /// Where the compression controls went.
    ///
    /// They used to live here as a second copy of the settings page's card,
    /// which meant two places to change the same account-level preference and
    /// two places to keep in sync. The preference applies to every upload from
    /// every client, so it belongs where account preferences live; what belongs
    /// here is knowing what it is currently set to.
    private var settingsHint: some View {
        // 当前设置是一串值,「在设置里改」是一个动作——中间隔开,否则末尾那
        // 项和链接只差 6pt 又没有分隔点,会连读成一句话("WebP 在设置里改")。
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(L.s.settings.modeLabel(model.uploadMode))
                Text("·").foregroundStyle(.quaternary)
                Text(L.s.settings.variantLabel(model.variantFormat))
                if model.maxImageWidth > 0 {
                    Text("·").foregroundStyle(.quaternary)
                    Text(L.s.upload.maxWidth(model.maxImageWidth))
                }
            }
            Button(L.s.upload.changeInSettings) { model.section = .settings }
                .buttonStyle(LinkButton())
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    struct Width: Hashable, Identifiable {
        let px: Int
        init(_ px: Int) { self.px = px }
        var id: Int { px }
        var label: String { px == 0 ? L.s.upload.unlimited : "\(px)" }
    }

    @ViewBuilder
    private var limits: some View {
        if let t = model.quota?.tier {
            HStack(spacing: 18) {
                if t.dailyUploadCount > 0, let used = model.quota?.uploadsToday {
                    let left = max(0, t.dailyUploadCount - used)
                    // Before the upload rather than after the failure: unlike
                    // the per-minute limit, the daily count does not clear
                    // until tomorrow, so it is not something to retry through.
                    stat(L.s.upload.remainingToday, L.s.upload.imageCount(left), warn: left <= 5)
                }
                stat(L.s.upload.maxFileSize, model.bytes(t.maxFileSize))
                stat(L.s.upload.supportedFormats,
                     t.allowedFormats.prefix(4).joined(separator: " · ").uppercased())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .panelSurface(12)
        }
    }

    private func stat(_ k: String, _ v: String, warn: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(k).font(.caption2).foregroundStyle(.tertiary)
            Text(v).font(.callout.weight(.medium)).foregroundStyle(warn ? .orange : .primary)
        }
    }

}

// MARK: - Row

private struct QueueRow: View {
    let item: UploadItem
    let bytes: (Int64) -> String

    var body: some View {
        HStack(spacing: 11) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name).font(.callout).lineLimit(1).truncationMode(.middle)
                    if let sent = item.sentBytes, item.size > 0 {
                        Text(L.s.upload.shrunkTo(Int(Double(sent) / Double(item.size) * 100)))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.brand)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.brand.opacity(0.16)))
                    }
                    if item.deduplicated {
                        Text(L.s.upload.deduplicated)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.success)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Capsule().fill(.green.opacity(0.16)))
                    }
                    Spacer(minLength: 0)
                    Text(detail).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
                if case .uploading = item.state {
                    ProgressBar(value: item.progress).frame(height: 3)
                } else if case .failed(let why) = item.state {
                    Text(why).font(.caption2).foregroundStyle(.orange).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .panelSurface(10)
    }

    private var detail: String {
        switch item.state {
        case .queued: L.s.upload.waiting
        case .uploading: "\(Int(item.progress * 100))%"
        case .done: item.size > 0 ? bytes(item.size) : L.s.upload.done
        case .failed: ""
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch item.state {
        case .queued:
            Image(systemName: "clock").foregroundStyle(.tertiary)
        case .uploading:
            ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.brand)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        }
    }
}

/// One progress bar shape, so the batch bar and the per-file bars match.
struct ProgressBar: View {
    var tint: Color = .brand
    /// 出现时是否从 0 长出来。上传进度条本来就从 0 开始,不需要;概览页那些
    /// 一出现就该显示既有值的才需要。
    var animatesIn = false

    let value: Double
    @State private var reveal: Double = 0
    /// 所在卡片的入场延迟。上传进度条(animatesIn = false)用不上它。
    @Environment(\.entranceDelay) private var entranceDelay

    private var shown: Double {
        min(1, max(0, value)) * (animatesIn ? reveal : 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.10))
                Capsule().fill(tint)
                    .frame(width: max(shown > 0 ? 2 : 0, geo.size.width * shown))
                    .animation(Reveal.change, value: value)
            }
        }
        .reveal($reveal, delay: animatesIn ? entranceDelay + Entrance.innerLead : 0)
    }
}
