import Foundation
import OpenimgKit

/// AI 修图的状态机。
///
/// 它是 GenerateModel 的姊妹,但只写了差异那一半:额度、历史、轮询全都在那
/// 边——同一张表、同一个额度池、同一个 `/api/ai/generations`,再起一个定时器
/// 只会让同一份数据被问两遍。这里管的是生成页没有的那件事:原图。
///
/// 原图选的是**图库里的图**而不是本地文件。那些图早就在图床上、有公开 CDN
/// 地址,后端直接把地址交给上游即可;走一遍「下载到本机 → 编码 → 传回去」
/// 只是白白多一趟几兆的往返。
extension AppModel {
    /// 清晰度的有效值:选过就用选的,没选或服务器撤掉了那一档就落回第一档。
    ///
    /// 不留空:它是计费档位,空值会让上游自己挑,而它可能挑最贵的 4k。界面
    /// 读的也是这个值,所以高亮的那一档就是真正会提交的那一档。
    var effectiveRetouchResolution: String {
        if aiResolutions.contains(retouchResolution) { return retouchResolution }
        return aiResolutions.first ?? "1k"
    }


    // MARK: - 派生状态

    var retouchPromptLength: Int {
        retouchPrompt.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
    }
    var retouchPromptTooLong: Bool { retouchPromptLength > aiPromptLimit }

    var retouchCanAddSource: Bool { retouchSources.count < aiEditSourceLimit }

    /// 最近上传的若干张,供输入区一键取用。
    ///
    /// 借图库页当前那一页的 images 而不是另发一次请求:进这个页面之前图库
    /// 早就拉过了,为一条快捷入口再问服务器一遍不值当。已经选中的排除掉——
    /// 留着只会让人点了没反应(toggle 会把它移除,那是另一回事)。
    var retouchRecent: [RemoteImage] {
        let chosen = Set(retouchSources.map(\.id))
        return images.filter { !chosen.contains($0.id) }.prefix(10).map { $0 }
    }

    var retouchCanSubmit: Bool {
        aiEnabled && !retouchSubmitting && aiRemaining > 0
            && !retouchSources.isEmpty
            && retouchPromptLength > 0 && !retouchPromptTooLong
    }

    /// 某张图选没选中。选图面板按它画勾。
    func retouchIsPicked(_ img: RemoteImage) -> Bool {
        retouchSources.contains { $0.id == img.id }
    }

    // MARK: - 选原图

    /// 点一下选中,再点一下取消。
    ///
    /// 满了还点新的:不静默吞掉,也不悄悄挤掉第一张——用户看不见被换掉的是
    /// 哪张。说一句「先取消一张」,把决定权留给他。
    func retouchToggleSource(_ img: RemoteImage) {
        if let i = retouchSources.firstIndex(where: { $0.id == img.id }) {
            retouchSources.remove(at: i)
            return
        }
        guard retouchCanAddSource else {
            announce(L.s.retouch.pickLimitReached(aiEditSourceLimit))
            return
        }
        retouchSources.append(img)
    }

    func retouchRemoveSource(_ img: RemoteImage) {
        retouchSources.removeAll { $0.id == img.id }
    }

    /// 打开选图面板。
    ///
    /// 面板有自己那份图库快照,不借图库页的 `images`:借来搜索会把用户翻到
    /// 一半的位置和选中状态一并冲掉。
    func retouchOpenPicker() {
        retouchPicking = true
        // 先把图库页当前那一页摆上,面板一开就有东西看;真正的一页随后覆盖它。
        if retouchLibrary.isEmpty { retouchLibrary = images }
    }

    /// 选图面板一次拉多少张。
    ///
    /// 60 张够铺满两三屏,再多一次请求就慢得能看出来。翻页由
    /// retouchLoadMoreLibrary 接着做——原来只拉这一页就不管了,图多的账号
    /// 在面板里永远只看得到最近的 60 张,更早的图根本选不到。
    private static let retouchPageSize = 60

