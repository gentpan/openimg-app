import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OpenimgKit

struct SettingsView: View {
    @ObservedObject var model: AppModel
    /// nil means "showing whatever the server says". It only holds a value
    /// while the field is being edited, so the card never has to be told that
    /// the account changed underneath it.
    @State private var draftName: String?
    @State private var editingName = false
    @State private var code = ""
    @State private var newPassword = ""
    @State private var pkCode = ""
    @State private var pkName = ""
    @State private var newPassword2 = ""
    /// nil 不显示表单;.some(nil) 新建;.some(profile) 编辑。
    @State private var storageForm: StorageProfile?? = nil
    @State private var avatarHover = false
    @State private var avatarDropping = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            // Two columns, matching the overview page.
            //
            // Six cards in one 560pt column inside a 1240pt window made the
            // page twice as long as it needed to be while leaving a third of
            // the width empty on either side. Split by what the cards are
            // about: who you are and how you get in on the left, what happens
            // to your images and where they go on the right.
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    profileCard
                    appearanceCard
                    securityCard
                    dangerCard
                }
                VStack(spacing: 16) {
                    conversionCard
                    watchCard
                    watermarkCard
                    locationCard
                    siteCard
                }
            }
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)   // centres the block in a wide window
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity)
        .task(id: model.account?.id) { await model.loadStats() }
    }

    // MARK: - Cards

    /// Editable, where it used to be a read-only block.
    ///
    /// It was read-only because the nickname and avatar routes were in the
    /// cookie-only group and this client holds a token, so every write would
    /// have 401'd. They now sit alongside the other things a token may do to
    /// its own account — see the note in router.go for where that line is.
    private var profileCard: some View {
        SettingsCard(L.s.settings.profile, "person.crop.circle") {
            if let a = model.account {
                HStack(alignment: .top, spacing: 14) {
                    avatarWell(a)

                    VStack(alignment: .leading, spacing: 8) {
                        nameField(a)
                        Text(a.email).font(.callout).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            tag(a.role)
                            // Role and tier are separate fields that happen to
                            // carry the same word for admins; printing both
                            // gives "admin admin".
                            if let t = model.quota?.tier, t.name != a.role { tag(t.name) }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// 头像本体就是入口:点击选图、悬浮显相机、把图片拖上来直接换——
    /// 下面的文字链接保留,给不喜欢猜交互的人一条明路。
    private func avatarWell(_ a: Account) -> some View {
        VStack(spacing: 6) {
            Button {
                Task { await model.pickAvatar() }
            } label: {
                Avatar(account: a, size: 62, client: try? model.client())
                    .overlay(
                        Circle().strokeBorder(
                            avatarDropping ? Color.brand : .white.opacity(0.12),
                            lineWidth: avatarDropping ? 2 : 1)
                    )
                    .overlay {
                        if avatarHover || avatarDropping {
                            Circle().fill(.black.opacity(0.45))
                            Image(systemName: avatarDropping ? "arrow.down.circle.fill" : "camera.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                        }
                    }
            }
            .buttonStyle(.plain)
            .onHover { avatarHover = $0 }
            .animation(.easeOut(duration: 0.12), value: avatarHover || avatarDropping)
            .help(L.s.settings.avatarHelp)
            .onDrop(of: [.fileURL], isTargeted: $avatarDropping) { providers in
                Task {
                    if let url = await Self.firstFileURL(from: providers) {
                        await model.setAvatar(url)
                    }
                }
                return true
            }
            HStack(spacing: 4) {
                Button(L.s.settings.change) { Task { await model.pickAvatar() } }
                    .buttonStyle(LinkButton()).font(.caption)
                if a.avatarURL?.isEmpty == false {
                    Text("·").font(.caption).foregroundStyle(.quaternary)
                    Button(L.s.settings.remove) { Task { await model.removeAvatar() } }
                        .buttonStyle(LinkButton()).font(.caption)
                }
            }
            .disabled(model.busy)
        }
    }

    /// 与 UploadView 同款的拖放解码(completion 版接口,规避 async loadItem
    /// 返回类型在正式版 SDK 严格并发下不可跨界的问题)。
    private static func firstFileURL(from providers: [NSItemProvider]) async -> URL? {
        for p in providers {
            let data: Data? = await withCheckedContinuation { cont in
                _ = p.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    cont.resume(returning: data)
                }
            }
            if let data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                return url
            }
        }
        return nil
    }

    /// Commits on Return and on losing focus, and reverts on Escape.
    ///
    /// A save button for one short string is a button people forget to press;
    /// blur-to-save is what the website does, so the two agree.
    private func nameField(_ a: Account) -> some View {
        TextField(L.s.settings.nickname, text: Binding(
            get: { draftName ?? a.name },
            set: { draftName = $0 }
        ))
            .textFieldStyle(.plain)
            .font(.title3.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(editingName ? 0.08 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.white.opacity(editingName ? 0.14 : 0), lineWidth: 1)
            )
            .frame(maxWidth: 260)
            .onSubmit { commitName() }
            .onExitCommand { draftName = nil; editingName = false }
            .focused($nameFocused)
            .onChange(of: nameFocused) { _, focused in
                editingName = focused
                if !focused { commitName() }
            }
            .animation(.easeOut(duration: 0.12), value: editingName)
    }

    private func commitName() {
        guard let draft = draftName else { return }
        // Dropped before the request, not after: `saveNickname` refreshes the
        // account, and whatever the server decided to store is then what shows
        // — including a trim or a 32-character truncation the user did not do.
        draftName = nil
        Task { await model.saveNickname(draft) }
    }

    /// Read-only on purpose.
    ///
    /// Creating and editing a storage profile means handing over the S3 access
    /// key and secret, and those routes are cookie-only by design — a token
    /// pasted into a PicGo config must not be able to read them back. So the
    /// app shows where the bytes actually sit and sends the user to the site to
    /// change it. The numbers come from /api/storage/summary, which the token
    /// can already reach.
    private var locationCard: some View {
        SettingsCard(L.s.settings.location, "externaldrive.connected.to.line.below") {
            VStack(alignment: .leading, spacing: 10) {
                if !model.storageProfiles.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(model.storageProfiles.enumerated()), id: \.element.id) { i, p in
                            if i > 0 { Divider().overlay(Color.white.opacity(0.06)) }
                            profileRow(p)
                        }
                    }
                } else if model.statsLoading {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                }

                if let form = storageForm {
                    Divider().overlay(Color.white.opacity(0.06))
                    StorageProfileForm(model: model, editing: form) { storageForm = nil }
                } else {
                    HStack(spacing: 8) {
                        Button {
                            model.storageCodeSent = false
                            storageForm = .some(nil)
                        } label: {
                            Label(L.s.settings.storageAdd, systemImage: "plus")
                        }
                        .buttonStyle(QuietButton())
                        .disabled(model.busy)
                        Spacer()
                    }
                }

                Text(L.s.settings.locationKeyNote)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .task(id: model.account?.id) { await model.loadStorageProfiles() }
    }

    /// 一行一个存储位置:名称与用量在左,操作在右。平台池不可编辑也不可删,
    /// 但可以被设回默认。
    private func profileRow(_ p: StorageProfile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: p.isPlatform ? "cube.box" : "externaldrive.badge.person.crop")
                .font(.system(size: 14))
                .foregroundStyle(p.isActive ? Color.brand : .orange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(p.name).font(.callout)
                    if p.isDefault {
                        Text(L.s.settings.storageDefaultBadge)
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.brand.opacity(0.18)))
                            .foregroundStyle(Color.brand)
                    }
                }
                if let err = p.lastError, !err.isEmpty, !p.isActive {
                    Text(err).font(.caption2).foregroundStyle(.orange).lineLimit(1)
                } else if let k = kindLabel(p.kind), k != p.name {
                    Text(k).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(model.bytes(p.storedBytes)).font(.callout.monospacedDigit())
                Text(L.s.settings.imageCount(Int(p.imageCount)))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Menu {
                if !p.isDefault, p.isActive {
                    Button(L.s.settings.storageSetDefault) { requestThen { code in
                        await model.setDefaultStorageProfile(p, code: code)
                    } }
                }
                if !p.isPlatform {
                    Button(L.s.settings.storageTest) {
                        Task {
                            do { try await model.client().testStorageProfile(id: p.id)
                                 model.announce(L.s.settings.storageTestPassed) }
                            catch { model.announce(model.message(error)) }
                        }
                    }
                    Button(L.s.settings.storageEdit) {
                        model.storageCodeSent = false
                        storageForm = .some(p)
                    }
                    Divider()
                    Button(L.s.settings.delete, role: .destructive) { requestThen { code in
                        await model.deleteStorageProfile(p, code: code)
                    } }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
            .disabled(p.isPlatform && p.isDefault)
        }
        .padding(.vertical, 9)
    }

    /// 设默认与删除同样要码,但它们没有表单可以承载输入框——用一个小对话框
    /// 收码,免得为两个动作各建一套界面。
    private func requestThen(_ action: @escaping (String) async -> Void) {
        Task {
            await model.sendCode(.storage)
            guard model.storageCodeSent else { return }
            let alert = NSAlert()
            alert.messageText = L.s.settings.codeField
            alert.informativeText = L.s.settings.codeSentTo(model.storageCodeSentTo)
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            alert.accessoryView = field
            alert.addButton(withTitle: L.s.settings.confirmChange)
            alert.addButton(withTitle: L.s.settings.cancel)
            guard alert.runModal() == .alertFirstButtonReturn else {
                model.storageCodeSent = false
                return
            }
            await action(field.stringValue.trimmingCharacters(in: .whitespaces))
        }
    }

    private func kindLabel(_ kind: String) -> String? {
        switch kind {
        case "platform": L.s.settings.kindPlatform
        case "s3", "r2": L.s.settings.kindOwnBucket(kind.uppercased())
        default: kind.isEmpty ? nil : kind
        }
    }

    /// The same three values the upload page offers. Both write to the account,
    /// so whichever one the user reaches for, the website agrees.
    private var conversionCard: some View {
        SettingsCard(L.s.settings.processing, "wand.and.stars") {
            VStack(alignment: .leading, spacing: 14) {
                setting(L.s.settings.mode, L.s.settings.modeDetail(model.uploadMode)) {
                    PillRow(items: UploadMode.allCases,
                            label: { L.s.settings.modeLabel($0) },
                            selection: pref($model.uploadMode))
                }
                setting(L.s.settings.autoConvert,
                        model.uploadMode == .original
                        ? L.s.settings.autoConvertOff : L.s.settings.autoConvertHint) {
                    PillRow(items: VariantFormat.allCases,
                            label: { L.s.settings.variantLabel($0) },
                            selection: pref($model.variantFormat))
                        .disabled(model.uploadMode == .original)
                        .opacity(model.uploadMode == .original ? 0.45 : 1)
                }
                setting(L.s.settings.maxWidth,
                        model.uploadMode == .original
                        ? L.s.settings.maxWidthOff : L.s.settings.maxWidthHint) {
                    PillRow(items: allowedMaxWidths.map(UploadView.Width.init),
                            label: \.label, selection: widthPref)
                        // Original mode ships the bytes untouched, so a width
                        // here does nothing. The web disables it; leaving it
                        // live on this end just invites setting a value that
                        // silently has no effect.
                        .disabled(model.uploadMode == .original)
                        .opacity(model.uploadMode == .original ? 0.45 : 1)
                }
                if let t = model.quota?.tier {
                    // The limits these three controls operate inside. They were
                    // a card of their own, which meant a read-only card sitting
                    // in a page of settings; against the switches they bound,
                    // they read as the constraint they are.
                    VStack(spacing: 0) {
                        Divider().overlay(Color.white.opacity(0.06))
                        row(L.s.settings.maxFileSize, model.bytes(t.maxFileSize))
                        Divider().overlay(Color.white.opacity(0.06))
                        row(L.s.settings.dailyUpload,
                            t.dailyUploadCount > 0
                            ? L.s.settings.imageCount(t.dailyUploadCount) : L.s.settings.unlimited)
                        Divider().overlay(Color.white.opacity(0.06))
                        row(L.s.settings.formats, t.allowedFormats.joined(separator: " · ").uppercased())
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    /// 目录监控自动上传。只增不删:本地删除不动云端,云端删除不回头删本地
    /// ——这是自动上传,不是同步,卡片文案也照这个口径写。
    private var watchCard: some View {
        SettingsCard(L.s.settings.watchFolders, "folder.badge.plus") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Toggle(isOn: Binding(
                        get: { model.watchEnabled },
                        set: { model.watchSetEnabled($0) }
                    )) { Text(L.s.settings.watchToggle).font(.callout) }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    Spacer()
                    if model.watchBusy { ProgressView().controlSize(.small) }
                }

                if let reason = model.watchPausedReason {
                    HStack(spacing: 8) {
                        Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
                        Text(L.s.settings.watchPaused(reason)).font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button(L.s.settings.resume) { model.watchResume() }
                            .buttonStyle(QuietButton())
                    }
                } else if !model.watchStatus.isEmpty {
                    Text(model.watchStatus).font(.caption).foregroundStyle(.tertiary)
                }
                if let issue = model.watchLastIssue {
                    Text(issue).font(.caption2).foregroundStyle(.orange)
                }

                ForEach(model.watchFolders, id: \.self) { path in
                    HStack(spacing: 8) {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text(path)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            model.watchRemoveFolder(path)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(L.s.settings.removeFolderHelp)
                    }
                    .padding(.vertical, 2)
                }

                HStack {
                    Button {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.prompt = L.s.settings.chooseFolderPrompt
                        if panel.runModal() == .OK, let url = panel.url {
                            model.watchAddFolder(url.path)
                        }
                    } label: {
                        Label(L.s.settings.addFolder, systemImage: "plus")
                    }
                    .buttonStyle(QuietButton())

                    if model.watchEnabled, !model.watchFolders.isEmpty,
                       model.watchPausedReason == nil {
                        Button(L.s.settings.scanNow) { model.watchScanFresh() }
                            .buttonStyle(QuietButton())
                            .disabled(model.watchBusy)
                    }
                    Spacer()
                }

                Text(L.s.settings.watchNote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// 外观。产品固定深色,可切的只有品牌色相——与网站 data-brand 同一套
    /// 取值,两端观感一致。
    /// 外观。产品固定深色,可切的只有界面语言与品牌色相——两者都与网站
    /// 同一套取值,两端观感一致。
    private var appearanceCard: some View {
        SettingsCard(L.s.settings.appearance, "paintpalette") {
            VStack(alignment: .leading, spacing: 14) {
                pickerRow(L.s.settings.language, L.s.settings.languageHint,
                          items: AppLang.allCases,
                          isOn: { $0 == model.lang },
                          tint: { _ in Color.brand },
                          select: { model.lang = $0 }) { lang in
                    Text(lang.label).font(.callout)
                }

                Divider().overlay(Color.white.opacity(0.06))

                pickerRow(L.s.settings.brandColor, L.s.settings.brandColorHint,
                          items: BrandTint.allCases,
                          isOn: { $0 == model.brandTint },
                          tint: { $0.accent },
                          select: { model.brandTint = $0 }) { tint in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(tint.accent)
                            .frame(width: 13, height: 13)
                            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.8))
                        Text(L.s.settings.tintName(tint)).font(.callout)
                    }
                }
            }
        }
    }

    /// 一行标题 + 一排互斥按钮。语言与品牌色是同一种控件,写两遍只会让它们
    /// 慢慢长歪。
    private func pickerRow<T: Hashable, C: View>(
        _ title: String, _ hint: String,
        items: [T],
        isOn: @escaping (T) -> Bool,
        tint: @escaping (T) -> Color,
        select: @escaping (T) -> Void,
        @ViewBuilder label: @escaping (T) -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.callout)
                Spacer()
                Text(hint).font(.caption2).foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    let on = isOn(item)
                    Button { select(item) } label: {
                        label(item)
                            .padding(.horizontal, 13)
                            .frame(height: Metrics.control)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(.white.opacity(on ? 0.12 : 0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(on ? tint(item).opacity(0.65) : .white.opacity(0.09),
                                                  lineWidth: on ? 1.4 : 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    /// 水印:本机合成后上传,不上服务器,所以是应用偏好而非账号偏好。
    /// 编辑器里按需开关;对监控目录可选自动应用。
    private var watermarkCard: some View {
        SettingsCard(L.s.settings.watermark, "signature") {
            VStack(alignment: .leading, spacing: 12) {
                Field(icon: "signature") {
                    TextField(L.s.settings.watermarkTextField, text: Binding(
                        get: { model.wmText },
                        set: { model.wmText = $0; model.saveWatermarkPrefs() }
                    ))
                }

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.s.settings.position).font(.caption).foregroundStyle(.secondary)
                        // 九宫格:所见即所得的位置选择,比下拉菜单直观。
                        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                            ForEach(0..<3, id: \.self) { row in
                                GridRow {
                                    ForEach(0..<3, id: \.self) { col in
                                        let a = row * 3 + col
                                        let name = Self.anchorNames[a]
                                        Button {
                                            model.wmAnchor = a
                                            model.saveWatermarkPrefs()
                                        } label: {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(model.wmAnchor == a
                                                      ? Color.brand : .white.opacity(0.12))
                                                .frame(width: 18, height: 14)
                                        }
                                        .buttonStyle(.plain)
                                        .help(name)
                                        .accessibilityLabel(L.s.settings.positionLabel(name))
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.s.settings.opacity(Int(model.wmOpacity * 100)))
                            .font(.caption).foregroundStyle(.secondary)
                        Slider(value: Binding(
                            get: { model.wmOpacity },
                            set: { model.wmOpacity = $0; model.saveWatermarkPrefs() }
                        ), in: 0.1...0.9)
                        .frame(width: 130)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.s.settings.size).font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: Binding(
                            get: { model.wmScale },
                            set: { model.wmScale = $0; model.saveWatermarkPrefs() }
                        )) {
                            Text(L.s.settings.sizeSmall).tag(0.02)
                            Text(L.s.settings.sizeMedium).tag(0.03)
                            Text(L.s.settings.sizeLarge).tag(0.045)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }
                }

                Toggle(L.s.settings.autoWatermarkWatch, isOn: Binding(
                    get: { model.wmAutoWatch },
                    set: { model.wmAutoWatch = $0; model.saveWatermarkPrefs() }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
                .disabled(model.watermarkSpec() == nil)

                Text(L.s.settings.watermarkNote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// 九宫格锚点的可读名,行优先与 WatermarkSpec.anchor 对齐。
    private static var anchorNames: [String] { L.s.settings.anchorNames }

    private func setting<C: View>(_ title: String, _ hint: String,
                                  @ViewBuilder control: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.callout)
                Spacer()
                Text(hint).font(.caption2).foregroundStyle(.tertiary)
            }
            control()
        }
    }

    private func pref<T>(_ b: Binding<T>) -> Binding<T> {
        Binding(get: { b.wrappedValue },
                set: { b.wrappedValue = $0; Task { await model.savePreferences() } })
    }

    private var widthPref: Binding<UploadView.Width> {
        Binding(get: { UploadView.Width(model.maxImageWidth) },
                set: { model.maxImageWidth = $0.px; Task { await model.savePreferences() } })
    }

    /// Password, passkeys and linked providers — the same set the website
    /// offers, minus linking.
    ///
    /// These used to be website-only on the grounds that a token must not reach
    /// account management. Checking what the handlers actually require showed
    /// that reasoning was aimed at the wrong thing: changing a password and
    /// enrolling a passkey are both gated on a code mailed to the account's own
    /// address, so the second factor was never the cookie. See router.go.
    ///
    /// Linking a provider is still missing, and for a real reason rather than a
    /// policy one: it is a full-page redirect carrying an intent cookie, and
    /// this app's web session is ephemeral, so the callback would have nothing
    /// to attach the link to.
    private var securityCard: some View {
        SettingsCard(L.s.settings.security, "lock.shield") {
            VStack(alignment: .leading, spacing: 16) {
                passwordSection
                Divider().overlay(Color.white.opacity(0.06))
                passkeySection
            }
        }
        .task(id: model.account?.id) { await model.loadPasskeys() }
    }

    @ViewBuilder
    private var passwordSection: some View {
        // 没有密码的账号(只用 OAuth/Passkey 注册)说"设置密码";旧服务器不
        // 返回该字段时按"修改"这个保守措辞走。
        let hasPassword = model.account?.hasPassword ?? true
        let tooShort = !newPassword.isEmpty && newPassword.count < 8
        let mismatch = !newPassword2.isEmpty && newPassword != newPassword2
        let ready = code.count == 6 && newPassword.count >= 8 && newPassword == newPassword2

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(hasPassword ? L.s.settings.changePassword : L.s.settings.setPassword)
                    .font(.callout)
                Spacer()
                Text(model.codeSent ? L.s.settings.codeValidHint : L.s.settings.codeWillSendHint)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if model.codeSent {
                if !model.codeSentTo.isEmpty {
                    Text(L.s.settings.codeSentTo(model.codeSentTo))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Field(icon: "number") {
                    TextField(L.s.settings.codeField, text: $code)
                }
                .frame(maxWidth: 240)
                Field(icon: "lock") {
                    SecureField(hasPassword
                                ? L.s.settings.newPasswordField : L.s.settings.passwordField,
                                text: $newPassword)
                }
                Field(icon: "lock.rotation") {
                    SecureField(L.s.settings.repeatPasswordField, text: $newPassword2)
                }
                if tooShort {
                    Text(L.s.settings.passwordTooShort).font(.caption2).foregroundStyle(.orange)
                } else if mismatch {
                    Text(L.s.settings.passwordMismatch).font(.caption2).foregroundStyle(.orange)
                }
                HStack(spacing: 8) {
                    Button(hasPassword ? L.s.settings.confirmChange : L.s.settings.confirmSet) {
                        Task {
                            if await model.changePassword(code: code, newPassword: newPassword) {
                                code = ""; newPassword = ""; newPassword2 = ""
                            }
                        }
                    }
                    .buttonStyle(BrandButton())
                    .disabled(!ready || model.busy)

                    Button(model.codeCooldown > 0
                           ? L.s.settings.resendIn(model.codeCooldown) : L.s.settings.resendCode) {
                        Task { await model.sendCode(.password) }
                    }
                    .buttonStyle(QuietButton())
                    .disabled(model.codeCooldown > 0 || model.busy)

                    Button(L.s.settings.cancel) {
                        model.codeSent = false; code = ""; newPassword = ""; newPassword2 = ""
                    }
                    .buttonStyle(LinkButton()).font(.caption)
                }
            } else {
                Button(hasPassword ? L.s.settings.changePassword : L.s.settings.setPassword) {
                    Task { await model.sendCode(.password) }
                }
                .buttonStyle(QuietButton())
                .disabled(model.busy)
            }
        }
    }

    @ViewBuilder
    private var passkeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Passkey").font(.callout)
                Spacer()
                Text(L.s.settings.passkeyHint)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if model.passkeys.isEmpty {
                Text(L.s.settings.noPasskeys).font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.passkeys) { p in
                        if p.id != model.passkeys.first?.id {
                            Divider().overlay(Color.white.opacity(0.06))
                        }
                        HStack(spacing: 10) {
                            Image(systemName: "person.badge.key")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.brand)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(.callout)
                                if let d = p.lastUsedAt {
                                    Text(L.s.settings.lastUsed(shortDate(d)))
                                        .font(.caption2).foregroundStyle(.tertiary)
                                } else if let d = p.createdAt {
                                    Text(L.s.settings.addedOn(shortDate(d)))
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Button(L.s.settings.delete) { Task { await model.deletePasskey(p) } }
                                .buttonStyle(LinkButton()).font(.caption2)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            if model.passkeyCodeSent {
                if !model.pkCodeSentTo.isEmpty {
                    Text(L.s.settings.codeSentTo(model.pkCodeSentTo))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Field(icon: "number") {
                    TextField(L.s.settings.codeField, text: $pkCode)
                }
                .frame(maxWidth: 240)
                Field(icon: "pencil") {
                    TextField(L.s.settings.passkeyNameField, text: $pkName)
                }
                HStack(spacing: 8) {
                    Button(L.s.settings.addPasskey) {
                        Task {
                            if await model.enrollPasskey(code: pkCode,
                                                         name: pkName.isEmpty ? "Mac" : pkName) {
                                pkCode = ""; pkName = ""
                            }
                        }
                    }
                    .buttonStyle(BrandButton())
                    .disabled(pkCode.count != 6 || model.busy)

                    Button(model.pkCodeCooldown > 0
                           ? L.s.settings.resendIn(model.pkCodeCooldown) : L.s.settings.resendCode) {
                        Task { await model.sendCode(.passkey) }
                    }
                    .buttonStyle(QuietButton())
                    .disabled(model.pkCodeCooldown > 0 || model.busy)

                    Button(L.s.settings.cancel) { model.passkeyCodeSent = false; pkCode = ""; pkName = "" }
                        .buttonStyle(LinkButton()).font(.caption)
                }
            } else {
                // 与改密码同一道二次因子:验证码先行,泄露的令牌不能给
                // 账号加登录后门。ad-hoc 构建里系统仪式会被拒,报错文案
                // 会解释并指去网站。
                Button(L.s.settings.addPasskey) { Task { await model.sendCode(.passkey) } }
                    .buttonStyle(QuietButton())
                    .disabled(model.busy)
            }
        }
    }

    /// Everything this app cannot do, in one place.
    ///
    /// These are the cookie-only routes — a token must not be able to change a
    /// password, mint more tokens, or read storage credentials, and that is a
    /// deliberate boundary rather than a gap. But it was previously expressed
    /// as one grey sentence in the corner of another card, which is the same as
    /// not saying it: a Mac user is exactly the person who needs an API token,
    /// and they had no way to find out where to get one.
    private var siteCard: some View {
        let links = Self.siteLinks
        return SettingsCard(L.s.settings.siteTitle, "safari") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(links, id: \.0) { title, detail, path in
                    if title != links.first?.0 {
                        Divider().overlay(Color.white.opacity(0.06))
                    }
                    Button {
                        if let u = URL(string: model.server + path) {
                            NSWorkspace.shared.open(u)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(title).font(.callout).foregroundStyle(.primary)
                                Text(detail).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private static var siteLinks: [(String, String, String)] {
        let s = L.s.settings
        return [
            (s.siteApiToken, s.siteApiTokenDetail, "/settings"),
            (s.siteLinkProviders, s.siteLinkProvidersDetail, "/settings"),
            (s.addPasskey, s.sitePasskeyDetail, "/settings"),
            (s.siteDeleteAccount, "", "/settings"),
        ]
    }

    private var dangerCard: some View {
        SettingsCard(L.s.settings.device, "laptopcomputer") {
            HStack(alignment: .top) {
                Text(L.s.settings.deviceNote)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button(L.s.settings.signOut) { model.signOut() }
                    .buttonStyle(DangerButton())
            }
            HStack {
                Spacer()
                Button(L.s.settings.openWebsite) {
                    if let u = URL(string: model.server) { NSWorkspace.shared.open(u) }
                }
                .buttonStyle(QuietButton())
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Bits

    /// 日期按界面语言格式化,而不是跟系统区域走——切成英文界面还印
    /// 「2026年8月17日」是两套语言混在一行里。
    private func shortDate(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(L.locale))
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v).multilineTextAlignment(.trailing)
        }
        .font(.callout)
        .padding(.vertical, 8)
    }

    private func tag(_ s: String) -> some View {
        Text(s)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.brand)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(Color.brand.opacity(0.16)))
    }
}

/// One card shape for the whole settings page, so sections stop each inventing
/// their own heading weight and padding.
struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    init(_ title: String, _ icon: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.icon = icon; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelSurface()
    }
}
