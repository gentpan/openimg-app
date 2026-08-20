import Foundation
import AppKit
import AuthenticationServices
import SwiftUI
import OpenimgKit

/// Trailing underscore because `Section` is a SwiftUI type and shadowing it
/// makes every `Section { }` in a List fail to resolve.
enum Section_: String, CaseIterable, Identifiable, Hashable {
    /// 「修图」紧挨着「生成」:两件事同一套额度、同一条轮询、同一个上游模型,
    /// 区别只在于有没有原图。中间隔着别的分区会让它们看起来毫不相干。
    case overview, gallery, upload, generate, retouch, editor, settings
    var id: String { rawValue }
    /// 显示名归 nav 分区管——侧栏、顶栏、这里都取同一份,不各写各的。
    var label: String { L.s.nav.section(self) }
    var icon: String {
        switch self {
        case .overview: "chart.bar.doc.horizontal"
        case .gallery: "square.grid.2x2"
        case .upload: "arrow.up.circle"
        case .generate: "sparkles"
        case .retouch: "wand.and.stars"
        case .editor: "crop"
        case .settings: "gearshape"
        }
    }

    /// The filled counterpart, used for the selected row. Swapping between the
    /// two is what `.symbolEffect(.replace)` animates — an outline morphing
    /// into a solid reads as "this one is on" without any extra chrome.
    var iconFilled: String {
        switch self {
        case .overview: "chart.bar.doc.horizontal.fill"
        case .gallery: "square.grid.2x2.fill"
        case .upload: "arrow.up.circle.fill"
        case .generate: "sparkles.rectangle.stack"
        case .retouch: "wand.and.stars.inverse"
        case .editor: "crop.rotate"
        case .settings: "gearshape.fill"
        }
    }

    /// 这一行要不要 AI 才存在。见 AppModel.visibleSections——没配 key 的
    /// 部署里这两行整个不出现。
    var needsAI: Bool { self == .generate || self == .retouch }
}

