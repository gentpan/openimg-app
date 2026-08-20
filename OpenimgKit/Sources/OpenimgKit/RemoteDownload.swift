import Foundation

public enum RemoteDownloadError: LocalizedError, Sendable {
    case badURL
    case http(Int)
    case tooLarge(Int64)
    case notAnImage(String?)
    case empty

    public var errorDescription: String? {
        switch self {
        case .badURL: "这不是一条能用的图片地址"
        case .http(let code): "服务器返回 \(code)"
        case .tooLarge(let cap): "文件超过 \(ByteCountFormatter.string(fromByteCount: cap, countStyle: .binary))"
        case .notAnImage(let ct): ct.map { "对方返回的不是图片（\($0)）" } ?? "对方返回的不是图片"
        case .empty: "下载到的内容是空的"
        }
    }
}

/// 从一条网址把图download下来,带进度。
///
/// 下载发生在**客户端**,不是让服务器去抓——服务器抓取意味着任何人都能让我们
/// 的机器去请求任意地址(内网、云元数据端点),那是要单独设计一层防护的东西。
/// 客户端下载没有这个问题:它请求的是用户自己机器能访问的地址。
public struct RemoteDownload: Sendable {
    public struct Progress: Sendable {
        public let received: Int64
        /// 对方没给 Content-Length 时是 -1。界面上要按"未知总量"处理,不能拿
        /// 它做分母——除以 -1 得到的进度条会往回走。
        public let total: Int64
        public var fraction: Double? {
            guard total > 0 else { return nil }
            return min(1, max(0, Double(received) / Double(total)))
        }
    }

    /// 下到 `dir` 里,返回落地的文件。
    ///
    /// - Parameter maxBytes: 0 表示不限。对方给了 Content-Length 就先按它拦一
    ///   次——没必要为了发现"太大了"先把 2 GB 拉完。
    public static func fetch(
        _ url: URL,
        into dir: URL,
        maxBytes: Int64 = 0,
        session: URLSession? = nil,
        onProgress: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw RemoteDownloadError.badURL
        }

        let s = session ?? {
            let c = URLSessionConfiguration.ephemeral
            c.requestCachePolicy = .reloadIgnoringLocalCacheData
            c.timeoutIntervalForRequest = 30
            c.timeoutIntervalForResource = 300
            return URLSession(configuration: c)
        }()

        var req = URLRequest(url: url)
        req.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let watcher = Watcher(cap: maxBytes, onProgress: onProgress)
        let (temp, resp) = try await s.download(for: req, delegate: watcher)
        // 系统给的临时文件在函数返回后会被回收,所以无论成败都要先接管它。
        defer { try? FileManager.default.removeItem(at: temp) }

        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RemoteDownloadError.http(http.statusCode)
        }
        if let hit = watcher.capHit { throw RemoteDownloadError.tooLarge(hit) }

        let size = (try? temp.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0 else { throw RemoteDownloadError.empty }
        if maxBytes > 0, Int64(size) > maxBytes { throw RemoteDownloadError.tooLarge(maxBytes) }

        // 认字节头再定文件名。**先读文件头再命名**:本地那道格式校验只看扩展
        // 名,而很多 CDN 地址根本没有扩展名,靠 Content-Type 又常常是
        // application/octet-stream。
        let head = (try? FileHandle(forReadingFrom: temp)).map { h -> Data in
            defer { try? h.close() }
            return (try? h.read(upToCount: 32)) ?? Data()
        } ?? Data()
        let ct = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
        guard RemoteImageURL.imageExtension(magic: head) != nil
                || RemoteImageURL.imageExtension(contentType: ct) != nil else {
            throw RemoteDownloadError.notAnImage(ct)
        }

        let name = RemoteImageURL.filename(for: url, contentType: ct, magic: head)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var dest = dir.appendingPathComponent(name)
        // 同名再来一次不该覆盖上一张——那一张可能正排在上传队列里。
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            let stem = dest.deletingPathExtension().lastPathComponent
            let ext = dest.pathExtension
            let next = ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)"
            dest = dir.appendingPathComponent(next)
            n += 1
        }
        try FileManager.default.moveItem(at: temp, to: dest)
        return dest
    }

    /// 进度回调 + 超限拦截。
    ///
    /// URLSession 的 per-task delegate 在自己的队列上被调用,所以它不是主 actor
    /// 隔离的;`capHit` 只在这一条队列上写、在下载结束之后读,`@unchecked` 是
    /// 就事论事的,不是图省事。
    private final class Watcher: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        private let cap: Int64
        private let onProgress: @Sendable (Progress) -> Void
        private(set) var capHit: Int64?

        init(cap: Int64, onProgress: @escaping @Sendable (Progress) -> Void) {
            self.cap = cap
            self.onProgress = onProgress
        }

        func urlSession(_ session: URLSession, downloadTask task: URLSessionDownloadTask,
                        didWriteData _: Int64, totalBytesWritten written: Int64,
                        totalBytesExpectedToWrite expected: Int64) {
            if cap > 0, written > cap || expected > cap {
                capHit = cap
                task.cancel()      // 别为了发现"太大了"把整个文件拉完
                return
            }
            onProgress(Progress(received: written, total: expected))
        }

        func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask,
                        didFinishDownloadingTo _: URL) {
            // async 版的 download(for:delegate:) 自己接管落地文件,这里什么都
            // 不用做;但协议要求实现它。
        }
    }
}
