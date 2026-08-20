import SwiftUI
import AppKit
import OpenimgKit

struct SettingsView: View {
    @ObservedObject var model: AppModel
    /// nil means "showing whatever the server says". It only holds a value
    /// while the field is being edited, so the card never has to be told that
    /// the account changed underneath it.
    @State private var draftName: String?
    @State private var editingName = false
    @State private var nameHovering = false
    /// 失焦之后延迟一拍退回只读态的那个任务。见 scheduleNameRevert。
    @State private var nameRevert: Task<Void, Never>?
    /// 指针是不是正压在「保存」上。见 scheduleNameRevert 里的第二道闸。
    @State private var saveHovering = false
    /// 已经失焦、等着退回只读态。
    @State private var namePendingRevert = false
    /// 指针是不是正压在昵称输入框上。
    @State private var fieldHovering = false
    /// 编辑昵称期间装的鼠标按下监听。见 installNameClickMonitor。
    @State private var nameClickMonitor: Any?
    @State private var code = ""
    @State private var newPassword = ""
    @State private var pkExpanded = false
    @State private var pkCode = ""
    @State private var pkName = ""
    @State private var newPassword2 = ""
    /// 设置页里三个"要填一会儿"的表单统一走模态窗,见 FormSheet。
    @State private var sheet: SettingsSheet?
    @State private var avatarHover = false
    @State private var avatarDropping = false
    @FocusState private var nameFocused: Bool

    /// 卡片顺序按「多久改一次 × 归属谁」排,不是按堆得整齐排。
    ///
    /// 前四张是账号与这台机器(一年动几次),后四张是图片的一条链路:怎么处理
    /// → 加什么水印 → 从哪进来 → 存到哪儿。
    ///
    /// 原来是手分的两列(左五右四)。左列 938、右列 1213,差了 275——而且两张
    /// 最高的卡(图片处理、水印)都在右列且一个叠一个,右列因此单方面超长。把
    /// 它们排进同一行,失衡就消失了。
    private enum CardID: String, Hashable, Sendable {
        case profile, linked, security, appearance
        case conversion, watermark, watch, location
    }

    private var cards: [BoardCard<CardID>] {
        [
            BoardCard(.profile),
            BoardCard(.linked),
            BoardCard(.security),
            BoardCard(.appearance),
            // 这两张最高。放同一行,谁也不再单方面把一列拉长。
            BoardCard(.conversion),
            BoardCard(.watermark),
            BoardCard(.watch),
            // 每行六段(名字/徽章/类型/字节/张数/菜单),横着铺最省高度。
            BoardCard(.location, spans: [3: 3]),
        ]
    }

    var body: some View {
        CardBoard(cards: cards) { id in
            switch id {
            case .profile:    profileCard
            case .linked:     linkedAccountsCard
            case .security:   securityCard
            case .appearance: appearanceCard
            case .conversion: conversionCard
            case .watermark:  watermarkCard
            case .watch:      watchCard
            case .location:   locationCard
            }
        }
        // 点空白处退出昵称编辑,靠的是 installNameClickMonitor,不是在这里挂
        // 一个 onTapGesture。
        //
        // 挂祖先手势有个绕不开的顺序问题:点昵称那一下,昵称自己的手势要把
        // editingName 置真,而祖先的手势看到"正在编辑"就会把它撤销——两者谁
        // 先谁后不是由这段代码决定的。要挡住就得比时间戳,而那种代码没人看得
        // 懂它在防什么。
        //
        // 监听没有这个问题:它只在编辑期间装,而进入编辑的那一次 mouseDown 在
        // 装之前就派发完了,它根本看不到。
        .onChange(of: editingName) { _, on in
            if on { installNameClickMonitor() } else { removeNameClickMonitor() }
        }
        .onDisappear { removeNameClickMonitor() }
        .task(id: model.account?.id) { await model.loadStats() }
        .sheet(item: $sheet) { which in
            switch which {
            case .password:
                PasswordSheet(model: model) { sheet = nil }
            case .storage(let profile):
                StorageProfileForm(model: model, editing: profile) { sheet = nil }
            }
        }
    }

