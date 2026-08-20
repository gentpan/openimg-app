import Foundation

/// 存储位置的种类。
public enum StorageKind: String, Sendable, Equatable, Hashable {
    case platform, r2, s3, b2, spaces, oss, cos, custom, removed

    /// 后端的取值是 `platform` / `user_r2` / `user_s3` / `unknown`，**不是**
    /// `r2` / `s3`。设置页曾经只认后两个，于是绑了 R2 的用户看到的是原样打印
    /// 的 `user_r2` —— 不报错、不留痕，只是显示得不对。
    ///
    /// 所有非 R2 的自有桶后端一律记成 `user_s3`（B2、Spaces、OSS、COS 都在里
    /// 面），所以再用 endpoint 细分一次，界面说的才是用户实际在用的那家。
    public static func parse(_ raw: String, endpoint: String = "") -> StorageKind {
        switch raw {
        case "platform": return .platform
        case "user_r2": return .r2
        case "user_s3":
            switch StorageProfileInput.describeEndpoint(endpoint) {
            case .r2: return .r2
            case .b2: return .b2
            case .spaces: return .spaces
            case .oss: return .oss
            case .cos: return .cos
            case .s3, .custom: return .s3
            case .none: return .s3
            }
        // 位置删了但图还在时后端回 "unknown"。
        default: return .removed
        }
    }

    /// 界面上那枚小徽章。平台池不需要 —— 它的名字已经说明一切。
    public var badge: String? {
        switch self {
        case .platform, .removed: nil
        case .r2: "R2"
        case .s3: "S3"
        case .b2: "B2"
        case .spaces: "Spaces"
        case .oss: "OSS"
        case .cos: "COS"
        case .custom: "S3"
        }
    }
}

/// 一个存储位置此刻的健康状况。
public enum StorageHealth: Sendable, Equatable {
    case ok
    /// 探针失败,而且它是默认位置 —— 新上传已经回落到平台池了。
    ///
    /// 与 `failing` 分开,因为用户要做的事不同:回落意味着"图还在传,只是没进你
    /// 的桶",而 failing 只是"这个桶连不上"。
    case fallenBack(String?)
    case failing(String?)
    /// 位置已经删了,但历史图片的字节还记在它名下。
    case removed
}

/// 概览页那张卡里的一行。
public struct StorageSlot: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let kind: StorageKind
    public let isDefault: Bool
    public let bytes: Int64
    public let images: Int
    public let health: StorageHealth
    /// 挂在这个位置下面的备份桶个数。备份桶不单独成行 —— 它不是"图存在哪",
    /// 是"图还多存了一份"。
    public let mirrors: Int

    public var share: Double = 0
}

