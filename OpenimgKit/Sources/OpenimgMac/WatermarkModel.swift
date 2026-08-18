import AppKit
import Foundation
import OpenimgKit
import UniformTypeIdentifiers

/// 图片水印那一半:换图、去背景、让 AI 画一枚。
///
/// 单独一个文件,因为这三件事都是**异步且会失败**的,而 AppModel 里那一段
/// 水印偏好是一串同步的 UserDefaults 读写。混在一起时,"哪些状态改完要存盘"
/// 与"哪些状态是一次操作的中途"就分不清了。
extension AppModel {

    // MARK: - 采纳一张水印图

    /// 把一份 PNG 字节设成当前水印图,顺带把两个派生状态一起更新。
    ///
    /// 三个属性只能一起变:字节、预览位图、透不透明。分开设的下场是界面上
    /// 还画着上一枚 logo,而渲染用的已经是新的那枚——这种不一致在截图里
    /// 看不出来,只会在传上去之后才发现。
    ///
    /// nil 表示"现在没有水印图"。
    func wmAdopt(_ png: Data?) {
        wmImagePNG = png
        guard let png, let img = ImageEdit.decode(png) else {
            wmImagePreview = nil
            wmImageOpaque = false
            return
        }
        wmImagePreview = NSImage(cgImage: img,
                                 size: NSSize(width: img.width, height: img.height))
        wmImageOpaque = !ImageEdit.hasTransparency(img)
    }

    /// 这张水印图值得提醒一句「去背景」吗。
    ///
    /// 只在图片模式下问:文字模式根本没有这张图,而一个常亮着的按钮会让人
    /// 以为文字水印也有背景可去。
    var wmNeedsCutout: Bool { wmKind == .image && wmImagePNG != nil && wmImageOpaque }

    // MARK: - 选一张图

