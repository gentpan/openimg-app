import Foundation
import OpenimgKit

/// 检查更新这件事的全部状态。
///
/// 这一版只负责**发现并告知**,不下载、不安装。用户点「查看发布说明」会跳浏览
/// 器去 GitHub,自己下载、拖进「应用程序」。
///
/// 不做自动安装是一个刻意的分期:发现这一段零下载、零提权面、纯逻辑全被自检
/// 覆盖,却已经拿到了自动更新绝大部分的实际价值——用户知道有新版了。而下载+替
/// 换那一段要正面处理替换正在运行的 app、权限、回滚,是另一个量级的风险。
@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(at: Date)
        case available(UpdateManifest.Release, stale: Int?, urgent: Bool)
        case blocked(UpdateVerdict.BlockedReason, latest: SemanticVersion)
        case failed(String)
        /// 正在下载,0…1。
        case downloading(UpdateManifest.Release, Double)
        /// 已就位,等用户点「立即重开」。
        ///
        /// 不自动重启:用户可能正传着图、正编辑着。安装完成与重启分成两步,是把
        /// "什么时候打断我"这个决定留给他。
        case installed(SemanticVersion)
    }

    @Published private(set) var state: State = .idle

    /// 侧栏上那个小圆点亮不亮。
    var hasUpdate: Bool {
        if case .available = state { return true }
        return false
    }

    private let feed: UpdateFeed
    /// 见过的最大 seq,挡重放。落 UserDefaults —— 它必须跨启动保留,否则重启一次
    /// 就把这道闸清零了。
    private static let seqKey = "update.highestSeenSeq"
    private static let lastCheckKey = "update.lastCheckedAt"
    /// 一天查一次就够。装了 app 的人不会一小时看一次有没有新版,而更频繁的检查
    /// 只是在给自己的服务器加无谓的请求。
    private static let interval: TimeInterval = 24 * 3600

    init(feed: UpdateFeed = UpdateFeed()) { self.feed = feed }

    /// 启动时调。距上次检查不足一天就什么都不做——包括不改 state,免得界面上
    /// 那行字在每次启动时闪一下。
    func checkIfDue() async {
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        if let last, Date().timeIntervalSince(last) < Self.interval { return }
        await check()
    }

    /// 下载 → 验证 → 替换。成功后停在 .installed 等用户点重开。
    ///
    /// 每一步失败都停在 .failed 并说清原因,不"尽力而为"地继续——这条链的每一
    /// 环都是安全边界,跳过任何一环都等于把它整个作废。
    func downloadAndInstall(_ release: UpdateManifest.Release, localBuild: Int) async {
        // 先问能不能装,再下载。装不了的话,下 8 MB 再告诉用户"其实装不了"是在
        // 浪费他的时间和流量。
        do {
            try UpdateInstaller.selfCheck()
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription
                            ?? error.localizedDescription)
            return
        }

        state = .downloading(release, 0)
        do {
            let zip = try await UpdateInstaller.download(release) { [weak self] p in
                Task { @MainActor in
                    guard let self, case .downloading = self.state else { return }
                    self.state = .downloading(release, p)
                }
            }
            defer { try? FileManager.default.removeItem(at: zip) }
            let verified = try UpdateInstaller.verify(zip: zip, expecting: release,
                                                      localBuild: localBuild)
            try UpdateInstaller.install(verified)
            state = .installed(release.version)
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription
                            ?? error.localizedDescription)
        }
    }

    /// 用户主动点「检查更新」时调,不看间隔。
    func check() async {
        state = .checking
        do {
            let m = try await feed.fetch()
            let seen = UserDefaults.standard.integer(forKey: Self.seqKey)
            guard let out = UpdatePolicy.evaluate(
                manifest: m,
                local: AppVersion.semantic ?? SemanticVersion(major: 0, minor: 0, patch: 0),
                localBuild: AppVersion.build,
                system: Self.systemVersion,
                arch: Self.arch,
                now: Date(),
                highestSeenSeq: seen
            ) else {
                // 清单的 seq 不比见过的大 —— 可能是重放,也可能只是 CDN 给了一份
                // 缓存。两者从这里分不开,所以不报错也不改结论,当作"这次没查到
                // 新东西"。
                state = .upToDate(at: Date())
                markChecked()
                return
            }

            // seq 只在采信之后才往上抬。抬早了的话,一份被拒的清单也会把闸门推高。
            UserDefaults.standard.set(m.seq, forKey: Self.seqKey)
            markChecked()

            switch out.verdict {
            case .upToDate:
                state = .upToDate(at: Date())
            case .available(let r):
                state = .available(r, stale: out.staleDays, urgent: out.belowRevoked)
            case .blocked(let why, let latest):
                state = .blocked(why, latest: latest)
            }
        } catch {
            // 检查更新失败不该打扰人:它是后台的、可选的。只把话留在设置页那一行。
            state = .failed(error.localizedDescription)
        }
    }

    private func markChecked() {
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
    }

    private static var systemVersion: SemanticVersion {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return SemanticVersion(major: v.majorVersion, minor: v.minorVersion, patch: v.patchVersion)
    }

    /// 编译期常量而不是运行时探测:`uname` 在 Rosetta 下会报 x86_64,而我们要问
    /// 的是"这个二进制是什么架构",不是"CPU 现在装成什么样"。
    private static var arch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
}