public enum StorageOverview {
    /// 把两个来源合成界面要的那几行。
    ///
    /// 两个来源各自缺一块,所以必须合:
    ///
    ///   - `profiles`(GET /api/storage/profiles)有名字、类型、是否默认、连通
    ///     状态,字节数是后端现算的 GROUP BY,是实数不是估计;
    ///   - `byProfile`(存储统计)多覆盖两种孤儿:**桶已经删了但字节还在**、
    ///     以及 **profile_id 为空的历史图**。
    ///
    /// 三条容易写错的合并规则:
    ///
    ///   1. 后端在没有平台 profile 行时,会把 `profile_id` 为空的图归为平台并
    ///      发一个**全零 UUID**。按 id 直接合并会画出两行「平台存储」。
    ///   2. 两个来源同 id 时字节取 `profiles` 那份,**不相加** —— 它们说的是
    ///      同一批字节。
    ///   3. 备份桶(`backupOfID != nil`)不成行,只在父行上记一个数;父行不存在
    ///      的孤儿备份桶直接丢弃,列出来只会让人以为图存在那儿。
    public static func slots(profiles: [StorageProfile],
                             byProfile: [StorageSummarySlice]) -> [StorageSlot] {
        // 备份桶先摘出去。
        var mirrorCount: [String: Int] = [:]
        var primary: [StorageProfile] = []
        for p in profiles {
            if let parent = p.backupOfID, !parent.isEmpty {
                mirrorCount[parent, default: 0] += 1
            } else {
                primary.append(p)
            }
        }

        var rows: [StorageSlot] = []
        var used = Set<String>()

        for p in primary {
            let kind = StorageKind.parse(p.kind, endpoint: p.endpoint)
            var bytes = p.storedBytes
            var images = Int(p.imageCount)
            used.insert(p.id)

            // 平台行要顺带吃掉那些孤儿切片(全零 UUID,或 kind 是 platform 但
            // id 对不上任何 profile 的)。
            if kind == .platform {
                for s in byProfile where s.id != p.id && isOrphanPlatform(s, knownIDs: profiles) {
                    bytes += s.bytes
                    images += s.images
                    used.insert(s.id)
                }
            }

            rows.append(StorageSlot(
                id: p.id, name: p.name, kind: kind, isDefault: p.isDefault,
                bytes: bytes, images: images,
                health: health(of: p), mirrors: mirrorCount[p.id] ?? 0))
        }

        // 剩下的切片:位置已经删了,字节还在。
        for s in byProfile where !used.contains(s.id) {
            let kind = StorageKind.parse(s.kind)
            // 孤儿平台切片在上面已经并进平台行了;这里若还剩,说明压根没有平台
            // profile —— 那就让它自己成一行,总量才对得上。
            rows.append(StorageSlot(
                id: s.id, name: s.name, kind: kind, isDefault: false,
                bytes: s.bytes, images: s.images,
                health: kind == .platform ? .ok : .removed, mirrors: 0))
        }

        // 排序:默认置顶 → 自有桶按字节降序 → 平台池 → 已移除。
        //
        // 默认置顶是因为它回答的是"我下一张图会存到哪",而那是这张卡最常被问
        // 的一件事。
        rows.sort { a, b in
            if a.isDefault != b.isDefault { return a.isDefault }
            let ra = rank(a.kind), rb = rank(b.kind)
            if ra != rb { return ra < rb }
            return a.bytes > b.bytes
        }

        // 占比。总量为 0 时全给 0 而不是 NaN —— NaN 传进 SwiftUI 的宽度会让
        // 整行不渲染,而那看着像卡片坏了。
        let total = rows.reduce(Int64(0)) { $0 + max(0, $1.bytes) }
        guard total > 0 else { return rows }
        return rows.map {
            var s = $0
            s.share = Double(max(0, $0.bytes)) / Double(total)
            return s
        }
    }

    private static func rank(_ k: StorageKind) -> Int {
        switch k {
        case .removed: 2
        case .platform: 1
        default: 0
        }
    }

    private static func health(of p: StorageProfile) -> StorageHealth {
        guard p.status == "invalid" else { return .ok }
        // 默认位置探针失败意味着新上传已经回落到平台池了。这跟"某个非默认的桶
        // 连不上"是两件事,用户要做的处置也不同。
        return p.isDefault ? .fallenBack(p.lastError) : .failing(p.lastError)
    }

    /// 一个切片是不是"该并进平台行"的孤儿。
    ///
    /// 后端在没有平台 profile 行时,把 profile_id 为空的图归为平台并发一个全零
    /// UUID。它不对应任何真实 profile,按 id 合并会多画一行。
    private static func isOrphanPlatform(_ s: StorageSummarySlice,
                                         knownIDs: [StorageProfile]) -> Bool {
        guard StorageKind.parse(s.kind) == .platform else { return false }
        return !knownIDs.contains { $0.id == s.id }
    }
}

/// `StorageSummary.ProfileSlice` 的别名,让这个文件不必依赖那个嵌套类型的全名。
public typealias StorageSummarySlice = StorageSummary.ProfileSlice
