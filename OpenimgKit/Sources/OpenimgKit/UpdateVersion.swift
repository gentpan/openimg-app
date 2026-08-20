import Foundation

/// 语义化版本号,以及由它推出来的 build 号。
///
/// 放在 Kit 里而不是打包脚本里,是因为这个公式将来有两个读者:打包时要写进
/// `CFBundleVersion`,而客户端拿到更新清单之后要拿自己的 build 号和清单里的比。
/// 两处各写一遍的话,某天改了其中一处,表现是"明明有新版却检测不到",没有任何
/// 报错——而这正是纯逻辑该待在 Kit 里、由 KitCheck 盯住的理由。
public struct SemanticVersion: Equatable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// 预发布标识,如 `beta.1`。空表示正式版。
    public let prerelease: String

    public init(major: Int, minor: Int, patch: Int, prerelease: String = "") {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// 解析 `1.2.3` 或 `v1.2.3` 或 `1.2.3-beta.1`。
    ///
    /// 宽容地吃掉前导的 `v`:git tag 带 v、Info.plist 不带,而两边的字符串迟早
    /// 会在某处相遇。不宽容的地方是位数——`1.2` 直接判失败,而不是补一个 0:
    /// 补零意味着把一个写错的版本号悄悄接受下来。
    public init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        guard !s.isEmpty else { return nil }

        // 构建元数据(+ 之后的部分)按 semver 不参与比较,直接丢掉。
        if let plus = s.firstIndex(of: "+") { s = String(s[s.startIndex..<plus]) }

        var pre = ""
        if let dash = s.firstIndex(of: "-") {
            pre = String(s[s.index(after: dash)...])
            s = String(s[s.startIndex..<dash])
            guard !pre.isEmpty else { return nil }
        }

        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var nums: [Int] = []
        for p in parts {
            // 只认十进制数字。Int(" 1") 会成功,而那不该被当成合法版本号。
            guard !p.isEmpty, p.allSatisfy(\.isNumber), let n = Int(p), n >= 0 else { return nil }
            nums.append(n)
        }
        self.init(major: nums[0], minor: nums[1], patch: nums[2], prerelease: pre)
    }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.isEmpty ? core : "\(core)-\(prerelease)"
    }

    /// 按 semver 比较:数字段逐位比,有预发布标识的小于同号的正式版。
    public static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        if a.major != b.major { return a.major < b.major }
        if a.minor != b.minor { return a.minor < b.minor }
        if a.patch != b.patch { return a.patch < b.patch }
        // 1.0.0-beta < 1.0.0。两边都是预发布时按字典序——够用了,这个项目不会
        // 出到需要区分 beta.2 与 beta.10 的地步,真出到了会先被 KitCheck 提醒。
        if a.prerelease.isEmpty && b.prerelease.isEmpty { return false }
        if a.prerelease.isEmpty { return false }
        if b.prerelease.isEmpty { return true }
        return a.prerelease < b.prerelease
    }
}

extension SemanticVersion {
    /// `CFBundleVersion` 用的单调整数。
    ///
    /// 公式是 `(major × 1_000_000 + minor × 1_000 + patch) × 1_000 + 提交数`,
    /// 于是 0.3.0 → 3_000_000,0.3.1 → 3_001_000。留 1000 的余量而不是 100,是
    /// 因为 patch 号在修 bug 密集的一周里涨得比想象中快。
    ///
    /// 末尾那三位是**距最近一个 tag 的提交数**,让每次提交出来的包都有不同的
    /// build 号——不然两个 tag 之间的所有构建都叫「0.3.0 (3000)」,装上之后
    /// 根本分不清手里是哪一版。
    ///
    /// 发布版这一位恒为 0:release.sh 显式传版本号、不走 git 推断,而清单里的
    /// build 也是由版本号单独算出来的。两边必须落在同一个数上——否则装上去的
    /// 那一版会认为自己比清单还新,从此永远收不到更新,而且不报任何错。
    ///
    /// 乘 1000 而不是在原数上加:直接加的话 0.3.0 之后第 25 次提交是 3025,
    /// 而那正是版本 0.3.25 的号——两个完全不同的东西撞在同一个数上。
    ///
    /// 换标度不影响已经装出去的那些:旧号最大 999_999(0.999.999),新号最小
    /// 1_000(0.0.1),此后发布的每一版都比任何旧号大,单调性照旧成立。
    ///
    /// **预发布版没有 build 号。** 0.4.0-beta 和 0.4.0 的数字三元组相同,给它们
    /// 同一个 build 号会打破单调性,而 CFBundleVersion 的单调性正是系统用来判断
    /// "哪个更新"的依据。与其编一个能排序的规则,不如现在明确不支持——这个项目
    /// 还没发过预发布版,真要发时再设计,好过现在留一条没人验证过的路径。
    public func buildNumber(commitsSinceTag: Int = 0) -> Int? {
        guard prerelease.isEmpty else { return nil }
        guard minor < 1_000, patch < 1_000 else { return nil }
        guard (0..<1_000).contains(commitsSinceTag) else { return nil }
        return (major * 1_000_000 + minor * 1_000 + patch) * 1_000 + commitsSinceTag
    }
}
