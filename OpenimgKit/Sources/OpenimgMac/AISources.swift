import Foundation
import AppKit
import OpenimgKit

/// 那几张图放进谁的篮子。
///
/// 修图页的「原图」与生成页的「参考图」是同一件事——1~4 张图库里的图,提交
/// 时只发 id——所以选图、上传、翻页那一整套只写一份,由这个值决定写进哪个
/// 数组。做成枚举而不是给每页各来一套方法:两页迟早会在同一件事上长歪。
enum AISourceSlot: String, Identifiable, Sendable, CaseIterable {
    case retouch
    case generate

    var id: String { rawValue }
}

extension AppModel {

    // MARK: - 篮子

    /// 读某一页当前选中的图。
    func aiSources(_ slot: AISourceSlot) -> [RemoteImage] {
        switch slot {
        case .retouch: retouchSources
        case .generate: generateSources
        }
    }

    func aiSetSources(_ slot: AISourceSlot, _ images: [RemoteImage]) {
        switch slot {
        case .retouch: retouchSources = images
        case .generate: generateSources = images
        }
    }

    /// 上限两页共用 aiEditSourceLimit:两条路最终都进 `/api/ai/edit`,后端只
    /// 收 1~4 张,前端放宽只会换来一个 400。
    func aiCanAddSource(_ slot: AISourceSlot) -> Bool {
        aiSources(slot).count < aiEditSourceLimit
    }

    /// 某张图选没选中。选图面板按它画勾。
    func aiIsPicked(_ img: RemoteImage, in slot: AISourceSlot) -> Bool {
        aiSources(slot).contains { $0.id == img.id }
    }

    /// 点一下选中,再点一下取消。
    ///
    /// 满了还点新的:不静默吞掉,也不悄悄挤掉第一张——用户看不见被换掉的是
    /// 哪张。说一句「先取消一张」,把决定权留给他。
    func aiToggleSource(_ img: RemoteImage, in slot: AISourceSlot) {
        var picked = aiSources(slot)
        if let i = picked.firstIndex(where: { $0.id == img.id }) {
            picked.remove(at: i)
            aiSetSources(slot, picked)
            return
        }
        guard aiCanAddSource(slot) else {
            announce(L.s.aiSource.limitReached(aiEditSourceLimit))
            return
        }
        picked.append(img)
        aiSetSources(slot, picked)
    }

    func aiRemoveSource(_ img: RemoteImage, in slot: AISourceSlot) {
        aiSetSources(slot, aiSources(slot).filter { $0.id != img.id })
    }

    /// 最近上传的若干张,供输入区一键取用。
    ///
    /// 借图库页当前那一页的 images 而不是另发一次请求:进这个页面之前图库
    /// 早就拉过了,为一条快捷入口再问服务器一遍不值当。已经选中的排除掉——
    /// 留着只会让人点了没反应(toggle 会把它移除,那是另一回事)。
    func aiRecent(_ slot: AISourceSlot) -> [RemoteImage] {
        let chosen = Set(aiSources(slot).map(\.id))
        return images.filter { !chosen.contains($0.id) }.prefix(10).map { $0 }
    }

    // MARK: - 选图面板

    /// 打开选图面板。
    ///
    /// 面板有自己那份图库快照,不借图库页的 `images`:借来搜索会把用户翻到
    /// 一半的位置和选中状态一并冲掉。
    func aiOpenPicker(_ slot: AISourceSlot) {
        aiPicking = slot
        // 先把图库页当前那一页摆上,面板一开就有东西看;真正的一页随后覆盖它。
        if aiLibrary.isEmpty { aiLibrary = images }
    }

    /// 选图面板一次拉多少张。
    ///
    /// 60 张够铺满两三屏,再多一次请求就慢得能看出来。翻页由
    /// aiLoadMoreLibrary 接着做——只拉这一页就不管的话,图多的账号在面板里
    /// 永远只看得到最近的 60 张,更早的图根本选不到。
    private static let aiLibraryPageSize = 60

    /// 拉第一页给选图面板用。搜索框每改一次就调一次(视图侧做去抖)。
    func aiLoadLibrary() async {
        guard connected, let c = try? client() else { return }
        aiLibraryLoading = true
        defer { aiLibraryLoading = false }
        let q = aiLibrarySearch.trimmingCharacters(in: .whitespaces)
        guard let page = try? await c.images(limit: Self.aiLibraryPageSize, offset: 0,
                                             query: q, sort: .newest)
        else { return }
        aiLibrary = page.images
        aiLibraryMore = page.images.count == Self.aiLibraryPageSize
    }

    /// 网格滚到底时接着拉下一页。
    ///
    /// 用已有条数当 offset 而不是记页码:搜索一变整个列表就重来,页码还得
    /// 单独复位,而条数天然跟着列表走。
    func aiLoadMoreLibrary() async {
        guard connected, aiLibraryMore, !aiLibraryLoading,
              let c = try? client() else { return }
        aiLibraryLoading = true
        defer { aiLibraryLoading = false }
        let q = aiLibrarySearch.trimmingCharacters(in: .whitespaces)
        let offset = aiLibrary.count
        guard let page = try? await c.images(limit: Self.aiLibraryPageSize, offset: offset,
                                             query: q, sort: .newest)
        else { return }
        // 去重:翻页期间有新图上传会让后一页与前一页重叠,不挡的话同一张图
        // 会在网格里出现两次,而它们的 id 相同,ForEach 会直接报重复。
        let have = Set(aiLibrary.map(\.id))
        aiLibrary.append(contentsOf: page.images.filter { !have.contains($0.id) })
        aiLibraryMore = page.images.count == Self.aiLibraryPageSize
    }

