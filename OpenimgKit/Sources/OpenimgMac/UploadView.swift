import SwiftUI
import OpenimgKit
import UniformTypeIdentifiers

struct UploadView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            if model.queue.isEmpty {
                // The drop target takes the room rather than floating in it.
                // A small dashed box centred in a large empty page reads as an
                // afterthought; on this screen it is the whole point.
                dropZone
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
                editRow
                formatRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 26)
        .padding(.bottom, 18)
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
                Task { await model.handleDrop(await urls(from: providers)) }
                return true
            }
            .animation(.easeOut(duration: 0.15), value: model.dropping)
            .sheet(item: $model.editTarget) { t in
                EditorSheet(model: model, source: t.url)
            }
    }

    /// 编辑入口:显式按钮 + 可选的"单张拖入先编辑"。
    private var editRow: some View {
        HStack(spacing: 14) {
            Button {
                model.pickAndEdit()
            } label: {
                Label(L.s.upload.editThenUpload, systemImage: "crop")
            }
            .controlSize(.small)
            .help(L.s.upload.editHelp)
            Toggle(L.s.upload.editOnDrop, isOn: Binding(
                get: { model.editOnDrop },
                set: { model.editOnDrop = $0; model.saveWatermarkPrefs() }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
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
        HStack(spacing: 6) {
            Text(L.s.settings.modeLabel(model.uploadMode))
            Text("·").foregroundStyle(.quaternary)
            Text(L.s.settings.variantLabel(model.variantFormat))
            if model.maxImageWidth > 0 {
                Text("·").foregroundStyle(.quaternary)
                Text(L.s.upload.maxWidth(model.maxImageWidth))
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

    /// NSItemProvider returns a file URL as its Data representation; decoding it
    /// any other way silently yields nil for every drop.
    ///
    /// 用 completion 版接口而不是 async 的 loadItem:后者返回
    /// `any NSSecureCoding`,在正式版 SDK 的严格并发下不可跨界发送
    /// (本机 beta 放行只是巧合)。Data 是 Sendable,包个 continuation 了事。
    private func urls(from providers: [NSItemProvider]) async -> [URL] {
        var out: [URL] = []
        for p in providers {
            let data: Data? = await withCheckedContinuation { cont in
                _ = p.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    cont.resume(returning: data)
                }
            }
            guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { continue }
            out.append(url)
        }
        return out
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

    let value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.10))
                Capsule().fill(tint)
                    .frame(width: max(2, geo.size.width * min(1, max(0, value))))
                    .animation(.easeOut(duration: 0.2), value: value)
            }
        }
    }
}
