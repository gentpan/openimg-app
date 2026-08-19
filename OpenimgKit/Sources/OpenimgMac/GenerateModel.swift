import Foundation
import OpenimgKit

/// 文生图的状态机,顺带是修图的那一半。
///
/// 生成是异步的:提交只换回一条 pending 记录,图要等上游几十秒。所以这里的
/// 核心是一个轮询循环——每三秒问一次 `/api/ai/generations`,直到没有在途的
/// 记录为止,页面一消失就取消。没人看着的时候不该有请求在跑。
///
/// 修图(RetouchModel.swift)与这里共用额度、历史与这一条轮询:后端把两件事
/// 记在同一张表里,一次请求就把两页要的数据都取回来了,再起一个定时器只会让
/// 同一份数据被问两遍。那边只写它独有的部分——原图。
extension AppModel {

    // MARK: - 派生状态

    /// AI 开没开。
    ///
    /// 状态还没拉回来时用上次启动记住的值,而不是一律当作"没开"。侧栏那两行
    /// 是导航,不是内容:每次冷启动先少两行、等一次网络往返再补上,看起来像
    /// 是功能时有时无。记住上次的结果,启动那一刻就是对的,拉回来再纠正——
    /// 猜错的代价只是短暂多/少一行,而猜对是常态(这个开关几乎不变)。
    var aiEnabled: Bool { aiStatus?.enabled ?? aiEnabledRemembered }

    /// 侧栏该显示哪几行。没配 APIMART_API_KEY 的部署里,「生成」和「修图」
    /// 不是灰的,是不存在的——给一个点不动的入口等于承诺了一件做不到的事。
    var visibleSections: [Section_] {
        Section_.allCases.filter { !$0.needsAI || aiEnabled }
    }

    /// 本站免费额度还剩几次。
    var aiRemaining: Int { aiStatus?.remaining ?? 0 }

    /// 这一刻到底还能不能生成。
    ///
    /// 本站额度见底不等于不能生成:关联了 pic.bi 且那边还有钱时,服务端会自动
    /// 接管(本地先扣、扣不动才走远程)。只看 aiRemaining 会把按钮封死在
    /// 「pic.bi 正该出场」的那一刻,整条付费路径永远走不到——而 AIStatus 里
    /// 早就有 canGenerate 把这件事算好了,两处各算各的迟早说出两种话。
    var aiCanUse: Bool { aiStatus?.canGenerate ?? false }

    /// pic.bi 那边还剩多少。没关联就是 0。
    var aiPicbiRemaining: Int { aiStatus?.picbiRemaining ?? 0 }

    /// 有没有一页 AI 界面正在屏幕上。轮询以它为总闸。
    ///
    /// 直接读 `section` 而不是让两个页面各自置位一个标志:SwiftUI 不保证旧页
    /// 的 onDisappear 一定跑在新页的 task 之前,而生成与修图之间是可以直接互
    /// 切的——顺序反过来的那一次,刚立起的标志会被上一页放倒,轮询就此停在
    /// 一个正看着的页面上。它同时还挡住了另一件事:提交是异步的,点完按钮立
    /// 刻切走时,`aiPollStart` 在离开之后才执行,那时 section 已经不是这两页
    /// 中的任何一个了。
    var aiViewVisible: Bool { section.needsAI }

    /// 还有没有没跑完的记录。轮询的开关就看它。
    var aiPending: Bool { aiGenerations.contains { !$0.status.isTerminal } }

    /// 历史按种类分给两页。同一张表、同一次请求,只是各看各的那一半——修图
    /// 记录混在文生图的列表里,那句「用这句再生成」会丢掉原图,重来一次得到
    /// 的是另一件事。
    /// 生成页两种都看。
    ///
    /// 它现在也能带参考图,而带了参考图的提交在后端就是一条 edit 记录——只看
    /// 文生图的话,用户在这一页按下按钮,结果却永远不出现在这一页,他会以为
    /// 提交失败了。代价是修图页发的记录也列在这里,但行内本来就有「修图」
    /// 徽章,读起来是通的。
    var aiTextGenerations: [AIGeneration] { aiGenerations }
    var aiEditGenerations: [AIGeneration] { aiGenerations.filter(\.isEdit) }