    // MARK: - Cards

    /// Editable, where it used to be a read-only block.
    ///
    /// It was read-only because the nickname and avatar routes were in the
    /// cookie-only group and this client holds a token, so every write would
    /// have 401'd. They now sit alongside the other things a token may do to
    /// its own account — see the note in router.go for where that line is.
    private var profileCard: some View {
        PanelCard(L.s.settings.profile, "person.crop.circle") {
            if let a = model.account {
                HStack(alignment: .top, spacing: 14) {
                    avatarWell(a)

                    VStack(alignment: .leading, spacing: 6) {
                        // 徽章贴着昵称,不另起一行。
                        //
                        // 角色是这个人的属性,挨着名字才读得顺;而单独占一行会
                        // 把「名字 + 邮箱」这一组从中间劈开——那两行本来是同
                        // 一件事(这是谁)。昵称框封顶 260pt,右边本来就空着。
                        HStack(spacing: 8) {
                            nameField(a)
                            tag(a.role)
                            // Role and tier are separate fields that happen to
                            // carry the same word for admins; printing both
                            // gives "admin admin".
                            if let t = model.quota?.tier, t.name != a.role { tag(t.name) }
                            Spacer(minLength: 0)
                        }
                        Text(a.email)
                            .font(.callout).foregroundStyle(.secondary)
                            .padding(.leading, 8)   // 对齐到昵称框的文字起点
                    }
                    Spacer(minLength: 0)
                }

                Divider().overlay(Color.white.opacity(0.06))
                LevelRow(model: model)
            }
        }
    }

