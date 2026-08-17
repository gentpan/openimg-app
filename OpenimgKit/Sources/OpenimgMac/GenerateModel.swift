import Foundation
import OpenimgKit

/// 文生图的状态机。
///
/// 生成是异步的:提交只换回一条 pending 记录,图要等上游几十秒。所以这里的
/// 核心是一个轮询循环——每三秒问一次 `/api/ai/generations`,直到没有在途的
/// 记录为止,页面一消失就取消。没人看着的时候不该有请求在跑。
extension AppModel {

    // MARK: - 派生状态

    var aiEnabled: Bool { aiStatus?.enabled == true }

    /// 侧栏该显示哪几行。没配 APIMART_API_KEY 的部署里,「生成」不是灰的,
    /// 是不存在的——给一个点不动的入口等于承诺了一件做不到的事。
    var visibleSections: [Section_] {
        Section_.allCases.filter { $0 != .generate || aiEnabled }
    }

    var aiRemaining: Int { aiStatus?.remaining ?? 0 }

    /// 还有没有没跑完的记录。轮询的开关就看它。
    var aiPending: Bool { aiGenerations.contains { !$0.status.isTerminal } }

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
        aiEnabled && !aiSubmitting && aiRemaining > 0
            && aiPromptLength > 0 && !aiPromptTooLong
    }

    // MARK: - 加载

    func aiLoadStatus() async {
        guard connected, let c = try? client() else { return }
        // 静默失败:AI 是附加功能,一个坏掉的端点不该在登录成功时弹红条。
        guard let s = try? await c.aiStatus() else { return }
        aiStatus = s
        // 选择必须落在服务器给的合法值里,否则提交时会被静默改写成默认档,
        // 界面显示的和实际出的图对不上。
        if !s.sizes.isEmpty, !s.sizes.contains(aiSize) { aiSize = s.sizes[0] }
        if !s.resolutions.isEmpty, !s.resolutions.contains(aiResolution) {
            aiResolution = s.resolutions[0]
        }
        // 功能被关掉时(自建实例撤掉了 key),别把用户留在一个已经不存在的
        // 页面上。
        if !s.enabled, section == .generate { section = .overview }
    }

    /// 进入生成页。
    ///
    /// 可见性是轮询的总闸,所以第一件事就是把它立起来;`aiViewDisappeared`
    /// 负责放倒。
    func aiViewAppeared() async {
        aiViewVisible = true
        await aiLoadStatus()
        // 列表为空说明这是本会话头一回进来,那一刻看到的「已完成」全是历史,
        // 不该为它们弹提示。再次回到这一页时列表还留着上次的样子,谁是趁我
        // 不在时落地的一目了然——那些该照常提示、照常刷图库。
        await aiRefresh(settling: aiGenerations.isEmpty)
    }

    /// 离开生成页。没人看着的时候不该有请求在跑。
    func aiViewDisappeared() {
        aiViewVisible = false
        aiPollStop()
    }

    /// 拉一次历史。
    ///
    /// `settling` 为真表示这是本会话第一次加载:那一刻所有已完成的记录都
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
        if justFinished.contains(where: { $0.status == .completed }) {
            quota = try? await c.quota()
            // 与上传后一样刷新图库:那张图现在就在库里,列表停在旧的一页
            // 只会让人以为没存进去。
            await load(resetPage: true)
            announce(L.s.generate.doneToast)
        }
        if let failed = justFinished.first(where: { $0.status == .failed }) {
            announce(L.s.generate.failedToast(failed.error ?? L.s.common.failed), seconds: 8)
        }
    }

    // MARK: - 提交

    func aiGenerate() async {
        guard aiCanSubmit else { return }
        let prompt = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        aiSubmitting = true
        defer { aiSubmitting = false }
        do {
            let gen = try await client().aiGenerate(
                prompt: prompt, size: aiSize, resolution: aiResolution)
            // 先插到列表最前面,不等下一轮轮询——提交后一秒内什么都不变的
            // 界面看起来就像没提交成功。落库发生在响应回来之前,所以正好卡在
            // 这一刻的那轮轮询可能已经把它取回来了;不查重就会得到两行同 id,
            // ForEach 撞上重复的 Identifiable。
            if !aiGenerations.contains(where: { $0.id == gen.id }) {
                aiGenerations.insert(gen, at: 0)
            }
            await aiLoadStatus()
            announce(L.s.generate.submitted)
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
        case .upstream(let m): L.s.generate.errUpstream(m)
        case .other: e.errorDescription ?? L.s.common.failed
        }
    }
}