    /// 侧栏那两行各自的转圈:哪一页有在途的,才在哪一行转。
    var aiPendingText: Bool { aiTextGenerations.contains { !$0.status.isTerminal } }
    var aiPendingEdit: Bool { aiEditGenerations.contains { !$0.status.isTerminal } }

    /// 服务器给的可选值;拿不到就退回一个能用的最小集,免得界面空掉。
    var aiSizes: [String] {
        let s = aiStatus?.sizes ?? []
        return s.isEmpty ? ["1:1"] : s
    }
    var aiResolutions: [String] {
        let r = aiStatus?.resolutions ?? []
        return r.isEmpty ? ["1k"] : r
    }

    /// 按 Unicode 标量数,不是字素簇数——后端量的是 `len([]rune(prompt))`。
    /// 一个 👨‍👩‍👧 在 Swift 里是 1 个 Character 却是 5 个 rune,用 `count` 会
    /// 让本地放行的描述在服务器那边撞上 400。
    var aiPromptLength: Int {
        aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
    }
    var aiPromptTooLong: Bool { aiPromptLength > aiPromptLimit }

    var aiCanSubmit: Bool {
        aiEnabled && !aiSubmitting && aiCanUse
            && aiPromptLength > 0 && !aiPromptTooLong
    }

    // MARK: - 加载

    func aiLoadStatus() async {
        guard connected, let c = try? client() else { return }
        // 静默失败:AI 是附加功能,一个坏掉的端点不该在登录成功时弹红条。
        guard let s = try? await c.aiStatus() else { return }
        aiStatus = s
        aiEnabledRemembered = s.enabled
        // 选择必须落在服务器给的合法值里,否则提交时会被静默改写成默认档,
        // 界面显示的和实际出的图对不上。
        if !s.sizes.isEmpty, !s.sizes.contains(aiSize) { aiSize = s.sizes[0] }
        if !s.resolutions.isEmpty, !s.resolutions.contains(aiResolution) {
            aiResolution = s.resolutions[0]
        }
        // 功能被关掉时(自建实例撤掉了 key),别把用户留在一个已经不存在的
        // 页面上。
        if !s.enabled, section.needsAI { section = .overview }
    }

    /// 进入生成页或修图页。两页共用同一条轮询,进出也就共用这一对方法。
    func aiViewAppeared() async {
        await aiLoadStatus()
        // 列表为空说明这是本会话头一回进来,那一刻看到的「已完成」全是历史,
        // 不该为它们弹提示。再次回到这一页时列表还留着上次的样子,谁是趁我
        // 不在时落地的一目了然——那些该照常提示、照常刷图库。
        await aiRefresh(settling: aiGenerations.isEmpty)
    }

    /// 离开生成页或修图页。没人看着的时候不该有请求在跑。
    ///
    /// 「离开」不等于「这一页消失了」:从生成切到修图时,消失的那一页交出的
    /// 是接力棒而不是终点——另一页正等着同一条轮询。所以只在两页都不在时才
    /// 真的停。
    func aiViewDisappeared() {
        guard !section.needsAI else { return }
        aiPollStop()
    }

    /// 拉一次历史。
    ///
    /// `settling` 为真表示这是本会话第一次加载:那一刻所有已完成的记录都
    /// 删掉一条生成记录,可选连同产出图。
    ///
    /// 先请求再改本地。乐观地先移除的话,请求失败那一行要么凭空回来、要么
    /// 就此消失而服务端还留着——两种都是骗人。删除没有连点场景,一次往返的
    /// 等待不值得拿正确性去换。
    func aiDelete(_ gen: AIGeneration, alsoImage: Bool) async {
        guard let c = try? client() else { return }
        do {
            try await c.aiDeleteGeneration(gen.id, alsoImage: alsoImage)
        } catch {
            announce(aiMessage(error))
            return
        }
        aiGenerations.removeAll { $0.id == gen.id }
        if alsoImage, let id = gen.imageID {
            aiImages[id] = nil
            // 图库里那张也得跟着消失,否则要等下一次翻页才对得上。
            images.removeAll { $0.id == id }
        }
        announce(L.s.generate.removed)
        // 删图会退还存储配额,额度面板的数字要跟上。
        await aiLoadStatus()
    }

