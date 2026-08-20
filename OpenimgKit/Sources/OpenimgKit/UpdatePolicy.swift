import Foundation

/// 一次检查的结论。
public enum UpdateVerdict: Equatable, Sendable {
    /// 已经是最新的。
    case upToDate
    /// 有新版本。
    case available(UpdateManifest.Release)
    /// 清单本身没问题,但这台机器装不了这一版(系统太旧、或架构不符)。
    ///
    /// 单列一条而不是并进 upToDate:用户在别处看到有新版、而 app 说"已是最新",
    /// 会以为检查坏了。说清"有,但你这台装不了"才是实话。
    case blocked(reason: BlockedReason, latest: SemanticVersion)

    public enum BlockedReason: Equatable, Sendable {
        case systemTooOld(needs: SemanticVersion)
        case wrongArch(needs: String)
    }
}

/// 一次检查的完整结果:结论,加上一些不影响结论、但要在界面上说的旁注。
public struct UpdateOutcome: Equatable, Sendable {
    public let verdict: UpdateVerdict
    /// 清单已经过期多少天。nil 表示没过期。
    ///
    /// **过期是警告,不是闸门。** 做成闸门的话,想在到期前续期就必须重签清单,
    /// 重签就要换 seq —— 于是"不发版就无法续期",而三个月不发版正是最可能发生
    /// 的情况。所以过期时照常给结论,只是附一句"这份清单有点旧了"。
    public let staleDays: Int?
    /// 本机版本低于清单里的 revokedBelow,建议尽快升。只是提示,不能强制。
    public let belowRevoked: Bool
}

public enum UpdatePolicy {
    /// 拿清单和本机情况比出一个结论。纯函数,不碰网络也不碰磁盘。
    ///
    /// - Parameters:
    ///   - local: 本机版本。
    ///   - localBuild: 本机 build 号。与版本号一起比,两个都要严格大于才算新版
    ///     —— 版本号是人写的,build 号是算出来的,两者不一致时说明发版流程出过
    ///     岔子,那种时候不该自动往前走。
    ///   - system: 本机 macOS 版本。
    ///   - arch: 本机架构,如 "arm64"。
    ///   - now: 注入而不是取当前时间,否则这套逻辑测不了。
    ///   - highestSeenSeq: 本机见过的最大 seq。低于或等于它的清单是重放。
    public static func evaluate(
        manifest: UpdateManifest,
        local: SemanticVersion,
        localBuild: Int,
        system: SemanticVersion,
        arch: String,
        now: Date,
        highestSeenSeq: Int
    ) -> UpdateOutcome? {
        // 重放:见过更新的清单之后,旧的一律不认。返回 nil 表示"这份清单不该被
        // 采信",与"没有更新"是两回事。
        guard manifest.seq > highestSeenSeq else { return nil }

        let stale: Int? = {
            guard now > manifest.expiresAt else { return nil }
            return max(1, Int(now.timeIntervalSince(manifest.expiresAt) / 86400))
        }()
        let belowRevoked = manifest.revokedBelow.map { local < $0 } ?? false
        let r = manifest.latest

        func out(_ v: UpdateVerdict) -> UpdateOutcome {
            UpdateOutcome(verdict: v, staleDays: stale, belowRevoked: belowRevoked)
        }

        // 严格大于。相等不是更新——这条看着显然,但它正是降级防线的地板:
        // 少了它,一份声称 0.3.0 的清单会让 0.3.0 的用户反复"更新"到自己。
        guard r.version > local, r.build > localBuild else { return out(.upToDate) }

        guard arch == r.arch else {
            return out(.blocked(reason: .wrongArch(needs: r.arch), latest: r.version))
        }
        guard system >= r.minimumSystemVersion else {
            return out(.blocked(reason: .systemTooOld(needs: r.minimumSystemVersion),
                                latest: r.version))
        }
        return out(.available(r))
    }
}