    /// 从磁盘挑一张图当水印。
    ///
    /// 收的格式比 PNG 宽:用户手上多半是一张 JPEG 的 logo,拦住他等于让他先
    /// 去别处转一次格式。存进来时统一归一化成 PNG(见 WatermarkStore.store),
    /// 不透明的那些由「去背景」接手。
    func wmChooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .webP, .gif, .bmp]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = L.s.settings.wmChooseImage
        guard panel.runModal() == .OK, let url = panel.url else { return }
        wmLoadImage(from: url)
    }

    /// 读一个文件当水印图。拖拽落图与面板选图共用这一条。
    func wmLoadImage(from url: URL) {
        do {
            let raw = try Data(contentsOf: url)
            wmAdopt(try WatermarkStore.store(raw))
            wmKind = .image           // 刚选完图却还停在文字模式,那一步白做了
            saveWatermarkPrefs()
        } catch {
            announce(wmMessage(error), seconds: 6)
        }
    }

    /// 清掉水印图。不顺手切回文字模式:用户可能只是想换一张。
    func wmClearImage() {
        WatermarkStore.clear()
        wmAdopt(nil)
    }

    // MARK: - 去背景

    /// 本机抠掉水印图的背景。
    ///
    /// 传的是 Data 不是 CGImage:抠图要跑 Vision 的前景分割,几百毫秒起,
    /// 挂在主线程上界面会肉眼可见地僵住。字节两头都自足,不必操心谁持有谁。
    func wmRemoveBackground() async {
        guard let png = wmImagePNG, !wmBusy else { return }
        wmBusy = true
        defer { wmBusy = false }
        let out: Result<Data?, Error> = await Task.detached {
            do { return .success(try WatermarkStore.withoutBackground(png)) }
            catch { return .failure(error) }
        }.value
        switch out {
        case .failure(let e):
            announce(wmMessage(e), seconds: 6)
        case .success(nil):
            // Vision 认不出主体。照实说,而不是给一张被胡乱挖空的图——那种图
            // 用户得贴到照片上才发现不对。
            announce(L.s.settings.wmCutoutNoSubject, seconds: 6)
        case .success(.some(let cut)):
            do { wmAdopt(try WatermarkStore.store(cut)) }
            catch { announce(wmMessage(error), seconds: 6) }
        }
    }

    // MARK: - 让 AI 画一枚

    /// 能不能按下「生成」。
    ///
    /// 额度那一条读 `AIStatus.canGenerate` 而不是 `aiRemaining > 0`:本地免费
    /// 额度见底不等于生成不了——关联了 pic.bi 且那边还有钱时服务端会接管。
    /// 只看 remaining 会把按钮恰好封死在"pic.bi 正该出场"的那一刻。
    ///
    /// wmGenID 非空表示上一条还在跑。不排队,直接不让提交:两条同时在途时
    /// 后落地的那张会把先落地的那张顶掉,而用户看不出发生了什么。
    var wmCanGenerate: Bool {
        aiStatus?.canGenerate == true && !wmBusy && wmGenID.isEmpty
            && !wmPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 提交一次「画一枚水印」。
    ///
    /// 走的是同一个 `/api/ai/generate`,只多带一个 `purpose`。透明底要换模型、
    /// 要 `background`+`output_format` 成对出现,这些约束全在后端一处
    /// (aiWatermarkPlan);客户端拼那三个参数意味着把"哪个模型认哪个键"这条
    /// 会随上游变的知识复制过来,而拼错的表现是拿回一张不透明的图、没有报错。
    ///
    /// 产物照常进图库——它和别的 AI 产出没有区别,去重、变体、短链一样也不少。
    /// 这里额外做的只有一件事:把本地这份设成当前水印。
    func wmGenerate() async {
        guard wmCanGenerate, let c = try? client() else { return }
        let prompt = wmPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        wmBusy = true
        defer { wmBusy = false }
        do {
            let gen = try await c.aiGenerateWatermark(prompt: prompt)
            wmSetPendingGen(gen.id)
            // 这条记录也归"最近生成"那一页管:它就是一条普通的生成记录,
            // 从设置页发起不改变这一点。列表里已经有了就别插重的——提交的
            // 响应回来之前,正好卡在那一刻的轮询可能已经把它取回来了。
            if !aiGenerations.contains(where: { $0.id == gen.id }) {
                aiGenerations.insert(gen, at: 0)
            }
            await aiLoadStatus()
            announce(L.s.settings.wmGenSubmitted)
        } catch {
            announce(aiMessage(error), seconds: 8)
            await aiLoadStatus()
            return
        }
        await wmAwaitGeneration()
    }

    /// 记住在途的那条记录。落盘,理由见 AppModel.wmGenID。
    func wmSetPendingGen(_ id: String) {
        wmGenID = id
        UserDefaults.standard.set(id, forKey: "wmGenID")
    }

    /// 等在途那条生成落地,成了就把图取回来设成水印。
    ///
    /// 自己轮而不是搭 `aiPollStart` 那条:那一条的总闸是「有一页 AI 界面正在
    /// 屏幕上」(见 aiViewVisible),而这件事是从设置页发起的,永远不满足那个
    /// 条件。合并两者要么让那条轮询失去总闸(没人看的时候也在问服务器),要么
    /// 让这件事永远等不到结果。
    ///
    /// 上限 200 轮 × 3 秒 = 10 分钟,与后端放弃一次生成的窗口同量级;超时只是
    /// 不再等,记录与那张图都还在,重启后接着等。
    func wmAwaitGeneration() async {
        let id = wmGenID
        guard !id.isEmpty else { return }
        for _ in 0..<200 {
            try? await Task.sleep(for: .seconds(3))
            guard connected, let c = try? client() else { return }
            guard let page = try? await c.aiGenerations() else { continue }
            aiGenerations = page.generations
            aiImages = page.images
            guard let gen = page.generations.first(where: { $0.id == id }) else {
                // 记录不在最近三十条里了(隔了很久才回来看)。再等下去也等不到,
                // 松开这个 id,免得它永远挡着下一次生成。
                wmSetPendingGen("")
                return
            }
            guard gen.status.isTerminal else { continue }
            wmSetPendingGen("")
            if gen.status == .failed {
                announce(L.s.settings.wmGenFailed(gen.error ?? L.s.common.failed), seconds: 8)
                await aiLoadStatus()
                return
            }
            guard let img = page.image(for: gen) else {
                announce(L.s.settings.wmGenFailed(L.s.common.failed), seconds: 8)
                return
            }
            await wmAdoptRemote(img)
            await aiLoadStatus()
            // 图库里多了一张,和别的 AI 产出一样。
            await load(resetPage: true)
            return
        }
    }

    /// 把图库里的一张图取回来设成水印图。
    ///
    /// 从公开地址下载而不是找本地缓存:这张图刚在服务器上生成,本机从来没有
    /// 过它的字节。下下来之后仍要过 WatermarkStore.store 归一化——服务端可能
    /// 已经把它转成了别的格式,而这条路上唯一不能丢的就是 alpha。
    func wmAdoptRemote(_ img: RemoteImage) async {
        guard let url = URL(string: img.url) else { return }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                announce(L.s.settings.wmGenFailed(L.s.common.failed), seconds: 6)
                return
            }
            // 上游给回来的是一张**不透明**的图:全站只用 gpt-image-2,而它不认
            // background/output_format 那套透明底参数。所以在这里本机抠一次
            // ——Vision 的前景分割,与「去背景」按钮同一段代码,不额外调一次
            // 上游、也不多花一份钱。提示词里明写了纯色背景,正是为了让它好抠。
            //
            // 抠不出来不算失败:那张图仍然是可用的水印,只是带着底。所以退回
            // 原图并说一句,而不是把整件事判死。
            let stored = try WatermarkStore.store(data)
            let cut: Data? = await Task.detached {
                try? WatermarkStore.withoutBackground(stored)
            }.value
            wmAdopt(cut ?? stored)
            wmKind = .image
            saveWatermarkPrefs()
            announce(cut != nil ? L.s.settings.wmGenDone : L.s.settings.wmGenDoneOpaque)
        } catch {
            announce(wmMessage(error), seconds: 6)
        }
    }

    /// App 启动、或重新连上之后:上次那条生成还悬着就接着等。
    ///
    /// `wmBusy` 在这里当单飞闸用:重连会走两遍(自动连接 + 用户手点),而
    /// 两条轮询循环等同一条记录,谁先看到终态谁就去下载,结果是同一张图被
    /// 存两遍、提示弹两次。
    func wmResumeGeneration() async {
        guard !wmGenID.isEmpty, aiEnabled, connected, !wmBusy else { return }
        wmBusy = true
        defer { wmBusy = false }
        await wmAwaitGeneration()
    }

    // MARK: - 文案

    func wmMessage(_ error: Error) -> String {
        guard let f = error as? WatermarkStore.Failure else { return message(error) }
        return switch f {
        case .tooLarge: L.s.settings.wmErrTooLarge(WatermarkStore.maxInputBytes / (1 << 20))
        case .notAnImage: L.s.settings.wmErrNotAnImage
        case .encodeFailed, .writeFailed: L.s.settings.wmErrSaveFailed
        }
    }
}