    /// 是「新看到的」,但没有一条是**刚刚**完成的,不该为它们弹提示、刷图库。
    func aiRefresh(settling: Bool = false) async {
        guard connected, let c = try? client() else { return }
        aiLoading = aiGenerations.isEmpty
        defer { aiLoading = false }
        let wasTerminal = Set(aiGenerations.filter { $0.status.isTerminal }.map(\.id))
        guard let page = try? await c.aiGenerations() else { return }
        aiGenerations = page.generations
        aiImages = page.images
        // 只要还有在途的就保证有一轮在等它——⌘R 刷新可能刚发现一条从网页端
        // 提交的记录,那时并没有循环在跑。已经在跑、或页面已经走了,这里都是
        // 空操作(见 aiPollStart 的两道闸)。
        if aiPending { aiPollStart() }
        guard !settling else { return }

        let justFinished = page.generations.filter {
            $0.status.isTerminal && !wasTerminal.contains($0.id)
        }
        guard !justFinished.isEmpty else { return }

        // 有记录落地了:余额变了(失败会退还),图库多了张图。
        await aiLoadStatus()
        // 落地的是哪一件事就说哪一句。同一条轮询喂两页,一句「生成完成」用在
        // 修图上会让人以为凭空多出了一张图,而用户刚做的是改一张已有的。
        if let done = justFinished.first(where: { $0.status == .completed }) {
            quota = try? await c.quota()
            // 与上传后一样刷新图库:那张图现在就在库里,列表停在旧的一页
            // 只会让人以为没存进去。
            await load(resetPage: true)
            announce(done.isEdit ? L.s.retouch.doneToast : L.s.generate.doneToast)
        }
        if let failed = justFinished.first(where: { $0.status == .failed }) {
            let reason = failed.error ?? L.s.common.failed
            announce(failed.isEdit ? L.s.retouch.failedToast(reason)
                                   : L.s.generate.failedToast(reason), seconds: 8)
        }
    }

    // MARK: - 提交

    /// 生成页的提交。一个按钮,按有没有参考图分两条路。
    ///
    /// 没有参考图是 `/api/ai/generate`(凭空画一张);有参考图就是
    /// `/api/ai/edit`——「按这几张图画」在后端本来就是同一件事,没有第三个
    /// 接口,也不该为它做成两个模式开关让用户自己去选对。
    func aiGenerate() async {
        guard aiCanSubmit else { return }
        let prompt = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let refs = generateSources
        aiSubmitting = true
        defer { aiSubmitting = false }
        do {
            let gen: AIGeneration
            if refs.isEmpty {
                gen = try await client().aiGenerate(
                    prompt: prompt, size: aiSize, resolution: aiResolution)
            } else {
                gen = try await client().aiEdit(
                    prompt: prompt, imageIDs: refs.map(\.id),
                    size: aiSize, resolution: aiResolution)
                // 参考图先记进 aiImages,历史行才能立刻画出缩略图——响应里只有
                // 这条记录本身,而图对象此刻就在手上。
                for img in refs where aiImages[img.id] == nil { aiImages[img.id] = img }
            }
            // 先插到列表最前面,不等下一轮轮询——提交后一秒内什么都不变的
            // 界面看起来就像没提交成功。落库发生在响应回来之前,所以正好卡在
            // 这一刻的那轮轮询可能已经把它取回来了;不查重就会得到两行同 id,
            // ForEach 撞上重复的 Identifiable。
            if !aiGenerations.contains(where: { $0.id == gen.id }) {
                aiGenerations.insert(gen, at: 0)
            }
            await aiLoadStatus()
            // 带参考图的那条走的是修图接口,记录也就落在修图那半张表里,不会
            // 出现在这一页的「最近生成」下面。所以这句话得指路——否则用户会
            // 盯着本页等一张永远不来的图。
            announce(refs.isEmpty ? L.s.generate.submitted : L.s.generate.refSubmitted)
            aiPollStart()
        } catch {
            announce(aiMessage(error))
            // 402/429 说明额度的账本已经变了,把真实数字取回来。
            await aiLoadStatus()
        }
    }