/// State for the whole app.
///
/// `@MainActor` on the type rather than on individual members: every property
/// here drives a view, and an actor boundary in the middle of that only buys
/// the ability to mutate UI state off the main thread, which is never wanted.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // Connection
    /// 默认指向官方实例,但可以改——后端是 MIT 开源、可自建的,把地址写死
    /// 等于告诉自建者"这个 App 不是给你的"。Kit 本来就收 URL 参数(它是个
    /// 库,写死主机没法测),这里只是把那个能力接到界面上。
    ///
    /// 登录页默认不显示地址栏:给普通用户一个输入框,只会招来一个填错的地址。
    /// 要用自建实例的人会去展开那一行。
    static let officialServer = "https://openimg.io"
    @Published var server = UserDefaults.standard.string(forKey: "server") ?? officialServer
    @Published var token = ""
    @Published var email = UserDefaults.standard.string(forKey: "email") ?? ""
    @Published var password = ""
    /// 登录页停在注册那一档。不落盘:它是当次的意图,不是偏好。
    @Published var registering = false
    /// 注册用的昵称与邮箱验证码。
    @Published var regName = ""
    @Published var regCode = ""
    /// 验证码重发倒计时。0 表示可以发。
    @Published var regCooldown = 0
    @Published var regCodeSent = false
    @Published var account: Account?
    @Published var quota: Quota?
    /// 按天的上传趋势。来自服务端,不是拿图库当前页聚合的。
    @Published var uploadTrend: UploadTrend?
    /// 取趋势失败的原因。
    ///
    /// 留着而不是丢掉:原来失败就整张卡消失,而"卡片不见了"和"这段时间没上传"
    /// 在界面上长得一模一样——一个不报错的失败模式,查起来极贵。宁可把话说出来。
    @Published var uploadTrendError: String?

    /// 更新检查。独立的对象而不是一堆 @Published 散在这里:它有自己的状态机,
    /// 而且和账号、图库完全无关——没登录也该能查更新。
    let updates = UpdateChecker()

    // 外观:界面语言。改它要重建整个视图树——文案取自 L.s 这个静态量,
    // 而非每个视图观察的属性,单靠 objectWillChange 只会刷新恰好在读
    // model 的那些视图。langEpoch 挂在根视图的 .id 上,变一次整树重建。
    @Published var lang: AppLang = AppLang.current {
        didSet {
            AppLang.current = lang
            UserDefaults.standard.set(lang.rawValue, forKey: "appLang")
            langEpoch &+= 1
        }
    }
    @Published var langEpoch = 0

    // 外观:品牌色相(与网站 data-brand 同一套)
    @Published var brandTint: BrandTint = BrandTint.current {
        didSet {
            BrandTint.current = brandTint
            UserDefaults.standard.set(brandTint.rawValue, forKey: "brandTint")
            brandTint.applyAppIcon()
        }
    }

    // Navigation
    @Published var section: Section_ = .gallery {
        didSet {
            // 换页就关掉选图面板。它记着"这些图往哪个篮子放",留着的话:在
            // 生成页开了面板、切到修图页、面板带着 generate 这个身份重新弹
            // 出来,选的图会落进上一页的篮子里——而用户看着的是这一页。
            if oldValue != section, aiPicking != nil { aiPicking = nil }
        }
    }
    @Published var status = ""
    @Published var busy = false

    // Gallery
    @Published var images: [RemoteImage] = []
    @Published var total = 0
    @Published var page = 0
    // 50 rather than 25: the grid sizes itself to fit whatever this is, and a
    // page of 25 in a default window means tiles big enough to look like a
    // mistake. See GridFit.
    @Published var pageSize = 50
    @Published var search = ""
    @Published var sort: SortKey = .newest
    @Published var selection: Set<String> = []
    @Published var detail: RemoteImage?
    @Published var linkFormat: LinkFormat = .url

    // 目录监控自动上传(实现在 FolderWatch.swift;存储属性必须declare在类体里)
    @Published var watchFolders: [String] = UserDefaults.standard.stringArray(forKey: "watchFolders") ?? []
    @Published var watchEnabled = UserDefaults.standard.bool(forKey: "watchEnabled")
    @Published var watchStatus = ""
    /// 非 nil 即已暂停(配额耗尽/每日上限/令牌失效);每日上限次日自动恢复,
    /// 其余等用户处理后手动继续。
    @Published var watchPausedReason: String?
    /// 最近一轮里被组规则拒绝的原因,给设置卡一行解释,免得「跳过 N」成谜。
    @Published var watchLastIssue: String?
    @Published var watchBusy = false
    var watchStream: FolderEventStream?
    var watchManifest = WatchManifest()
    /// 记录清单从哪个 URL 加载——清单按 服务器+账号 键控,URL 变了就该换。
    var watchManifestLoadedFrom: URL?
    /// 扫描进行中又来了扫描请求:记账,收尾补扫,不静默丢弃。
    var watchScanAgain = false
    /// 本会话失败过的路径。不进清单(下次启动还会重试),只防同一会话热循环;
    /// 「立即扫描」与恢复暂停会清空它。
    var watchSkip: Set<String> = []
    var watchRescan: Task<Void, Never>?

    // 图库导出(实现在 Exporter.swift)
    @Published var export: ExportProgress?
    var exportCancelled = false

    // AI 文生图(实现在 GenerateModel.swift;存储属性必须declare在类体里)。
    // aiStatus 为 nil 或 enabled 为假时,侧栏根本不显示这一页——见
    // visibleSections。
    @Published var aiStatus: AIStatus?
    @Published var aiPrompt = ""
    /// 尺寸与清晰度的可选值由服务器给,这两个只是当前选择;状态到手后会
    /// 校正到列表里的合法值。
    @Published var aiSize = "1:1"
    @Published var aiResolution = "1k"
    @Published var aiGenerations: [AIGeneration] = []
    /// 已完成记录对应的图片,按 image_id 索引,与图库那份同构。
    @Published var aiImages: [String: RemoteImage] = [:]
    @Published var aiSubmitting = false
    @Published var aiLoading = false
    /// 轮询任务。页面消失就取消——没人看着的时候没有理由每三秒问一次。
    var aiPollTask: Task<Void, Never>?
    // AI 修图(实现在 RetouchModel.swift)。与生成共用额度、历史与轮询。
    @Published var retouchPrompt = ""
    /// 空串表示「跟随原图」——那时请求里整个不带这个键,上游按原图尺寸出图。
    @Published var retouchSize = ""
    @Published var retouchResolution = ""
    @Published var retouchSubmitting = false

    // 给 AI 的那几张图(实现在 AISources.swift)。修图页叫「原图」、生成页叫
    // 「参考图」,是同一件事:1~4 张**图库里**的图,提交时只发 id。存整个对象
    // 而不是 id,是因为缩略图要立刻画出来,而图库翻页后 `images` 里就没有它了。
    @Published var retouchSources: [RemoteImage] = []
    @Published var generateSources: [RemoteImage] = []
    /// 选图面板开给了哪一页;nil 就是没开。做成可选值而不是布尔,是因为两页
    /// 共用同一个面板,面板得知道自己在往哪个篮子里放图。
    @Published var aiPicking: AISourceSlot?
    /// 面板自己那份图库快照。不复用 `images`:那是图库页当前停在的一页,借来
    /// 搜索会把用户翻到一半的位置冲掉。一次只开一个面板,所以只有一份。
    @Published var aiLibrary: [RemoteImage] = []
    @Published var aiLibrarySearch = ""
    @Published var aiLibraryLoading = false
    /// 选图面板还有没有下一页。翻到底就置假,免得空转。
    @Published var aiLibraryMore = true
    /// 从那一行直接传图的忙态。与 `uploading` 分开:上传页的队列是另一回事,
    /// 而这一行要在原地转圈并挡住重复点击。
    @Published var aiSourceUploading = false

    // 上传前编辑(实现在 EditorSheet.swift)
    @Published var editTarget: EditTarget?
    @Published var editOnDrop = UserDefaults.standard.bool(forKey: "editOnDrop")

    /// 上次启动时 AI 是开着的吗。用来在状态拉回来之前先把侧栏画对,
    /// 理由见 `aiEnabled`。
    @Published var aiEnabledRemembered = UserDefaults.standard.bool(forKey: "aiEnabled") {
        didSet {
            guard oldValue != aiEnabledRemembered else { return }
            UserDefaults.standard.set(aiEnabledRemembered, forKey: "aiEnabled")
        }
    }
    /// 编辑确认后的渲染进行中:上传按钮转圈并禁用,防双击双传。
    @Published var editSubmitting = false
    /// upload() 的并发调用计数——uploading 只在归零时熄灭。
    private var activeUploads = 0

    /// 上传前抹除元数据。默认开。
    ///
    /// 默认开而不是默认关:图床发出去的是公开外链,一张带 GPS 的照片等于把
    /// 拍摄地点一起发出去,而知道 EXIF 里有 GPS 的人远少于会随手发链接的人。
    /// 让想留原始元数据的人自己去关,比让不知情的人自己去开安全得多。
    ///
    /// 与 wm* 一样存 UserDefaults 而非账号偏好:剥离发生在这台 Mac 上,服务器
    /// 无从执行,存到账号里只会让另一台设备以为自己也剥了。
    @Published var stripMetadata = (UserDefaults.standard.object(forKey: "stripMetadata") as? Bool) ?? true {
        didSet {
            guard oldValue != stripMetadata else { return }
            UserDefaults.standard.set(stripMetadata, forKey: "stripMetadata")
        }
    }

    /// 开关对应的档位。界面上只给开/关两个位置,没把四档都摆出来:「删多少」
    /// 用户判断不了,而中间档的差别只有摄影者在意——他们要的正好是默认档
    /// .identifying 保留下来的曝光参数。
    var stripLevel: StripLevel { stripMetadata ? .identifying : .none }

    /// 剥离结果该不该拦下这张图;nil 表示可以传。
    ///
    /// 拦的判据是 stripFailureBlocks——"剥不成"本身不够,还要这一张**确实带着
    /// 定位**、而且服务端也不会替我们清掉。理由写在那个函数里。
    func stripBlockReason(_ outcome: StripOutcome, source: URL) -> String? {
        guard stripFailureBlocks(outcome, source: source) else { return nil }
        switch outcome {
        case .notNeeded, .stripped: return nil
        case .unsupported(let reason): return L.s.errors.stripBlocked(L.s.errors.stripReason(reason))
        case .verificationFailed: return L.s.errors.stripBlocked(L.s.errors.stripVerifyFailed)
        }
    }

    /// 上传前的最后一道闸。放在缩放与水印**之后**——那两步各自产出新的临时
    /// 文件,只有守在真正要发出去的那份字节上才没有绕过去的路。缩放本身只写
    /// 像素、不抄元数据,所以优化模式下这一步多半直接得到 .notNeeded,不会白
    /// 多一次读写。
    func stripBeforeUpload(_ url: URL) async -> StripOutcome {
        let level = stripLevel
        // 读写整个文件,别占着主线程——上传循环是串行的,一张 40MB 的 raw
        // 能让界面卡住肉眼可见的一下。
        return await Task.detached { ImageMetadata.strippedCopy(of: url, level: level) }.value
    }

    /// 剥不成的时候,这一张到底该不该拦住。
    ///
    /// 直接把"剥不成"一律当阻断,会把带元数据的 WebP 整类挡在门外——macOS 的
    /// ImageIO 写不了 WebP(长期如此,不是本机配置问题),而 WebP 截图相当常见。
    /// 拿产品可用性换一个多数情况下根本不存在的风险,不划算。
    ///
    /// 真实的风险面比"剥不成"窄得多,因为**服务端本来就剥**:
    ///   - 优化模式:vips 会 RemoveMetadata 并重新编码,元数据一个不剩;
    ///   - 原样模式:只对 JPEG 抹 GPS(StripGPSFromJPEG),其余格式原样存。
    /// 所以客户端剥离真正补的缺口只有一个——**原样模式下的非 JPEG**。
    ///
    /// 于是判据收成两条:优化模式一律放行;原样模式下只有"确实查出定位信息、
    /// 而本机又剥不掉"才拦。剥不成但本来就没有定位的(绝大多数截图)照常传。
    func stripFailureBlocks(_ outcome: StripOutcome, source: URL) -> Bool {
        if case .stripped = outcome { return false }
        if outcome.allowsOriginal { return false }
        // 服务端会重新编码,客户端这一步只是提前量。
        if uploadMode == .optimized { return false }
        // 原样模式:只有真的带着定位才拦。verificationFailed 已经带着扫描结果,
        // 不必再读一次盘。
        if case .verificationFailed(let residual) = outcome { return residual.hasLocation }
        return ImageMetadata.residual(source).hasLocation
    }

    // 水印偏好——纯本机合成,不上服务器,所以存 UserDefaults 而非账号偏好。
    // 唯一的例外是那枚 logo:几百 KB 的二进制归 WatermarkStore 管,理由写在
    // 那个类型的头注里(UserDefaults 会把整份 plist 在启动时读进内存)。
    @Published var wmKind = WatermarkKind(
        rawValue: UserDefaults.standard.string(forKey: "wmKind") ?? "") ?? .text
    @Published var wmText = UserDefaults.standard.string(forKey: "wmText") ?? ""
    @Published var wmAnchor = (UserDefaults.standard.object(forKey: "wmAnchor") as? Int) ?? 8
    @Published var wmOpacity = (UserDefaults.standard.object(forKey: "wmOpacity") as? Double) ?? 0.45
    /// 文字模式的字号比例。
    @Published var wmScale = (UserDefaults.standard.object(forKey: "wmScale") as? Double)
        ?? WatermarkKind.text.defaultScale
    /// 图片模式的 logo 宽度比例。**单独一个键**,不与 wmScale 共用。
    ///
    /// 两个数含义不同(字号 vs logo 整幅宽度)、量级差四倍。共用一个键的表现
    /// 是:从文字切到图片,那枚 logo 按 3% 贴上去小到看不见;再切回文字,字号
    /// 按 12% 糊掉半张图。切模式不该改变另一种模式下已经调好的样子。
    @Published var wmImageScale = (UserDefaults.standard.object(forKey: "wmImageScale") as? Double)
        ?? WatermarkKind.image.defaultScale
    @Published var wmAutoWatch = UserDefaults.standard.bool(forKey: "wmAutoWatch")

    /// 当前水印图的 PNG 字节。启动时从磁盘读一次就常驻:监控目录连传二十张
    /// 就是二十次同样的读,而这份字节最多 1024px 见方。
    @Published var wmImagePNG: Data?
    /// 水印图的预览位图。与 wmImagePNG 同步维护,不在 body 里现解——SwiftUI
    /// 的 body 一秒能跑几十次,每次解一张 1024px 的 PNG 是白烧 CPU。
    ///
    /// NSImage 只在主 actor 上被创建和读取(AppModel 整个是 @MainActor),
    /// 不跨并发边界。
    @Published var wmImagePreview: NSImage?
    /// 这张水印图整幅不透明——贴上去会是个方块。界面据此给出「去背景」入口,
    /// 而不是把这张图拦下来:一枚白底 logo 抠一下就能用,拦住等于让用户自己
    /// 去找修图软件。
    @Published var wmImageOpaque = false
    /// 去背景 / AI 生成正在跑。两件事共用一个标志:它们都要独占那枚 logo,
    /// 同时点两下的结果是后到的覆盖先到的,而用户看不出发生了什么。
    @Published var wmBusy = false
    /// AI 生成水印的在途记录 id。
    ///
    /// 落 UserDefaults 是为了 App 重启后还能接上:上游要几十秒,这期间关掉
    /// App 并不罕见,而那次生成的额度已经扣掉了。丢了这个 id,图还是会进图库
    /// (与其它 AI 产出一视同仁),但"顺手设成当前水印"那一步就断了。
    @Published var wmGenID = UserDefaults.standard.string(forKey: "wmGenID") ?? ""
    /// 生成水印用的描述。不持久化——它是一次性的。
    @Published var wmPrompt = ""

    func watermarkSpec() -> WatermarkSpec? {
        let spec: WatermarkSpec
        switch wmKind {
        case .text:
            spec = WatermarkSpec(text: wmText.trimmingCharacters(in: .whitespaces),
                                 anchor: wmAnchor, opacity: wmOpacity, scale: wmScale)
        case .image:
            guard let png = wmImagePNG else { return nil }
            spec = WatermarkSpec(imagePNG: png, anchor: wmAnchor,
                                 opacity: wmOpacity, scale: wmImageScale)
        }
        // 交给 Kit 判"渲染得出东西吗",不在这里再写一遍 text 非空:两处判断
        // 分头写,迟早有一处漏掉新的模式。
        return spec.isRenderable ? spec : nil
    }

    func saveWatermarkPrefs() {
        let d = UserDefaults.standard
        d.set(wmKind.rawValue, forKey: "wmKind")
        d.set(wmText, forKey: "wmText")
        d.set(wmAnchor, forKey: "wmAnchor")
        d.set(wmOpacity, forKey: "wmOpacity")
        d.set(wmScale, forKey: "wmScale")
        d.set(wmImageScale, forKey: "wmImageScale")
        d.set(wmAutoWatch, forKey: "wmAutoWatch")
        d.set(editOnDrop, forKey: "editOnDrop")
    }

    // 存储位置(BYOS)。改动类操作要邮箱验证码作二次因子——见后端
    // requireCodeIfToken:这组接口能把后续上传导去别处,单靠泄露的令牌
    // 不该做得成。
    @Published var storageProfiles: [StorageProfile] = []
    @Published var storageCodeSent = false
    @Published var storageCodeSentTo = ""
    @Published var storageCodeCooldown = 0

    // Stats
    @Published var summary: StorageSummary?
    @Published var transactions: [QuotaTransaction] = []
    @Published var checkins: [CheckinRecord] = []
    @Published var statsLoading = false

    // Conversion preferences. Mirrored locally so the controls respond
    // immediately; the server is the source of truth on next connect.
    @Published var uploadMode: UploadMode = .optimized
    @Published var variantFormat: VariantFormat = .webp
    @Published var maxImageWidth = 0

    // Upload
    @Published var uploading = false
    @Published var queue: [UploadItem] = []
    /// 正在从网址取的图。与 queue 分开:它们还没成为"待上传的文件",取完才进
    /// 队列;混在一起的话队列里会出现一种没有本地文件的行,每处用到 url 的地
    /// 方都要多一个判空。
    @Published var fetches: [RemoteFetch] = []
    /// 网址输入框里的内容。
    @Published var urlDraft = ""
    /// 本机 Image Playground 弹窗开着没有。
    @Published var localGenOpen = false
    /// 刷新图标转不转。
    @Published var refreshing = false
    /// 正在跑的刷新次数。连点两下时,转圈要等**最后一次**结束才停——用布尔量
    /// 的话第一次结束就把圈停了,而第二次还在跑,看着像刷新提前收工了。
    private var refreshRuns = 0
    @Published var dropping = false

    /// Overall progress across the batch, weighted by file size — a 40 KB icon
    /// finishing should not move the bar as far as a 20 MB photo.
    ///
    /// Falls back to counting files when no size is known. Reading a file size
    /// can fail, and a weighted average over all-zero weights is 0/0: the bar
    /// would sit at empty with half the batch already uploaded.
    var batchProgress: Double {
        guard !queue.isEmpty else { return 0 }
        let total = queue.reduce(0.0) { $0 + Double($1.size) }
        if total <= 0 {
            return queue.reduce(0.0) { $0 + $1.fraction } / Double(queue.count)
        }
        return queue.reduce(0.0) { $0 + Double($1.size) * $1.fraction } / total
    }

    /// Every size divides evenly by the five-column grid, so a full page never
    /// ends in a short row with holes where the missing cards would be — the
    /// same reason the web gallery uses these numbers.
    let pageSizes = [25, 50, 100, 200]

    private let store = TokenStore()
    private var searchTask: Task<Void, Never>?

    var connected: Bool { account != nil }
    var pageCount: Int { max(1, Int(ceil(Double(total) / Double(pageSize)))) }

    init() {
        token = store.load(server: server) ?? ""
        // 水印图从磁盘读一次就常驻。同步读:它最多 1024px 见方的 PNG,而
        // 异步读的代价是启动那一瞬间设置页会显示"还没设过水印图",然后突然
        // 冒出一枚——看起来像是刚被谁设上去的。
        wmAdopt(WatermarkStore.load())
    }

    func client() throws -> OpenimgClient {
        guard let url = URL(string: server.trimmingCharacters(in: .whitespaces)) else {
            throw OpenimgError.badServerURL
        }
        return try OpenimgClient(server: url, token: token)
    }

    /// 换服务器:令牌、账号、图库全都属于旧实例,一并清掉。清单与偏好按
    /// 服务器+账号键控,不需要在这里动。
    func setServer(_ raw: String) {
        var v = raw.trimmingCharacters(in: .whitespaces)
        if v.isEmpty { v = Self.officialServer }
        if !v.contains("://") { v = "https://" + v }
        while v.hasSuffix("/") { v.removeLast() }
        guard v != server else { return }
        watchStop()
        aiReset()
        server = v
        UserDefaults.standard.set(v, forKey: "server")
        token = ""
        account = nil
        quota = nil
        images = []
        total = 0
        storageProfiles = []
    }

    /// Names the credential on the server, so the token list on the website
    /// reads "Openimg for Mac · 西风的 MacBook" instead of an opaque entry the
    /// user cannot place.
    var deviceName: String { Host.current().localizedName ?? "Mac" }

    // MARK: - Connection

    /// Called at launch. Silent on failure — an expired token should land the
    /// user on the settings tab, not greet them with a red banner.
    /// 把本机时区报给服务器。
    ///
    /// 签到的"一天"从几点开始要按用户实际过的那一天算,而服务器没别的办法知道
    /// 那是哪个时区。报一次就存在账号上,不跟着每次请求走——跟着请求走的话,
    /// 改一下就能让"今天"变成另一天,签到可以刷。
    ///
    /// 失败不提示也不重试:它是纯优化,没报上去只是退回 UTC 日界,也就是这个
    /// 字段存在之前的行为。为它弹一个错只会让人困惑。
    private func reportTimezone() async {
        let tz = TimeZone.current.identifier
        guard tz != lastReportedTimezone, let c = try? client() else { return }
        try? await c.updatePreferences(timezone: tz)
        lastReportedTimezone = tz
    }

    func restore() async {
        guard !token.isEmpty else { section = .settings; return }
        await connect(quiet: true)
        if !connected { section = .settings }
    }

    private let oauth = OAuthSignIn()
    /// 上一次报上去的时区,避免每次连上都发一个空操作请求。
    private var lastReportedTimezone = ""

    var canSubmit: Bool {
        if registering {
            // 六位码在本地先拦一道:服务端 binding 要求 len=6,少一位就是一次
            // 白跑的往返,而错误还会笼统地报成"凭据太短"。
            return !email.isEmpty && password.count >= 8
                && !regName.trimmingCharacters(in: .whitespaces).isEmpty
                && regCode.count == 6
        }
        return !email.isEmpty && !password.isEmpty
    }

    /// 能不能发验证码。邮箱填了、且不在倒计时里。
    var canSendRegCode: Bool { !email.isEmpty && regCooldown == 0 && !busy }

    /// What the primary button and the return key both do, so the form has one
    /// submit path regardless of which mode it is in.
    func primaryAction() async {
        guard canSubmit, !busy else { return }
        if registering { await register() } else { await signIn() }
    }

    /// 请服务器发一封注册验证码,并起 60 秒倒计时。
    ///
    /// 倒计时是本地的,只为挡住连点——真正的频率限制在服务端。它先起再发:
    /// 请求失败也不立刻放开,否则一个打不通的网络会变成可以无限点的按钮。
    func sendRegisterCode() async {
        guard canSendRegCode else { return }
        guard let url = URL(string: server.trimmingCharacters(in: .whitespaces)) else {
            announce(message(OpenimgError.badServerURL)); return
        }
        regCooldown = 60
        startRegCooldown()
        do {
            try await OpenimgAuth.registerCode(server: url, email: email)
            regCodeSent = true
            announce(L.s.login.regCodeSent(email))
        } catch {
            announce(message(error), seconds: 8)
        }
    }

    private func startRegCooldown() {
        Task { [weak self] in
            while let s = self, s.regCooldown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.regCooldown -= 1
            }
        }
    }

    /// 注册并直接登录。
    ///
    /// 建完账号服务端下的是 cookie 会话,而这个客户端靠令牌活着,所以 Kit 那边
    /// 紧接着换成长效令牌——与密码登录完全同一段逻辑,见 OpenimgAuth.register。
    func register() async {
        busy = true
        defer { busy = false }
        do {
            guard let url = URL(string: server.trimmingCharacters(in: .whitespaces)) else {
                throw OpenimgError.badServerURL
            }
            let (minted, _) = try await OpenimgAuth.register(
                server: url, email: email, password: password,
                code: regCode, name: regName.trimmingCharacters(in: .whitespaces),
                device: deviceName
            )
            token = minted
            password = ""
            regCode = ""
            registering = false
            UserDefaults.standard.set(email, forKey: "email")
            await connect()
        } catch {
            account = nil
            announce(message(error), seconds: 8)
        }
    }

    /// Google, GitHub or passkey. All three finish the same way: the sheet
    /// hands back a one-time code and the token comes from trading it, so
    /// nothing long-lived ever travels through a URL.
    ///
    /// The providers go straight to their own start route. Passkey cannot —
    /// WebAuthn runs in the page, and driving it natively needs an
    /// associated-domains entitlement, which needs a Team ID a locally signed
    /// build does not have. It opens the site's own sign-in page instead,
    /// which hands back a code through the same handoff.
    func signIn(with method: SignInMethod) async {
        busy = true
        defer { busy = false }
        do {
            let code: String?
            switch method {
            case .passkey:
                // 先试本机仪式(Touch ID / iPhone 确认),不行再回落网页。
                //
                // 本机这条要 associated-domains 授权,而授权要签名身份——ad-hoc
                // 开发构建两样都没有,系统会直接拒。回落不是兜底摆设:开发构建
                // 天天在用,没有它这个按钮在本地就是坏的。
                if let native = try await passkeyCodeNatively() {
                    code = native
                } else {
                    code = try await oauth.startWebLogin(server: server)
                }
            case .google, .github:
                code = try await oauth.start(provider: method.rawValue, server: server)
            }
            guard let code else { return } // 用户关掉了登录窗口
            guard let url = URL(string: server) else { throw OpenimgError.badServerURL }
            let (minted, _) = try await OpenimgAuth.exchange(
                server: url, code: code, device: deviceName
            )
            token = minted
            await connect()
        } catch {
            account = nil
            announce(message(error))
        }
    }

    /// 走本机 Passkey 拿一次性 code;这台机器做不到就返回 nil,由调用方回落。
    ///
    /// 返回 nil 而不是抛错的只有一种情况:**这个构建没有资格**(没有签名身份、
    /// 或关联域名文件不对)。用户主动取消也返回 nil——他不想登,回落去弹个网页
    /// 同样不是他要的。真正的失败(网络、服务器)照旧抛出去。
    private func passkeyCodeNatively() async throws -> String? {
        guard let url = URL(string: server.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        let start: PasskeyLoginStart
        do {
            start = try await OpenimgAuth.passkeyLoginBegin(server: url)
        } catch {
            // 服务器不支持或没配 Passkey:这不是"本机不行",没必要回落到一个
            // 同样不会成功的网页流程。
            throw error
        }
        guard let challenge = Data(base64URL: start.options.publicKey.challenge) else {
            return nil
        }
        let rpID = start.options.publicKey.rpId ?? url.host ?? ""
        guard !rpID.isEmpty else { return nil }

        let asr: ASAuthorizationPlatformPublicKeyCredentialAssertion
        do {
            asr = try await PasskeyEnroller().assert(rpID: rpID, challenge: challenge)
        } catch {
            // 系统拒绝(没资格)或用户取消,两者都退回 nil 让调用方决定。
            NSLog("[openimg] 本机 Passkey 不可用,回落网页: %@", String(describing: error))
            return nil
        }
        guard let raw = asr.credentialID as Data?,
              let clientData = asr.rawClientDataJSON as Data?,
              let authData = asr.rawAuthenticatorData,
              let sig = asr.signature else { return nil }
        let assertion = WebAuthnAssertion(
            id: raw.base64URLEncoded,
            rawId: raw.base64URLEncoded,
            response: .init(
                clientDataJSON: clientData.base64URLEncoded,
                authenticatorData: authData.base64URLEncoded,
                signature: sig.base64URLEncoded,
                userHandle: asr.userID?.base64URLEncoded))
        return try await OpenimgAuth.passkeyLoginFinish(
            server: url, flow: start.flow, assertion: assertion)
    }

    /// Exchanges the password for a long-lived token, then connects with it.
    ///
    /// The session the password buys is not what gets stored: it expires in
    /// seven days and the server has no refresh endpoint, so keeping it would
    /// log the user out every week. See OpenimgAuth.signIn.
    func signIn() async {
        busy = true
        defer { busy = false }
        do {
            guard let url = URL(string: server.trimmingCharacters(in: .whitespaces)) else {
                throw OpenimgError.badServerURL
            }
            let (minted, _) = try await OpenimgAuth.signIn(
                server: url, email: email, password: password, device: deviceName
            )
            token = minted
            password = ""      // never held longer than the exchange needs
            UserDefaults.standard.set(email, forKey: "email")
            await connect()
        } catch {
            account = nil
            announce(message(error))
        }
    }

    func connect(quiet: Bool = false) async {
        busy = true
        defer { busy = false }
        do {
            let c = try client()
            let me = try await c.me()

            // Persist only after the server confirms the token, so a typo never
            // lands in the keychain for the next launch to load and fail with.
            // And persistence is not part of connecting: the token is already
            // known good here, so a keychain problem must not report "cannot
            // connect" for a session that works perfectly.
            var warning = ""
            do { try store.save(token, server: server) } catch {
                warning = L.s.errors.tokenNotSaved
            }

            account = me
            uploadMode = me.uploadMode.flatMap(UploadMode.init) ?? .optimized
            variantFormat = me.variantFormat.flatMap(VariantFormat.init) ?? .webp
            maxImageWidth = me.maxImageWidth ?? 0
            // 先报时区再取额度:签到状态是按时区算的,顺序反了的话首屏会显示
            // 上一个时区下的"今天已签到"。
            await reportTimezone()
            quota = try? await c.quota()
            await load(resetPage: true)
            await loadStats()
            await aiLoadStatus()
            watchSetup()
            // 上次那条「生成水印」还悬着就接着等。额度在提交那一刻就扣了,
            // 关一次 App 不该让那张图白生成——不接的话它仍会进图库,只是
            // "顺手设成当前水印"那一步断了。
            Task { await wmResumeGeneration() }
            if !quiet {
                announce(L.s.errors.connected(me.email, warning))
                section = .overview
            }
        } catch {
            account = nil
            announce(message(error))
        }
    }

    /// 退出。
    ///
    /// 先请服务器把这枚令牌作废,再抹掉本机那份。顺序不能反:抹完就没有凭据
    /// 去调撤销接口了。
    ///
    /// 撤销失败**不阻断退出**——用户要的是"从这台机器上下线",而网络出问题时
    /// 把他卡在登录态里毫无道理。但会如实说明服务器那边没撤成,而不是笼统地
    /// 报一句"已退出"。
    func signOut() {
        // 客户端要在清空之前拿到手:它在构造时就把令牌抓走了,而 signOutLocally
        // 是同步执行的——放到 Task 里再 client() 的话,等它真正跑起来时令牌
        // 已经是空串,撤销请求会带着空凭据出门。
        let c = try? client()
        let srv = server
        signOutLocally()
        guard let c else {
            // 本来就没连上,没有令牌可撤,不必说服务器那边的事。
            return
        }
        Task {
            do {
                _ = try await c.revokeCurrentToken()
                announce(OpenimgAuth.signedOutAndRevoked)
            } catch {
                NSLog("[openimg] 退出时撤销令牌失败 server=%@: %@",
                      srv, String(describing: error))
                announce(OpenimgAuth.signOutIsLocalOnly, seconds: 8)
            }
        }
    }

    /// 只清本机状态。撤销那一步由 signOut 负责。
    private func signOutLocally() {
        watchStop()
        aiReset()
        watchSkip.removeAll()
        watchStatus = ""
        watchPausedReason = nil
        watchLastIssue = nil
        exportCancelled = true
        store.delete(server: server)
        token = ""
        password = ""
        account = nil
        quota = nil
        images = []
        total = 0
        selection = []
        section = .settings
        // 提示由 signOut 在撤销有结果之后发:成没成是两句不同的话,这里发的话
        // 只会被后面那句盖掉,或者更糟——先说"已作废"再发现没成。
    }

    // MARK: - Stats

    var streak: Int { checkins.first?.streak ?? 0 }

    /// The server records days as UTC `yyyy-mm-dd`, so "today" has to be asked
    /// in UTC too — comparing against a local date puts the app a day out for
    /// anyone east of Greenwich, which is most of its users.
    var checkedInToday: Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = cal.timeZone
        return checkins.contains { $0.date == f.string(from: Date()) }
    }

    /// Monday-first, because that is how the streak reads to a user even
    /// though the server keys days in UTC.
    var thisWeek: [CheckinDay] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2
        cal.locale = L.locale
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = cal.timeZone

        // 星期缩写交给 Locale:中文得「一…日」,英文得「M…S」,不必自己维护
        // 两份表。符号表从周日排起,而这一周从周一算,所以取值时挪一位。
        let weekdays = cal.veryShortStandaloneWeekdaySymbols

        let now = Date()
        let today = f.string(from: now)
        let claimed = Set(checkins.map(\.date))
        guard let start = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }

        return (0..<7).compactMap { i in
            guard let day = cal.date(byAdding: .day, value: i, to: start) else { return nil }
            let key = f.string(from: day)
            return CheckinDay(
                id: key,
                label: weekdays[(i + 1) % 7],
                claimed: claimed.contains(key),
                isToday: key == today,
                future: key > today
            )
        }
    }

    /// How far into the current month-long milestone the streak has come.
    var monthProgress: (done: Int, total: Int) {
        let total = quota?.checkin?.daysPerMonth ?? 30
        guard total > 0 else { return (0, 30) }
        return (streak % total == 0 && streak > 0 ? total : streak % total, total)
    }

    func loadStats() async {
        guard connected else { return }
        statsLoading = true
        defer { statsLoading = false }
        guard let c = try? client() else { return }
        // Independent panels: one failing endpoint should blank its own card,
        // not the whole page.
        async let sum = try? await c.storageSummary()
        async let tx = try? await c.transactions(limit: 50)
        async let ck = try? await c.checkinHistory(limit: 130)
        // 存储位置也一并取。概览的存储卡要它,而它原来只在设置页拉——冷启动
        // 直接进概览时那张卡会空着,而空着的原因是"没人去取",不是"没有数据"。
        async let sp = try? await c.storageProfiles()
        async let tr = Result { try await c.uploadTrend(days: 30) }
        summary = await sum
        transactions = await tx?.transactions ?? []
        checkins = await ck ?? []
        storageProfiles = await sp ?? []
        switch await tr {
        case .success(let t):
            uploadTrend = t
            uploadTrendError = nil
        case .failure(let e):
            uploadTrendError = e.localizedDescription
        }
    }

    func checkin() async {
        busy = true
        defer { busy = false }
        do {
            let r = try await client().checkin()
            announce(r.capped
                ? L.s.errors.checkinCapped
                : L.s.errors.checkinDone(Self.bytes(r.grantedBytes), r.streak))
            quota = try? await client().quota()
            await loadStats()
        } catch {
            announce(message(error))
        }
    }

    // MARK: - Gallery

    func load(resetPage: Bool = false) async {
        guard !token.isEmpty else { return }
        if resetPage { page = 0 }
        busy = true
        defer { busy = false }
        do {
            let res = try await client().images(
                limit: pageSize, offset: page * pageSize, query: search, sort: sort
            )
            images = res.images
            total = res.total
            // A checked box on a row that is no longer on screen is a good way
            // to delete the wrong thing.
            selection = []
        } catch {
            announce(message(error))
        }
    }

    /// Typing in the search field should not fire a request per keystroke.
    func searchChanged() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await load(resetPage: true)
        }
    }

    /// What the refresh control and ⌘R do, which depends on the page: the
    /// gallery reloads its page, the overview reloads its numbers.
    /// 点了刷新按钮。**无论如何都转**,并且真的去取数据。
    ///
    /// 单独一个方法而不是直接调 refreshCurrent:按钮要的是"点了有反应",而
    /// refreshCurrent 是"把当前页的数据取一遍",两件事的时长不是一回事——
    /// 本地缓存命中或者接口很快时,它可能几十毫秒就回来了,转圈闪一下就没,
    /// 用户看到的等同于"点了没反应"。所以这里兜一个最短时长。
    ///
    /// 不设 disabled:忙的时候点一下什么都不发生,是这个按钮原来最让人困惑的
    /// 地方——用户不知道是没点中、还是坏了、还是在等。
    func refreshTapped() {
        Task { @MainActor in
            refreshRuns += 1
            refreshing = true
            let started = Date()
            await refreshCurrent()
            // 最短转够 0.6 秒。低于这个数,转一下和闪一下在眼睛里没有区别。
            let left = 0.6 - Date().timeIntervalSince(started)
            if left > 0 { try? await Task.sleep(for: .seconds(left)) }
            refreshRuns -= 1
            if refreshRuns <= 0 {
                refreshRuns = 0
                refreshing = false
            }
        }
    }

    func refreshCurrent() async {
        switch section {
        case .gallery: await load()
        case .overview:
            // 顺带刷 quota。空间卡那个大字读的是 model.quota,而它只在
            // connect() 时取过一次——不带上这一句,页面上最重要的数字按 ⌘R
            // 纹丝不动,而旁边的图表全都变了,看着像刷新坏了。
            //
            // 取回来才赋值,失败时留着旧的。别处是 `quota = try? …`(失败即
            // 清空),那个语义适合首次连接;而这是刷新,一次网络抖动把页面上
            // 最大的那个数字抹成空白,比显示一个几秒前的旧值糟得多。
            async let fresh = try? await client().quota()
            await loadStats()
            if let q = await fresh { quota = q }
        case .generate, .retouch:
            await aiLoadStatus()
            await aiRefresh()
        case .settings:
            quota = try? await client().quota()
            // 设置页上印着 pic.bi 的关联状态,而关联是在浏览器里做的:⌘R
            // 是用户回到应用后最顺手的那一下。
            await refreshAccountLinks()
        case .upload, .editor:
            quota = try? await client().quota()
        }
    }

    func go(to newPage: Int) async {
        page = min(max(0, newPage), pageCount - 1)
        await load()
    }

    // MARK: - Lightbox navigation

    var detailIndex: Int? {
        guard let d = detail else { return nil }
        return images.firstIndex { $0.id == d.id }
    }
    var canGoPrev: Bool { (detailIndex.map { $0 > 0 } ?? false) || page > 0 }
    var canGoNext: Bool {
        guard let i = detailIndex else { return false }
        return i < images.count - 1 || page < pageCount - 1
    }

    /// Stepping past either end of the page turns the page.
    ///
    /// Stopping at the page boundary would be simpler and would also mean the
    /// arrow keys go dead every 25 pictures for a reason the viewer cannot see
    /// — the page is a fetch detail, not something the user is looking at.
    func showPrev() async {
        guard let i = detailIndex else { return }
        if i > 0 { detail = images[i - 1]; return }
        guard page > 0 else { return }
        await go(to: page - 1)
        detail = images.last
    }

    func showNext() async {
        guard let i = detailIndex else { return }
        if i < images.count - 1 { detail = images[i + 1]; return }
        guard page < pageCount - 1 else { return }
        await go(to: page + 1)
        detail = images.first
    }

    func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func toggleAll() {
        if selection.count == images.count { selection = [] }
        else { selection = Set(images.map(\.id)) }
    }

    func deleteSelected() async {
        let ids = Array(selection)
        guard !ids.isEmpty else { return }

        let freed = images.filter { selection.contains($0.id) }.reduce(Int64(0)) { $0 + $1.sizeStored }
        let alert = NSAlert()
        alert.messageText = L.s.errors.deleteTitle(ids.count)
        alert.informativeText = L.s.errors.deleteBody(ids.count, Self.bytes(freed))
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.s.errors.deleteConfirm)
        alert.addButton(withTitle: L.s.errors.deleteCancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        busy = true
        defer { busy = false }
        do {
            // The server caps one call at 500.
            var deleted = 0
            for start in stride(from: 0, to: ids.count, by: 500) {
                let chunk = Array(ids[start..<min(start + 500, ids.count)])
                deleted += try await client().bulkDelete(ids: chunk).deleted
            }
            announce(L.s.errors.deleted(deleted))
            detail = nil
            quota = try? await client().quota()
            await load()
        } catch {
            announce(message(error))
        }
    }

    func delete(_ img: RemoteImage) async {
        selection = [img.id]
        await deleteSelected()
    }

    // MARK: - Upload

    func pickAndUpload() async {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        // Folders too: a shoot or a screenshot folder is the natural unit, and
        // making the user open it and select-all first is busywork.
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.image, .folder]
        panel.message = L.s.errors.pickImages
        guard panel.runModal() == .OK else { return }
        await upload(expand(panel.urls))
    }

    /// Walks folders into the image files inside them.
    ///
    /// Sorted by path so a folder arrives in the order the user sees it in
    /// Finder, and filtered by the tier's own format list rather than by a
    /// hard-coded set — a group that allows HEIC should be able to send HEIC.
    func expand(_ urls: [URL]) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if !isDir.boolValue {
                out.append(url)
                continue
            }
            let walker = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            while let f = walker?.nextObject() as? URL {
                guard (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                      isUploadable(f) else { continue }
                out.append(f)
            }
        }
        return out.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Extensions the account's own tier accepts, plus the aliases the server
    /// folds together — it stores "jpeg" but nobody names a file that way.
    func isUploadable(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        var allowed = Set(quota?.tier.allowedFormats ?? [])
        if allowed.isEmpty {
            allowed = ["jpeg", "png", "webp", "gif", "avif", "heic", "bmp", "tiff"]
        }
        if allowed.contains("jpeg") { allowed.formUnion(["jpg", "jpe"]) }
        if allowed.contains("heic") { allowed.insert("heif") }
        if allowed.contains("tiff") { allowed.insert("tif") }
        return allowed.contains(ext)
    }
    /// 返回真正传上去的那几张图,顺序与入参一致。
    ///
    /// 加这个返回值是为了「传一张图,立刻拿它当 AI 的原图/参考图」:那条路
    /// 要的就是这张新图的对象本身。绝大多数调用方(拖放、监控目录、编辑器)
    /// 不关心结果,所以 `@discardableResult`——但它们走的仍是同一条流水线,
    /// 没有为 AI 单开的上传口:配额、去重、本地预缩、失败中止全都照旧。
    @discardableResult
    /// copyLink 决定传完要不要把链接塞进剪贴板。
    ///
    /// 上传页的默认行为是传完即复制——那是它的主业。但 AI 页拿它上传参考图
    /// 时,用户正在写提示词,剪贴板里多半是他等会儿要粘的东西,悄悄换掉是
    /// 一件他既没要求也不会察觉的事。
    func upload(_ urls: [URL], copyLink: Bool = true) async -> [RemoteImage] {
        guard !urls.isEmpty else { return [] }
        // 并发调用(拖放/编辑器确认/监控几路都能进来)必须安全:旧实现整体
        // 替换 queue 后,另一路在途循环拿旧下标解引用会越界崩溃。改成:
        // 每个批次只按 id 定位自己的行,写入时刻找不到(队列被新批次换掉)
        // 就静默跳过——那行已不在屏幕上。
        let items = urls.map { UploadItem(url: $0) }
        activeUploads += 1
        uploading = true
        defer {
            activeUploads -= 1
            if activeUploads == 0 { uploading = false }
        }

        // The whole batch goes on screen up front, so the user can see what was
        // accepted before anything starts moving.
        queue = items

        func row(_ id: UUID) -> Int? { queue.firstIndex { $0.id == id } }

        var done = 0
        var lastLink = ""
        var uploaded: [RemoteImage] = []
        for (idx, item) in items.enumerated() {
            let url = item.url
            if let reason = rejectLocally(url) {
                if let k = row(item.id) { queue[k].state = .failed(reason) }
                continue
            }
            if let k = row(item.id) { queue[k].state = .uploading }

            // Shrink first when a width limit is set. Only ever a downscale in
            // the same format — see LocalResize for why nothing else happens on
            // this side. Skipped entirely in original mode, where the point is
            // to hand over the exact bytes.
            var toSend = url
            var temp: URL?
            if uploadMode == .optimized, maxImageWidth > 0,
               let smaller = LocalResize.shrink(url, maxWidth: maxImageWidth) {
                toSend = smaller
                temp = smaller
                if let k = row(item.id) {
                    queue[k].sentBytes =
                        (try? smaller.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
                }
            }
            defer { if let temp { try? FileManager.default.removeItem(at: temp) } }

            // 抹除定位与设备身份。剥不成就**不传**:这条路发出去的是公开外链,
            // 一张剥不干净的照片传上去就收不回来了,失败当成阻断而不是"算了
            // 照旧传"。
            var stripTemp: URL?
            let outcome = await stripBeforeUpload(toSend)
            if let reason = stripBlockReason(outcome, source: toSend) {
                if let k = row(item.id) { queue[k].state = .failed(reason) }
                announce(reason)
                continue
            }
            if let clean = outcome.strippedURL {
                toSend = clean
                stripTemp = clean
                if let k = row(item.id) {
                    queue[k].sentBytes =
                        (try? clean.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
                }
            }
            // strippedCopy 把产物放在自己的一次性目录里,连目录一起删。
            defer { if let s = stripTemp { try? FileManager.default.removeItem(at: s.deletingLastPathComponent()) } }

            do {
                let id = item.id
                // The server sees the original filename regardless of which
                // file the bytes came from.
                let res = try await client().upload(fileURL: toSend,
                                                    filename: url.lastPathComponent) { [weak self] p in
                    Task { @MainActor in
                        guard let self, let k = self.queue.firstIndex(where: { $0.id == id })
                        else { return }
                        self.queue[k].progress = p
                    }
                }
                if let k = row(item.id) {
                    queue[k].state = .done
                    queue[k].progress = 1
                    queue[k].deduplicated = res.deduplicated
                }
                lastLink = linkFormat.render(res.image)
                // 去重命中时返回的是**库里那张老图**,这正是调用方想要的:选它
                // 当原图与选那张老图完全等价,不会凭空多出一条一模一样的记录。
                uploaded.append(res.image)
                done += 1
            } catch {
                if let k = row(item.id) { queue[k].state = .failed(message(error)) }
                // Quota, daily cap and an invalid token all doom the rest of
                // the batch, so mark them rather than retrying into the wall.
                for rest in items[(idx + 1)...] {
                    if let k = row(rest.id), queue[k].state == .queued {
                        queue[k].state = .failed(L.s.errors.cancelled)
                    }
                }
                announce(message(error))
                break
            }
        }
        if done > 0 {
            if copyLink { copy(lastLink) }
            announce(done == 1 ? L.s.errors.uploadedOne : L.s.errors.uploadedMany(done))
            quota = try? await client().quota()
            await load(resetPage: true)
        }
        return uploaded
    }

    func clearQueue() { queue.removeAll() }

    /// Pushes a preference change. Applied optimistically because these are
    /// segmented controls — a picker that snaps back while a request is in
    /// flight feels broken even when nothing is wrong.
    func savePreferences() async {
        do {
            try await client().updatePreferences(
                uploadMode: uploadMode,
                variantFormat: variantFormat,
                maxImageWidth: maxImageWidth
            )
        } catch {
            announce(message(error))
        }
    }

    // MARK: - Security

    @Published var passkeys: [PasskeyCredential] = []
    @Published var codeSent = false
    /// Passkey 注册的验证码状态独立于改密码——两个表单在同一张卡上,
    /// 共用一个标志会互相误开。
    @Published var passkeyCodeSent = false
    /// 验证码发去了哪个邮箱、还剩几秒可重发。与网页端同一套呈现:只说
    /// "已发送"而不说发去哪,用户不知道该翻哪个信箱。
    @Published var codeSentTo = ""
    @Published var codeCooldown = 0
    @Published var pkCodeSentTo = ""
    @Published var pkCodeCooldown = 0
    private var cooldownTask: Task<Void, Never>?

    /// 一个计时器喂两个倒计时——两个表单各起一个 Task 会在同一秒里互相
    /// 打断,而且退出视图时容易漏掉取消。
    private func startCooldownTicker() {
        guard cooldownTask == nil else { return }
        cooldownTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if codeCooldown > 0 { codeCooldown -= 1 }
                if pkCodeCooldown > 0 { pkCodeCooldown -= 1 }
                if storageCodeCooldown > 0 { storageCodeCooldown -= 1 }
                if codeCooldown <= 0, pkCodeCooldown <= 0, storageCodeCooldown <= 0 {
                    cooldownTask = nil
                    return
                }
            }
        }
    }

    func loadPasskeys() async {
        guard connected, let c = try? client() else { return }
        passkeys = (try? await c.passkeys()) ?? []
    }

    /// Asks the server to mail a code. Deliberately not silent on success —
    /// the next screen asks for six digits, and if the mail never arrived the
    /// user needs to know the request itself went through.
    func sendCode(_ purpose: AccountCodePurpose) async {
        do {
            let sent = try await client().requestAccountCode(purpose: purpose)
            if purpose == .passkey {
                passkeyCodeSent = true
                pkCodeSentTo = sent.email
                pkCodeCooldown = sent.resendIn
            } else if purpose == .storage {
                storageCodeSent = true
                storageCodeSentTo = sent.email
                storageCodeCooldown = sent.resendIn
            } else {
                codeSent = true
                codeSentTo = sent.email
                codeCooldown = sent.resendIn
            }
            startCooldownTicker()
            announce(L.s.errors.codeSentTo(sent.email))
        } catch {
            announce(message(error))
        }
    }

    /// Returns true when the password actually changed, so the form knows
    /// whether to clear itself.
    func changePassword(code: String, newPassword: String) async -> Bool {
        do {
            try await client().changePassword(code: code, newPassword: newPassword)
            codeSent = false
            announce(L.s.errors.passwordChanged)
            return true
        } catch {
            announce(message(error))
            return false
        }
    }

    func deletePasskey(_ p: PasskeyCredential) async {
        do {
            try await client().deletePasskey(id: p.id)
            await loadPasskeys()
            announce(L.s.errors.passkeyRemoved(p.name))
        } catch {
            announce(message(error))
        }
    }

    func unlink(_ provider: String) async {
        do {
            try await client().unlink(provider: provider)
            account = try await client().me()
            // 关联状态决定服务器给不给 4K 那一档,而 AI 状态是登录时问过一次
            // 就留着的:不重取,生成页会一直摆着一个已经会被拒的清晰度。
            await aiLoadStatus()
            announce(L.s.errors.unlinked)
        } catch {
            announce(message(error))
        }
    }

    /// 重新问一次账号与 AI 状态。
    ///
    /// pic.bi 的关联在浏览器里完成——那条路要 cookie 会话,这个客户端拿的是
    /// 令牌,走不了——所以应用这边没有"完成"的回调可听,只能在用户回来时
    /// (⌘R,或点一下"我已完成关联")重新问服务器。静默失败:这只是刷新。
    func refreshAccountLinks() async {
        guard connected, let c = try? client() else { return }
        if let fresh = try? await c.me() { account = fresh }
        await aiLoadStatus()
    }

    // MARK: - Profile

    /// Renames the account.
    ///
    /// Not optimistic, unlike `savePreferences`: the server trims the string
    /// and caps it at 32 characters, so what it stores is not always what was
    /// typed, and a field that keeps showing the rejected value is worse than
    /// one that snaps to the truth.
    func saveNickname(_ name: String) async {
        guard let a = account, name != a.name else { return }
        do {
            let saved = try await client().updateProfile(name: name)
            account = try await client().me()
            announce(saved.isEmpty ? L.s.errors.nicknameCleared : L.s.errors.nicknameChanged(saved))
        } catch {
            announce(message(error))
        }
    }

    func pickAvatar() async {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = false
        p.message = L.s.errors.pickAvatar
        guard p.runModal() == .OK, let url = p.url else { return }
        await setAvatar(url)
    }

    func setAvatar(_ url: URL) async {
        // 服务器上限 8 MB(最终会压成 256px AVIF),本地先拦免得白传一趟
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > 8 << 20 {
            announce(L.s.errors.avatarTooLarge)
            return
        }
        busy = true
        defer { busy = false }
        do {
            _ = try await client().uploadAvatar(fileURL: url)
            account = try await client().me()
            announce(L.s.errors.avatarUpdated)
        } catch {
            announce(message(error))
        }
    }

    /// Rejects what the server would reject anyway.
    ///
    /// Worth doing locally because the daily upload count is consumed by the
    /// attempt, not by the success: learning from a 415 that HEIC is not in
    /// your tier costs one of the day's allowance either way.
    /// 本机 Image Playground 出的图。
    ///
    /// **先拷一份再传**。系统给的那个 URL 指向它自己的临时区,而上传是个要走
    /// 几秒的异步过程——中途被回收的话,失败原因会是一句"文件不存在",和真正
    /// 发生的事毫无关系。
    ///
    /// 出来的图按普通上传处理,不进 AI 生成记录:那条记录是服务端那次生成的
    /// 凭据(扣了几次、什么模型、失败能不能退),而这一张压根没经过服务端。
    /// 硬塞进去只会让"本月还剩几次"对不上账。
    func acceptLocalGeneration(_ url: URL) async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("openimg-local", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = url.lastPathComponent.isEmpty ? "image.png" : url.lastPathComponent
        let dest = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            announce(message(error))
            return
        }
        _ = await upload([dest])
        try? FileManager.default.removeItem(at: dest)
    }

    // MARK: - 网址取图与粘贴

    /// 正在下载的一条。
    struct RemoteFetch: Identifiable {
        let id = UUID()
        let url: URL
        var received: Int64 = 0
        /// 对方没给 Content-Length 时是 -1。别拿它当分母。
        var total: Int64 = -1
        /// 失败原因。留着而不是让这一行消失——一闪而过的失败等于没报错。
        var failed: String?

        var fraction: Double? {
            guard total > 0 else { return nil }
            return min(1, max(0, Double(received) / Double(total)))
        }
        var name: String {
            let last = url.lastPathComponent
            return last.isEmpty || last == "/" ? (url.host ?? url.absoluteString) : last
        }
    }

    private var fetchTasks: [UUID: Task<Void, Never>] = [:]

    /// 下载落地的地方。放自己的子目录里,便于收尾时整块清掉。
    private var remoteDir: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("openimg-remote", isDirectory: true)
    }

    /// 从一条网址取图,取完直接进上传队列。
    func fetchFromURL(_ raw: String) {
        guard let url = RemoteImageURL.parse(raw) else {
            announce(L.s.upload.urlBad)
            return
        }
        urlDraft = ""
        let item = RemoteFetch(url: url)
        fetches.append(item)
        let id = item.id
        // 上限用用户组的单文件上限。为了发现"太大了"把 2 GB 拉完是没必要的,
        // RemoteDownload 会在 Content-Length 或者累计字节超了的时候当场掐断。
        let cap = quota?.tier.maxFileSize ?? 0
        let dir = remoteDir

        fetchTasks[id] = Task { @MainActor in
            // 强捕获 self:任务是短命的,而 defer 一定会把它从 fetchTasks 里摘
            // 掉,循环引用活不过这一次下载。用 weak 反而写不出来——进度回调里
            // 再套一层 weak 就成了"在并发闭包里引用被捕获的 var self"。
            defer { self.fetchTasks[id] = nil }
            do {
                let file = try await RemoteDownload.fetch(url, into: dir, maxBytes: cap) { p in
                    Task { @MainActor in self.applyFetchProgress(id, p) }
                }
                guard !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: file)
                    return
                }
                self.fetches.removeAll { $0.id == id }
                _ = await self.upload([file])
                // 上传路径不删来源文件(拖进来的是用户自己的图),但这一份是我们
                // 下的,不清就会在临时目录里一直堆着。
                try? FileManager.default.removeItem(at: file)
            } catch {
                guard !Task.isCancelled else { return }
                if let k = self.fetches.firstIndex(where: { $0.id == id }) {
                    self.fetches[k].failed = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
    }

    private func applyFetchProgress(_ id: UUID, _ p: RemoteDownload.Progress) {
        guard let k = fetches.firstIndex(where: { $0.id == id }) else { return }
        fetches[k].received = p.received
        fetches[k].total = p.total
    }

    /// 取消或收起一条。
    func dropFetch(_ id: UUID) {
        fetchTasks[id]?.cancel()
        fetchTasks[id] = nil
        fetches.removeAll { $0.id == id }
    }

    /// 粘贴板里有什么就上传什么。
    ///
    /// 三种来源按"最明确"到"最含糊"依次试:拷贝的文件 → 位图数据 → 一段看着
    /// 像网址的文字。顺序反过来的话,从 Finder 拷贝的图片会因为剪贴板上同时挂
    /// 着一份文件名字符串而被当成网址去请求。
    func pasteAndUpload() async {
        let pb = NSPasteboard.general

        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            await handleDrop(urls)
            return
        }

        if let file = pasteboardImageFile(pb) {
            _ = await upload([file])
            try? FileManager.default.removeItem(at: file)
            return
        }

        if let text = pb.string(forType: .string), RemoteImageURL.parse(text) != nil {
            fetchFromURL(text)
            return
        }

        announce(L.s.upload.pasteEmpty)
    }

    /// 把剪贴板上的位图落成一个临时文件。
    ///
    /// 优先拿 PNG 原样落盘;只有 TIFF 时才转一次——截图和多数应用给的都是 PNG,
    /// 无条件走 NSImage 转码等于给每一次粘贴白付一次重编码。
    private func pasteboardImageFile(_ pb: NSPasteboard) -> URL? {
        var data = pb.data(forType: .png)
        var ext = "png"
        if data == nil, let tiff = pb.data(forType: .tiff) {
            data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            ext = "png"
        }
        guard let data, !data.isEmpty else { return nil }

        let stamp = Int(Date().timeIntervalSince1970)
        let dir = remoteDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("pasted-\(stamp).\(ext)")
        do {
            try data.write(to: file)
            return file
        } catch {
            return nil
        }
    }

    func rejectLocally(_ url: URL) -> String? {
        guard let tier = quota?.tier else { return nil }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if tier.maxFileSize > 0, Int64(size) > tier.maxFileSize {
            return L.s.errors.fileTooLarge(Self.bytes(tier.maxFileSize))
        }
        let ext = url.pathExtension.lowercased()
        // 与服务端 CanonFormat 同一套折叠:jpe/tif 少了会被本地误拒,而服务
        // 端本会接受
        let canon = switch ext {
        case "jpg", "jpe": "jpeg"
        case "heif": "heic"
        case "tif": "tiff"
        default: ext
        }
        if !tier.allowedFormats.isEmpty, !tier.allowedFormats.contains(canon) {
            return L.s.errors.formatNotAllowed(ext.uppercased())
        }
        return nil
    }

    // MARK: - Helpers

    func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var toastTask: Task<Void, Never>?

    /// Shows a message and clears it on its own. A status line that never goes
    /// away turns into furniture and stops being read.
    func announce(_ text: String, seconds: Double = 4) {
        withAnimation(.spring(duration: 0.3)) { status = text }
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { status = "" }
        }
    }

    func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    static func bytes(_ n: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        // Otherwise a zero-byte file reads as "Zero KB", which is both wrong
        // and the sort of string that makes a UI look unfinished.
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: n)
    }
    func bytes(_ n: Int64) -> String { Self.bytes(n) }
}
