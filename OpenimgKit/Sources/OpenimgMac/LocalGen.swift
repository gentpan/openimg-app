import SwiftUI
import AppKit
#if canImport(ImagePlayground)
import ImagePlayground
#endif

/// 用 Mac 本机的 Image Playground 出图。
///
/// 这条路和 AI 生成那条**不是同一件事**,不是它的兜底:
///
///   - 风格只有动画 / 插画 / 素描 / 表情,**没有写实**。想要产品图、写实场景,
///     还得走服务端那条;
///   - 只在 Apple 芯片 + macOS 15.1 + 用户自己打开了 Apple Intelligence + 受支
///     持的地区语言时才存在。这些条件不满足的机器上,这个入口整个不出现;
///   - 不耗任何配额:图在本机算,出来的字节直接进上传管线。
///
/// 用系统弹窗而不是自己画输入框。看着是绕了一圈,但可编程的那个 API
/// (`ImageCreator`)在 macOS 27 上**已被弃用,而且实测直接抛 notSupported**
/// ——本机跑一遍就知道,它不是"将来会没",是现在就没有。
enum LocalGen {
    /// 这台机器此刻能不能用。
    ///
    /// 每次读都问一遍系统,不缓存:用户可能在设置里刚打开 Apple Intelligence,
    /// 缓存住的话要重启 app 才认。这个调用很便宜。
    static var isReady: Bool {
        #if canImport(ImagePlayground)
        if #available(macOS 15.1, *) {
            return ImagePlaygroundViewController.isAvailable
        }
        #endif
        return false
    }
}

/// 把系统弹窗挂上去。
///
/// 包一层是因为部署目标是 macOS 14,而这个修饰器 15.1 才有——`if #available`
/// 必须在 ViewBuilder 里面,不能写在调用点上。
struct LocalGenSheet: ViewModifier {
    @Binding var presented: Bool
    /// 用户已经打的提示词,带进弹窗当起点。空着也行,系统弹窗里可以现打。
    let concept: String
    let onImage: (URL) -> Void

    func body(content: Content) -> some View {
        #if canImport(ImagePlayground)
        if #available(macOS 15.1, *) {
            content.imagePlaygroundSheet(
                isPresented: $presented,
                concept: concept,
                onCompletion: onImage
            )
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    func localGenSheet(isPresented: Binding<Bool>, concept: String,
                       onImage: @escaping (URL) -> Void) -> some View {
        modifier(LocalGenSheet(presented: isPresented, concept: concept, onImage: onImage))
    }
}
