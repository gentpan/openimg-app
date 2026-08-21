import AppKit
import CryptoKit
import Foundation
import OpenimgKit

/// 装一份新版本。
///
/// 整条链上唯一把「远端的字节」变成「本机跑的代码」的地方,所以它的形状是围绕
/// **不可能装上没验过的东西**设计的,而不是围绕流程好写。
///
/// 地板是代码签名,不是清单签名。清单私钥泄露只能让攻击者指定下载地址;字节仍
/// 须过团队 ID + 公证 + 版本严格递增这一串,而那意味着他手上只有你自己发过的包。
enum UpdateInstaller {

    /// 验过的包。**只有 verify 能造出它,而 install 只收它。**
    ///
    /// 这不是洁癖:Sparkle 那条 high 级公告的形态正是「验的路径 ≠ 装的路径」。
    /// 把「验过」编码进类型,那种错就写不出来——没有 VerifiedBundle 就调不了
    /// install,而拿到 VerifiedBundle 就说明它是从 verify 出来的。
    struct VerifiedBundle {
        let url: URL
        let version: SemanticVersion
        fileprivate init(url: URL, version: SemanticVersion) {
            self.url = url
            self.version = version
        }
    }

    enum Failure: LocalizedError {
        case notInApplications
        case translocated
        case sizeMismatch(Int, Int)
        case digestMismatch
        case unpackFailed(String)
        case notExactlyOneApp(Int)
        case signature(String)
        case identifierMismatch(String)
        case notNewer(String)
        case replaceFailed(String)

        var errorDescription: String? {
            switch self {
            case .notInApplications:
                "只能更新装在「应用程序」里的副本。请先把 App 拖进「应用程序」。"
            case .translocated:
                "App 正运行在系统的只读隔离路径上，无法自我更新。请把它拖进「应用程序」后重开。"
            case .sizeMismatch(let got, let want):
                "下载大小不符（\(got) ≠ \(want)）"
            case .digestMismatch:
                "下载内容的校验和与更新清单不符"
            case .unpackFailed(let why):
                "解压失败：\(why)"
            case .notExactlyOneApp(let n):
                "压缩包里有 \(n) 个 App，预期恰好 1 个"
            case .signature(let why):
                "签名校验未通过：\(why)"
            case .identifierMismatch(let id):
                "包的标识符不是本应用（\(id)）"
            case .notNewer(let v):
                "包里的版本 \(v) 不比当前版本新"
            case .replaceFailed(let why):
                "替换失败：\(why)"
            }
        }
    }

    // MARK: - 下载

    /// 下载并校验大小与摘要。返回落地的 zip。
    static func download(_ release: UpdateManifest.Release,
                         progress: @Sendable @escaping (Double) -> Void) async throws -> URL {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForResource = 600
        let session = URLSession(configuration: cfg)

        let watcher = ProgressWatcher(onProgress: progress)
        let (tmp, resp) = try await session.download(from: release.url, delegate: watcher)
        defer { try? FileManager.default.removeItem(at: tmp) }

        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.unpackFailed("服务器返回 \(http.statusCode)")
        }

        let data = try Data(contentsOf: tmp)
        guard data.count == release.size else {
            throw Failure.sizeMismatch(data.count, release.size)
        }
        // 摘要用**读回来的字节**算,不是用下载过程中累计的——中间任何一步动过
        // 手脚,这里都对不上。
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest.caseInsensitiveCompare(release.sha256) == .orderedSame else {
            throw Failure.digestMismatch
        }