    /// 拉第一页给选图面板用。搜索框每改一次就调一次(视图侧做去抖)。
    func retouchLoadLibrary() async {
        guard connected, let c = try? client() else { return }
        retouchLibraryLoading = true
        defer { retouchLibraryLoading = false }
        let q = retouchSearch.trimmingCharacters(in: .whitespaces)
        guard let page = try? await c.images(limit: Self.retouchPageSize, offset: 0,
                                             query: q, sort: .newest)
        else { return }
        retouchLibrary = page.images
        retouchLibraryMore = page.images.count == Self.retouchPageSize
    }

    /// 网格滚到底时接着拉下一页。
    ///
    /// 用已有条数当 offset 而不是记页码:搜索一变整个列表就重来,页码还得
    /// 单独复位,而条数天然跟着列表走。
    func retouchLoadMoreLibrary() async {
        guard connected, retouchLibraryMore, !retouchLibraryLoading,
              let c = try? client() else { return }
        retouchLibraryLoading = true
        defer { retouchLibraryLoading = false }
        let q = retouchSearch.trimmingCharacters(in: .whitespaces)
        let offset = retouchLibrary.count
        guard let page = try? await c.images(limit: Self.retouchPageSize, offset: offset,
                                             query: q, sort: .newest)
        else { return }
        // 去重:翻页期间有新图上传会让后一页与前一页重叠,不挡的话同一张图
        // 会在网格里出现两次,而它们的 id 相同,ForEach 会直接报重复。
        let have = Set(retouchLibrary.map(\.id))
        retouchLibrary.append(contentsOf: page.images.filter { !have.contains($0.id) })
        retouchLibraryMore = page.images.count == Self.retouchPageSize
    }

    // MARK: - 提交

    func retouchSubmit() async {
        guard retouchCanSubmit else { return }
        let prompt = retouchPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let sources = retouchSources
        retouchSubmitting = true
        defer { retouchSubmitting = false }
        do {
            let gen = try await client().aiEdit(
                prompt: prompt,
                imageIDs: sources.map(\.id),
                // size 空串是「跟随原图」:那时这个键整个不发,让上游按原图
                // 比例出图。清晰度没有这一档,理由见 effectiveRetouchResolution。
                size: retouchSize,
                resolution: effectiveRetouchResolution)
            // 原图先记进 aiImages,历史行才能立刻画出缩略图——响应里只有这条
            // 记录本身,而原图对象此刻就在手上,没有理由等下一轮轮询去取。
            for img in sources where aiImages[img.id] == nil { aiImages[img.id] = img }
            // 与生成同一个理由:落库发生在响应回来之前,正好卡在这一刻的那轮
            // 轮询可能已经把它取回来了,不查重就是两行同 id。
            if !aiGenerations.contains(where: { $0.id == gen.id }) {
                aiGenerations.insert(gen, at: 0)
            }
            await aiLoadStatus()
            announce(L.s.retouch.submitted)
            aiPollStart()
        } catch {
            announce(aiMessage(error))
            // 402/429 说明额度的账本已经变了,把真实数字取回来。
            await aiLoadStatus()
        }
    }

    /// 把某条记录整个放回上面:描述、原图、尺寸。改坏了重来、或在一句上反复
    /// 微调,都靠它。
    ///
    /// 原图从 `aiImages` 里取:那是这条记录**当时**用的图,可能早已翻出了图
    /// 库当前这一页。一张都取不到时不清空已选的——用户手上那几张比一条历史
    /// 记录更要紧。
    func retouchReuse(_ gen: AIGeneration) {
        retouchPrompt = gen.prompt
        let sources = gen.sourceIDs.compactMap { aiImages[$0] }
        if !sources.isEmpty { retouchSources = Array(sources.prefix(aiEditSourceLimit)) }
        retouchSize = aiSizes.contains(gen.size) ? gen.size : ""
        retouchResolution = aiResolutions.contains(gen.resolution) ? gen.resolution : ""
    }

    /// 换服务器或退出登录时清空。选中的原图属于那个账号的图库,留着会在下一
    /// 个账号登录后指向几张他看不见的图。
    func retouchReset() {
        retouchPrompt = ""
        retouchSources = []
        retouchLibrary = []
        retouchLibraryMore = true
        retouchSearch = ""
        retouchSubmitting = false
        retouchPicking = false
    }
}
