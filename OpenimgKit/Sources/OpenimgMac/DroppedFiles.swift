import Foundation
import UniformTypeIdentifiers

/// 把 `onDrop` 递来的 NSItemProvider 解成文件 URL。
///
/// NSItemProvider 把文件 URL 放在它的 Data 表示里,换任何别的读法都只会静默
/// 得到 nil——每个拖放目标都要踩一次这个坑,所以只写一份。
///
/// 用 completion 版接口而不是 async 的 `loadItem`:后者返回
/// `any NSSecureCoding`,在正式版 SDK 的严格并发下不可跨界发送(本机 beta
/// 放行只是巧合)。Data 是 Sendable,包个 continuation 了事。
///
/// 整个 @MainActor:`onDrop` 交出来的那组 NSItemProvider 是主 actor 隔离的,
/// 而 NSItemProvider 不是 Sendable——换成 nonisolated 就得把它们「发送」出去,
/// 编译器直接拒绝。等在主 actor 上没有代价,真正的读盘发生在回调那一侧。
@MainActor
enum DroppedFiles {
    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var out: [URL] = []
        for p in providers {
            let data: Data? = await withCheckedContinuation { cont in
                _ = p.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { d, _ in
                    cont.resume(returning: d)
                }
            }
            guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { continue }
            out.append(url)
        }
        return out
    }

    /// 只要第一个的场合(头像、编辑器)。仍然把每个都解一遍再取首个:前几个
    /// 里混着解不出来的东西时,不该整个拖放就此作废。
    static func firstURL(from providers: [NSItemProvider]) async -> URL? {
        await urls(from: providers).first
    }
}