    /// 头像本体就是入口:点击选图、悬浮显相机、把图片拖上来直接换。
    ///
    /// 底下原来还有一行「更换 · 移除」的文字链接。去掉了:「更换」和点头像
    /// 本身是同一件事,同一个动作摆两个入口,读者会以为它们不一样;而「移除」
    /// 这条路整个不再提供——头像是可以覆盖的,没有必要专门给"变回没有头像"
    /// 留一个按钮。
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
                    if let url = await DroppedFiles.firstURL(from: providers) {
                        await model.setAvatar(url)
                    }
                }
                return true
            }
            .disabled(model.busy)
        }
    }

    /// 平时是一行字,点一下才变成输入框,旁边随之出现「保存」。
    ///
    /// 原来是常驻输入框、失焦即存。改掉是因为那个设计有两处说不通:一是它平
    /// 时长得就像可编辑的,而这张卡里别的东西都不是,读起来像是有个输入框漏
    /// 了标签;二是失焦即存意味着点一下别处就把改动写进去了,而用户可能只是
    /// 点开了旁边的菜单又退回来。
    ///
    /// 点到别处就退回只读态,草稿丢掉。保存只由「保存」按钮和回车发生——
    /// 失焦自动保存会把那颗按钮变成摆设,而用户可能只是点开了旁边的菜单。
    ///
    /// 这里原来是"失焦既不保存也不丢弃,留在编辑态,想放弃按 Esc"。想法是别
    /// 吃掉刚打的字,但代价是**没改过就出不来**:点开一看不想改了,唯一的出路
    /// 是按 Esc,而没人知道要按 Esc。一个进得去出不来的状态,比丢掉一个昵称的
    /// 代价大得多——何况昵称就那么几个字,重打一遍不算什么。
    private func nameField(_ a: Account) -> some View {
        HStack(spacing: 8) {
            if editingName {
                TextField(L.s.settings.nickname, text: Binding(
                    get: { draftName ?? a.name },
                    set: { draftName = $0 }
                ))
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                    )
                    .frame(maxWidth: 260)
                    .onHover { fieldHovering = $0 }
                    .onSubmit { commitName() }
                    .onExitCommand { cancelName() }
                    .focused($nameFocused)
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { scheduleNameRevert() }
                    }

                Button(L.s.common.save) { commitName() }
                    .buttonStyle(BrandButton())
                    .controlSize(.small)
                    .onHover { hovering in
                        saveHovering = hovering
                        // 指针离开时补做一次:焦点丢的那一刻指针要是正好停在
                        // 这颗按钮上,那次撤销会被第二道闸挡掉,不补的话就又
                        // 卡回"出不来"的状态了。
                        if !hovering { tryNameRevert() }
                    }
                    // 名字没动就不给按:一次什么都不改的写请求,除了让头像和
                    // 昵称闪一下重新加载之外没有任何作用。
                    .disabled((draftName ?? a.name) == a.name)
            } else {
                Text(a.name.isEmpty ? L.s.settings.nickname : a.name)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(a.name.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.white.opacity(nameHovering ? 0.06 : 0))
                    )
                    // 悬浮才露出的铅笔。常驻的话这行字就永远带着一个图标,
                    // 而它 99% 的时间只是在显示名字。
                    .overlay(alignment: .trailing) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .opacity(nameHovering ? 1 : 0)
                            .offset(x: 16)
                    }
                    .contentShape(Rectangle())
                    .onHover { nameHovering = $0 }
                    .onTapGesture {
                        namePendingRevert = false
                        editingName = true
                        // 下一拍再要焦点:这一拍 TextField 还没进视图树。
                        DispatchQueue.main.async { nameFocused = true }
                    }
                    .help(L.s.settings.nicknameEditHint)
            }
        }
        .animation(.easeOut(duration: 0.12), value: editingName)
        .animation(.easeOut(duration: 0.12), value: nameHovering)
    }

    /// 失焦之后退回只读态。**延迟一拍**是必须的。
    ///
    /// 点「保存」这个动作本身会先让输入框失焦:mouseDown 时焦点就走了,而按钮
    /// 的 action 要到 mouseUp 才触发,中间隔着一段真实的时间。立刻退的话按钮
    /// 在自己的 action 跑起来之前就已经从视图树里消失了——那颗按钮会变成永远
    /// 点不动,而这种"点了没反应"最难查。
    ///
    /// 两道闸,因为任何一道单独都不够:
    ///
    ///   - **延时**挡得住一次正常的点击(mouseDown 到 mouseUp 通常不到 150ms),
    ///     但挡不住按住不放——按 300ms 再松手,撤销已经先跑完了。
    ///   - **悬浮**挡得住按住不放,但指针刚落到按钮上那一瞬 onHover 未必已经
    ///     更新,单靠它会漏掉最快的那种点击。
    ///
    /// 键盘那条路不受影响:回车走 onSubmit,直接提交,根本不经过这里。
    private func scheduleNameRevert() {
        guard editingName else { return }
        namePendingRevert = true
        nameRevert?.cancel()
        nameRevert = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            tryNameRevert()
        }
    }

    /// 条件都满足就退回只读态。三个入口调它:延时到点、指针离开「保存」、
    /// 以及鼠标监听。
    ///
    /// **不能拿 `nameFocused` 当条件**——这正是第一版没生效的原因:点一块没
    /// 有响应者的空白区域时,TextField 仍然是第一响应者,焦点根本没走。改用
    /// "指针不在输入框、也不在保存按钮上"来判断。
    private func tryNameRevert() {
        guard namePendingRevert, editingName, !saveHovering, !fieldHovering else { return }
        cancelName()
    }

    /// 编辑期间监听 app 内的鼠标按下。
    ///
    /// 这是第二条路,和上面那个 `.onTapGesture` 各走各的:手势依赖 SwiftUI 把
    /// 点击沿祖先链冒上来,而卡片里嵌了滚动视图、图表、各种自绘背景,哪一层
    /// 会不会把事件吃掉不是看一眼就能确定的事。监听走的是 AppKit 那一层,不
    /// 受这些影响。两条都只是调同一个幂等的函数,同时触发也无所谓。
    ///
    /// 监听里**不直接撤销**,仍然走那个带延时的 schedule:监听在 mouseDown 就
    /// 触发,比按钮的 action(mouseUp)更早,直接撤销会让「保存」在自己跑起来
    /// 之前就消失。
    private func installNameClickMonitor() {
        guard nameClickMonitor == nil else { return }
        nameClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { event in
            if !fieldHovering && !saveHovering { scheduleNameRevert() }
            return event        // 只看,不吞
        }
    }

    private func removeNameClickMonitor() {
        if let m = nameClickMonitor { NSEvent.removeMonitor(m) }
        nameClickMonitor = nil
    }

    private func cancelName() {
        removeNameClickMonitor()
        nameRevert?.cancel(); nameRevert = nil
        namePendingRevert = false
        draftName = nil
        editingName = false
        nameFocused = false
    }

    private func commitName() {
        removeNameClickMonitor()
        nameRevert?.cancel(); nameRevert = nil
        namePendingRevert = false
        defer { editingName = false; nameFocused = false }
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
        PanelCard(L.s.settings.location, "externaldrive.connected.to.line.below") {
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

                HStack(spacing: 8) {
                    Button {
                        model.storageCodeSent = false
                        sheet = .storage(nil)
                    } label: {
                        Label(L.s.settings.storageAdd, systemImage: "plus")
                    }
                    .buttonStyle(QuietButton())
                    .disabled(model.busy)
                    Spacer()
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
                } else if let k = kindLabel(p), k != p.name {
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
                        sheet = .storage(p)
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

    /// 后端发的是 platform / user_r2 / user_s3,不是 s3 / r2。
    ///
    /// 原来只认后两个,于是绑了 R2 的用户在这里看到的是原样打印的 `user_r2`
    /// ——default 分支把没认出来的值直接显示出去了,不报错也不留痕。
    ///
    /// 非 R2 的自有桶后端一律记成 user_s3(B2、Spaces、OSS、COS 都在里面),
    /// 所以再用 endpoint 细分一次,这样界面说的才是用户实际在用的那家。
    private func kindLabel(_ p: StorageProfile) -> String? {
        switch p.kind {
        case "platform": L.s.settings.kindPlatform
        case "user_r2": L.s.settings.kindOwnBucket("R2")
        case "user_s3": L.s.settings.kindOwnBucket(vendorName(p.endpoint))
        // 位置删了但图还在时后端回 "unknown"。
        case "unknown", "": nil
        default: p.kind
        }
    }

    private func vendorName(_ endpoint: String) -> String {
        switch StorageProfileInput.describeEndpoint(endpoint) {
        case .r2: "R2"
        case .b2: "B2"
        case .spaces: "Spaces"
        case .oss: "OSS"
        case .cos: "COS"
        case .s3, .custom, .none: "S3"
        }
    }

    /// The same three values the upload page offers. Both write to the account,
    /// so whichever one the user reaches for, the website agrees.
    private var conversionCard: some View {
        PanelCard(L.s.settings.processing, "wand.and.stars") {
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
                // 上面三项写账号偏好,这一项只写本机——剥离在这台 Mac 上发生,
                // 服务器执行不了。原图模式下照样生效:那个模式承诺的是不重新
                // 编码,不是"连定位一起原样发到公网上"。
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $model.stripMetadata) {
                        Text(L.s.settings.stripMetadata).font(.callout)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    Text(L.s.settings.stripMetadataHint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
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
        PanelCard(L.s.settings.watchFolders, "folder.badge.plus") {
            InfoTip(text: L.s.settings.watchNote, title: L.s.settings.watchFolders)
        } content: {
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

            }
        }
    }

    /// 应用与设备。
    ///
    /// 原来是两张卡:「外观」(两个选择器)和「这台设备」(两颗按钮)。合并的
    /// 理由不是凑高度——是两张各自都不够一张卡的分量,合起来四个控件才够。
    /// 它们说的也是同一件事:这台机器上的 Openimg 是什么样、以及怎么离开它。
    private var appearanceCard: some View {
        PanelCard(L.s.settings.appAndDevice, "laptopcomputer") {
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

                Divider().overlay(Color.white.opacity(0.06))

                // 版本号。
                //
                // 在这之前 app 里没有任何地方显示自己的版本——用户想说"我这版
                // 有个问题"的时候只能去看文件信息,而那还得先找到 .app 在哪。
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(L.s.settings.appVersion).font(.callout)
                        Spacer()
                        Text(AppVersion.display)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    UpdateRow(checker: model.updates)
                }

                Divider().overlay(Color.white.opacity(0.06))

                VStack(alignment: .leading, spacing: 10) {
                    Text(L.s.settings.deviceNote)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button(L.s.settings.signOut) { model.signOut() }
                            .buttonStyle(DangerButton())
                        Button(L.s.settings.openWebsite) {
                            if let u = URL(string: model.server) { NSWorkspace.shared.open(u) }
                        }
                        .buttonStyle(QuietButton())
                        Spacer(minLength: 0)
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
        PanelCard(L.s.settings.watermark, "signature") {
            // 三段说明合成一处。它们都是"知道了有用、但不影响当下操作"的背景
            // 知识,常驻在卡里会占掉整张卡近一半高度。
            InfoTip(text: [L.s.settings.wmGenNote,
                           L.s.settings.wmImageNote,
                           L.s.settings.watermarkNote].joined(separator: "\n\n"),
                    title: L.s.settings.watermark)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                // 模式在最前面:后面每一栏的含义都随它变(输入框还是图片、
                // 字号还是 logo 宽度),放在下面会让人先填完再发现填错了地方。
                Picker("", selection: Binding(
                    get: { model.wmKind },
                    set: { model.wmKind = $0; model.saveWatermarkPrefs() }
                )) {
                    Text(L.s.settings.wmModeText).tag(WatermarkKind.text)
                    Text(L.s.settings.wmModeImage).tag(WatermarkKind.image)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // 高度跟 Metrics.control 走,和同屏的输入框、按钮对齐。分段
                // 用 controlSize 而不是 frame:frame 对 NSSegmentedControl 只是
                // 把它居中放进一个更高的盒子里,画出来还是原来那么高。large
                // 这一档正好落在 Metrics.control 附近。
                .controlSize(.large)
                .frame(width: 180)
                .accessibilityLabel(L.s.settings.wmMode)

                if model.wmKind == .text {
                    Field(icon: "signature") {
                        TextField(L.s.settings.watermarkTextField, text: Binding(
                            get: { model.wmText },
                            set: { model.wmText = $0; model.saveWatermarkPrefs() }
                        ))
                    }
                } else {
                    watermarkImageSection
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

                    // 两种模式的大小控件不是同一个:文字模式的"小/中/大"三档
                    // 够用(字号合不合适只取决于读不读得清),而 logo 的合适
                    // 尺寸随它自己的形状变——一枚细长的横条和一个方形图标在
                    // 同一个比例下观感差很远,得给连续的数。
                    if model.wmKind == .text {
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
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L.s.settings.wmImageSize(Int(model.wmImageScale * 100)))
                                .font(.caption).foregroundStyle(.secondary)
                            // 区间取自 Kit,不在这里写死:渲染那边会按同一个
                            // 区间夹,两处各写一份的表现是"拖到底了还是没变大"。
                            Slider(value: Binding(
                                get: { model.wmImageScale },
                                set: { model.wmImageScale = $0; model.saveWatermarkPrefs() }
                            ), in: WatermarkKind.image.scaleRange)
                            .frame(width: 130)
                        }
                    }
                }

                Toggle(L.s.settings.autoWatermarkWatch, isOn: Binding(
                    get: { model.wmAutoWatch },
                    set: { model.wmAutoWatch = $0; model.saveWatermarkPrefs() }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
                .disabled(model.watermarkSpec() == nil)
            }
        }
    }

    /// 图片模式那一段:当前的 logo、换/删、去背景、以及让 AI 画一枚。
    @ViewBuilder
    private var watermarkImageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                // 棋盘格垫底:一张透明底的 logo 放在纯色上看不出透明,而"这张
                // 图到底有没有透明背景"正是这一页要帮用户回答的问题。
                ZStack {
                    Checkerboard()
                    if let img = model.wmImagePreview {
                        Image(nsImage: img).resizable().scaledToFit().padding(4)
                    } else {
                        Image(systemName: "photo").foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 64, height: 64)
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke(.white.opacity(0.12), lineWidth: 1))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        // 统一样式而不是留系统默认:同一张卡片里已经有 Pill、
                        // BrandButton 与 Field 三种高度,再混进一个系统按钮
                        // (随 macOS 版本变)就凑不齐任何一条基准线了。
                        Button(model.wmImagePNG == nil
                               ? L.s.settings.wmChooseImage : L.s.settings.wmReplaceImage) {
                            model.wmChooseImage()
                        }
                        .buttonStyle(QuietButton())
                        if model.wmImagePNG != nil {
                            Button(L.s.settings.wmClearImage) { model.wmClearImage() }
                                .buttonStyle(QuietButton())
                        }
                    }
                    if model.wmImagePNG == nil {
                        Text(L.s.settings.wmNoImage)
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    // 不透明的图不拦下来,只在旁边多一个按钮:一枚白底 logo
                    // 抠一下就能用,拦住等于让用户自己去找修图软件。
                    if model.wmNeedsCutout {
                        Text(L.s.settings.wmOpaqueNote)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(L.s.settings.wmCutout) {
                            Task { await model.wmRemoveBackground() }
                        }
                        .disabled(model.wmBusy)
                    }
                }
            }

            if model.aiEnabled {
                Divider().opacity(0.3)
                Text(L.s.settings.wmGenTitle).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Field(icon: "sparkles") {
                        TextField(L.s.settings.wmGenPrompt, text: $model.wmPrompt)
                            .onSubmit { Task { await model.wmGenerate() } }
                    }
                    Button(L.s.settings.wmGenButton) {
                        Task { await model.wmGenerate() }
                    }
                    // 并排在 Field 旁边,高度跟 Metrics.field 走而不是 control
                    // ——同一行里差六个点,一眼就看得出没对齐。
                    .buttonStyle(BrandButton())
                    .frame(height: Metrics.field)
                    .disabled(!model.wmCanGenerate)
                }
                // 在途时说清楚"还在跑",否则按钮变灰看起来像是坏了。
                if !model.wmGenID.isEmpty || model.wmBusy {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(L.s.settings.wmGenPending)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
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
        PanelCard(L.s.settings.security, "lock.shield") {
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
        let hasPassword = model.account?.hasPassword ?? true
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(hasPassword ? L.s.settings.changePassword : L.s.settings.setPassword)
                    .font(.callout)
                Spacer()
                Text(L.s.settings.codeWillSendHint).font(.caption2).foregroundStyle(.tertiary)
            }
            Button(hasPassword ? L.s.settings.changePassword : L.s.settings.setPassword) {
                sheet = .password
            }
            .buttonStyle(QuietButton())
            .disabled(model.busy)
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

                    Button(L.s.settings.cancel) {
                        model.passkeyCodeSent = false; pkCode = ""; pkName = ""; pkExpanded = false
                    }
                        .buttonStyle(LinkButton()).font(.caption)
                }
            } else if pkExpanded {
                // 展开了但还没发信:发不发由人按。
                Text(L.s.settings.codeWillSendHint)
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button(model.pkCodeCooldown > 0
                           ? L.s.settings.resendIn(model.pkCodeCooldown) : L.s.settings.sendCode) {
                        Task { await model.sendCode(.passkey) }
                    }
                    .buttonStyle(BrandButton())
                    .disabled(model.pkCodeCooldown > 0 || model.busy)

                    Button(L.s.settings.cancel) { pkExpanded = false }
                        .buttonStyle(LinkButton()).font(.caption)
                }
            } else {
                // 与改密码同一道二次因子:验证码先行,泄露的令牌不能给
                // 账号加登录后门。ad-hoc 构建里系统仪式会被拒,报错文案
                // 会解释并指去网站。
                //
                // 点它只展开表单,不发信。原来是直接发——于是误点一次就烧掉
                // 一封受频率限制的邮件,而用户此刻可能只是想看看这里有什么。
                Button(L.s.settings.addPasskey) { pkExpanded = true }
                    .buttonStyle(QuietButton())
                    .disabled(model.busy)
            }
        }
    }

    /// pic.bi 关联。
    ///
    /// 自成一张卡片,而不是塞进「登录与安全」:关联打通的是额度,不是登录
    /// 方式——pic.bi 没有登录按钮,也不该被读成有。
    ///
    /// 关联**和解绑**都在网站上完成。
    ///
    /// 两条路(`/auth/picbi/link-start` 与 `/auth/picbi/unlink`)都挂在 cookie
    /// 会话那一组,而这个客户端拿的是令牌,`ASWebAuthenticationSession` 又是
    /// ephemeral 的(见 OAuthSignIn 里那条注释),都走不通。
    ///
    /// 这一条曾经写成"解绑是纯 API,令牌能调",按那个前提做出来的按钮点下去
    /// 只会拿到 401,而界面把它翻成「令牌无效」——令牌其实好好的,是敲错了门。
    /// 这类误导性报错比功能缺失更费时间,所以宁可两条都领到网页去。
    ///
    /// 为什么不把 unlink 放进令牌组:它动的是钱那一侧的关联,而 API 令牌常年
    /// 有效、会被粘进第三方客户端,不该碰这件事。
    private var linkedAccountsCard: some View {
        let linked = model.account?.picbiConnected ?? false
        return PanelCard(L.s.settings.linkedAccounts, "link") {
            VStack(alignment: .leading, spacing: 10) {
                Text(L.s.settings.linkedAccountsHint)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.brand)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("pic.bi").font(.callout)
                            if linked { tag(L.s.settings.picbiLinked) }
                        }
                        Text(linked ? L.s.settings.picbiLinkedNote : L.s.settings.picbiNote)
                            .font(.caption2).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if linked {
                        Button(L.s.settings.picbiUnlink) { openLinkPage() }
                            .buttonStyle(LinkButton()).font(.caption2)
                    } else {
                        Button(L.s.settings.picbiLink) { openLinkPage() }
                            .buttonStyle(QuietButton())
                    }
                }

                if !linked {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(L.s.settings.picbiLinkHint)
                            .font(.caption2).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button(L.s.settings.picbiRefresh) {
                            Task { await model.refreshAccountLinks() }
                        }
                        .buttonStyle(LinkButton()).font(.caption2)
                    }
                }
            }
        }
        .disabled(model.busy)
    }

    /// 设置页而不是 link-start 本身:后者是 cookie-only 的,浏览器里没有会话
    /// 时回的是一段 401 JSON,而不是登录页。
    private func openLinkPage() {
        if let u = URL(string: model.server + "/settings") { NSWorkspace.shared.open(u) }
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
        // 首字母大写只在显示这一层做,不动服务端的取值。role/tier 在接口里是
        // 小写标识("admin"/"user"/"free"),拿它当界面文案直接印出来才显得像
        // 调试输出。中文之类没有大小写的语言,capitalized 原样返回。
        Text(s.prefix(1).uppercased() + s.dropFirst())
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.brand)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(Color.brand.opacity(0.16)))
    }
}


/// 透明度垫底的棋盘格。
///
/// 画出来而不是贴一张图片资源:这个 App 是纯代码构建的 SPM 目标,加一份图片
/// 资源要连带一个 Bundle.module 的取用路径,而这里只需要两种颜色的方格。
private struct Checkerboard: View {
    var cell: Double = 8

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.10)))
            let cols = Int((size.width / cell).rounded(.up))
            let rows = Int((size.height / cell).rounded(.up))
            for r in 0..<max(rows, 1) {
                for c in 0..<max(cols, 1) where (r + c) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: Double(c) * cell, y: Double(r) * cell,
                                         width: cell, height: cell)),
                             with: .color(.black.opacity(0.18)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