    // MARK: - 直接上传

    /// 「上传新图」的选文件入口。
    ///
    /// 只收文件不收文件夹:一个文件夹当参考图没有意义,而上传页那边收文件夹
    /// 是因为「整个拍摄目录」本来就是它的单位。
    func aiPickAndUploadSource(into slot: AISourceSlot) async {
        guard aiCanAddSource(slot), !aiSourceUploading else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        panel.message = L.s.errors.pickImages
        guard panel.runModal() == .OK else { return }
        await aiUploadSources(panel.urls, into: slot)
    }

    /// 传几张本地图,传完直接选中。
    ///
    /// 走的是 `upload(_:)` 这条**正常上传流水线**,不是给 AI 开的旁路:这些
    /// 字节存下来本来就是图床该干的事,而且只有进了库的图才有 id——
    /// `/api/ai/edit` 收的是 id,历史记录里「拿哪张改的」也是靠 id 指回去的。
    /// 把图编码成 base64 直接塞进请求,这两样都拿不到,还要让同一份字节在网上
    /// 多走一趟。
    ///
    /// 超出上限的部分**在上传之前**就砍掉:一次拖进十张,多传的七张既选不上
    /// 又实打实扣了配额,那是用户没要过的事。
    func aiUploadSources(_ urls: [URL], into slot: AISourceSlot) async {
        guard !aiSourceUploading else {
            announce(L.s.aiSource.uploadBusy)
            return
        }
        let room = aiEditSourceLimit - aiSources(slot).count
        guard room > 0 else {
            announce(L.s.aiSource.limitReached(aiEditSourceLimit))
            return
        }
        // 文件夹展开成里面的图,再按账号档位过滤——与拖到上传页同一套规则。
        let files = expand(urls).filter { isUploadable($0) }
        guard !files.isEmpty else {
            // 静默 return 会让人以为功能坏了:面板关掉、拖放被系统画成"接受了",
            // 然后什么都没发生。档位不支持某种格式是最常见的原因,得说出来。
            announce(L.s.aiSource.noUploadable)
            return
        }
        // 多出来的那几张不提示:紧接着的「已上传并选中 N 张」和行尾的 N / 4
        // 已经把话说完了,先弹一句「先取消一张」反而是句会被立刻盖掉的假话
        // ——毕竟这一次确实传成了几张。
        let batch = Array(files.prefix(room))

        aiSourceUploading = true
        defer { aiSourceUploading = false }
        NSLog("[openimg-ai] 开始上传 %d 张", batch.count)
        for f in batch {
            let sz = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            NSLog("[openimg-ai]   %@ (%d 字节, 可读=%@)", f.lastPathComponent, sz,
                  FileManager.default.isReadableFile(atPath: f.path) ? "是" : "否")
        }
        // 不复制链接:用户正在写提示词,剪贴板里多半是等会儿要粘的东西。
        //
        // 加超时:上传卡住时旋转指示器会一直转下去,用户看不出是慢还是死了。
        // 两分钟对几兆的图绰绰有余,超过就是出事了,该说话而不是继续转。
        let fresh = await withTimeout(seconds: 120) { [weak self] in
            await self?.upload(batch, copyLink: false) ?? []
        } ?? {
            NSLog("[openimg-ai] 上传超时(120s),请求没有返回")
            return []
        }()
        NSLog("[openimg-ai] 上传返回 %d 张", fresh.count)
        guard !fresh.isEmpty else {
            // upload 失败时已经播报了具体原因(配额、格式、令牌),这里只补一句
            // 「所以没有图被选中」——否则那一行静静地什么都没变,像是没点到。
            announce(L.s.aiSource.uploadFailed)
            return
        }
        // 去重命中会返回库里那张老图,可能正好是已经选中的那张;`aiToggleSource`
        // 遇到已选的会把它**移除**,所以这里不能用它。
        var picked = aiSources(slot)
        let have = Set(picked.map(\.id))
        for img in fresh where !have.contains(img.id) && picked.count < aiEditSourceLimit {
            picked.append(img)
        }
        aiSetSources(slot, picked)
        // 一张都没新增(传的正好是已经选着的那张,被去重认了出来):不说
        // 「已选中 0 张」这种废话,`upload` 自己那句「已上传」照旧站着。
        let added = picked.count - have.count
        if added > 0 { announce(L.s.aiSource.uploaded(added)) }
    }
}


/// 给一段异步工作加个上限。超时返回 nil,调用方自己决定怎么说。
///
/// 用在上传上:一个转个不停的指示器是最糟的失败方式——用户分不清是网慢还是
/// 已经死了,只能一直等下去。
@MainActor
func withTimeout<T: Sendable>(seconds: Double,
                              _ work: @escaping @Sendable () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await work() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