    /// 把某条记录的描述放回输入框。失败重来、或在一句上反复微调,都靠它。
    func aiReuse(_ gen: AIGeneration) {
        aiPrompt = gen.prompt
        if aiSizes.contains(gen.size) { aiSize = gen.size }
        if aiResolutions.contains(gen.resolution) { aiResolution = gen.resolution }
    }

    // MARK: - 轮询

    /// 每三秒问一次,直到没有在途记录。
    ///
    /// 轮询而不是等推送:后端自己也是轮上游的,没有可订阅的通道。上限兜住的
    /// 是「服务器加了一个客户端不认识的状态」这种情况——未知状态按在途处理
    /// (见 AIGenStatus 的解码),没有上限就会一直转下去。
    func aiPollStart() {
        // `aiViewVisible` 而不只是「没有别的轮询在跑」:提交是异步的,点完
        // 「生成」立刻切走时,这一句在 onDisappear 之后才执行——只看 nil 的话
        // 会起一轮没人看的循环,一直问到出图为止。
        guard aiViewVisible, aiPollTask == nil else { return }
        aiPollTask = Task { [weak self] in
            var rounds = 0
            while !Task.isCancelled, rounds < 200 {
                rounds += 1
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self, connected, aiEnabled, aiViewVisible
                else { break }
                await aiRefresh()
                if !aiPending { break }
            }
            // 只有「自己跑完的」才交还这个句柄。被 aiPollStop 取消的那个醒来
            // 时,句柄可能已经指向新起的一轮——照清不误会把新任务的引用抹掉,
            // 于是下一次 aiPollStart 又能起一个,两个循环同时在问服务器。
            if !Task.isCancelled { self?.aiPollTask = nil }
        }
    }

    func aiPollStop() {
        aiPollTask?.cancel()
        aiPollTask = nil
    }

    /// 换服务器或退出登录时清空。历史与额度都属于那个账号,留着会在下一个
    /// 账号登录后短暂显示别人的记录。
    func aiReset() {
        aiPollStop()
        aiStatus = nil
        aiGenerations = []
        aiImages = [:]
        aiSubmitting = false
        retouchReset()
    }

    // MARK: - 文案

    /// 提交失败的措辞走自己这份 i18n。
    ///
    /// Kit 里那几个 `errorDescription` 是中文的兜底,而这一页的三种「不能生
    /// 成」——没开、今天用完、这个月用完——恰恰是最需要说准的地方:后两者
    /// 一个等明天、一个靠签到。
    func aiMessage(_ error: Error) -> String {
        guard let e = error as? AIGenError else { return message(error) }
        return switch e {
        case .disabled: L.s.generate.errDisabled
        case .notVerified: L.s.generate.errNotVerified
        case .dailyLimit: L.s.generate.errDailyLimit
        case .monthlyExhausted: L.s.generate.errMonthlyExhausted
        case .badPrompt: L.s.generate.errBadPrompt(aiPromptLimit)
        // 这两种只可能来自修图那条路,措辞也归它:一个是没选图,一个是选中的
        // 原图已经被删了,两句都要指向「回去选图」而不是「稍后重试」。
        case .noSource: L.s.retouch.errNoSource
        case .sourceMissing: L.s.retouch.errSourceMissing
        case .upstream(let m): L.s.generate.errUpstream(m)
        case .other: e.errorDescription ?? L.s.common.failed
        }
    }
}