        let keep = FileManager.default.temporaryDirectory
            .appendingPathComponent("openimg-update-\(UUID().uuidString).zip")
        try data.write(to: keep)
        return keep
    }

    // MARK: - 解压与验证

    /// 解压、验签、防降级。全过才给出 VerifiedBundle。
    ///
    /// 顺序是有讲究的:先解压到一个**新建的空目录**,再数 app 个数,最后才验签
    /// ——反过来的话,一个塞了两个 app 的包可能验了 A 装了 B。
    static func verify(zip: URL, expecting release: UpdateManifest.Release,
                       localBuild: Int) throws -> VerifiedBundle {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appendingPathComponent("openimg-unpack-\(UUID().uuidString)")
        // 必须是新建的空目录:往已有目录里解压,"恰好一个 app"这条判断就失效了。
        try fm.createDirectory(at: dir, withIntermediateDirectories: false)

        // ditto 而不是 unzip:实测它会把路径穿越夹在目标目录内,并把符号链接降级
        // 成普通文件后中止。**退出码必须查**——不查的话解压失败会一路走到"目录
        // 里没有 app",报出来的原因和真实原因无关。
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, dir.path]
        let err = Pipe()
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? ""
            throw Failure.unpackFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // 只看顶层。恶意 zip 能造出**兄弟目录**,"递归扫一遍找 .app"的写法会被
        // 绕过——找到的那个未必是解压出来的主体。
        let tops = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let apps = tops.filter { $0.pathExtension == "app" }
        guard apps.count == 1, let app = apps.first else {
            throw Failure.notExactlyOneApp(apps.count)
        }

        try checkSignature(app)
        try checkNotDowngrade(app, expecting: release, localBuild: localBuild)
        return VerifiedBundle(url: app, version: release.version)
    }

    /// 代码签名 + 公证。整个模型的地板就是这一条要求串。
    ///
    /// `anchor apple generic` 单独毫无意义——任何交了年费的开发者都满足它。
    /// **必须钉 subject.OU**(团队号),否则谁都能签一个包给你装上。
    ///
    /// 公证校验恒开,绝不因离线降级:装订的票据没有被代码签名封住(实测把它覆盖
    /// 成 1 字节,codesign --verify --deep --strict 照样返回 0),所以它不能当
    /// "离线时的兜底",它是可伪造的。用户离线时不更新的代价是零。
    private static func checkSignature(_ app: URL) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess,
              let code else {
            throw Failure.signature("读不出签名")
        }
        let text = """
            anchor apple generic \
            and identifier "io.openimg.mac" \
            and certificate leaf[subject.OU] = "WPDUNPG5N8" \
            and notarized
            """
        var req: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &req) == errSecSuccess,
              let req else {
            throw Failure.signature("要求串无效")
        }
        var cfErr: Unmanaged<CFError>?
        let status = SecStaticCodeCheckValidityWithErrors(
            code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), req, &cfErr)
        guard status == errSecSuccess else {
            let why = cfErr?.takeRetainedValue().localizedDescription ?? "OSStatus \(status)"
            throw Failure.signature(why)
        }
    }

    /// 防降级。读的是**包自己的 Info.plist**,不是清单声称的版本。
    ///
    /// 清单可以被改,这份 plist 改不了——改了签名就挂(实测四种改法:往
    /// Contents/ 加文件、往 Resources/ 加文件、改图标一个字节、改描述文件一个
    /// 字节,全部报 "a sealed resource is missing or invalid")。
    private static func checkNotDowngrade(_ app: URL,
                                          expecting release: UpdateManifest.Release,
                                          localBuild: Int) throws {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let d = NSDictionary(contentsOf: plist) as? [String: Any] else {
            throw Failure.identifierMismatch("读不出 Info.plist")
        }
        let id = d["CFBundleIdentifier"] as? String ?? ""
        guard id == "io.openimg.mac" else { throw Failure.identifierMismatch(id) }

        let shortVersion = d["CFBundleShortVersionString"] as? String ?? ""
        let build = Int(d["CFBundleVersion"] as? String ?? "") ?? -1
        guard let v = SemanticVersion(shortVersion) else {
            throw Failure.notNewer(shortVersion)
        }
        // 三条都要:版本号严格大于、build 严格大于、且与清单声称的一致。第三条
        // 挡的是"清单说 0.4.0、包里其实是 0.3.1"这种偷梁换柱。
        guard v == release.version, build == release.build else {
            throw Failure.notNewer("\(shortVersion) (\(build))")
        }
        guard build > localBuild else {
            throw Failure.notNewer("\(shortVersion) (\(build))")
        }
    }

    // MARK: - 替换与重启

    /// 当前这份 app 能不能自我更新。
    ///
    /// 两种不能:被 translocate(系统把下载来的 app 挂到只读随机路径上跑,它连
    /// 自己在哪都不知道),以及不在「应用程序」里(可能在 DMG 上、在下载文件夹
    /// 里,替换了也不是用户以为的那一份)。
    static func selfCheck() throws {
        let me = Bundle.main.bundleURL
        let path = me.path
        // translocation 的路径形如 /private/var/folders/.../AppTranslocation/...
        if path.contains("/AppTranslocation/") {
            throw Failure.translocated
        }
        guard path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/") else {
            throw Failure.notInApplications
        }
    }

    /// 用验过的那份换掉正在跑的这份,然后重启。
    ///
    /// renamex_np + RENAME_SWAP:两个路径**原子交换**。先删后拷的话,中间存在
    /// 一个"旧的没了、新的还没到位"的窗口——那一刻断电或崩溃,用户就没有 app
    /// 了。交换则要么全成要么全不成,失败时旧的原封不动。
    ///
    /// 交换后旧版本落在临时路径上,顺手删掉;删失败也不算失败——新版已经就位,
    /// 为了一份残留的旧包去报错是本末倒置。
    static func install(_ bundle: VerifiedBundle) throws {
        try selfCheck()
        let me = Bundle.main.bundleURL
        let fm = FileManager.default

        // 先把新包挪到同一个卷上。跨卷 rename 不成立,而临时目录经常在别的卷。
        let staged = me.deletingLastPathComponent()
            .appendingPathComponent(".openimg-staged-\(UUID().uuidString).app")
        try fm.copyItem(at: bundle.url, to: staged)

        let ok = staged.withUnsafeFileSystemRepresentation { newPath in
            me.withUnsafeFileSystemRepresentation { oldPath in
                renamex_np(newPath!, oldPath!, UInt32(RENAME_SWAP))
            }
        }
        guard ok == 0 else {
            try? fm.removeItem(at: staged)
            throw Failure.replaceFailed(String(cString: strerror(errno)))
        }
        // 交换之后,staged 这个路径上是**旧**版本。
        try? fm.removeItem(at: staged)
    }

    /// 重开自己。
    ///
    /// 用 open -n 起一个新实例再退出当前进程,而不是原地 exec:正在跑的可执行
    /// 文件刚被换掉,exec 的语义在那一刻是没定义的。中间隔一个 open 让 launchd
    /// 去接手,是唯一可靠的做法。
    @MainActor
    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-n", Bundle.main.bundleURL.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    private final class ProgressWatcher: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        private let onProgress: @Sendable (Double) -> Void
        init(onProgress: @escaping @Sendable (Double) -> Void) { self.onProgress = onProgress }
        func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask,
                        didWriteData _: Int64, totalBytesWritten w: Int64,
                        totalBytesExpectedToWrite e: Int64) {
            guard e > 0 else { return }
            onProgress(min(1, Double(w) / Double(e)))
        }
        func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask,
                        didFinishDownloadingTo _: URL) {}
    }
}
