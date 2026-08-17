import Foundation

/// 导航外壳的文案:侧栏、顶栏、菜单命令。
///
/// 只放"框"上的字——页面内部的文案各归各的分区。
struct NavStrings: Sendable {
    // 四个分区名。侧栏行、顶栏标题共用一份,别在两处各写各的。
    let overview: String
    let gallery: String
    let upload: String
    let settings: String

    // 菜单命令。「刷新」是通用词,取 common 那份,这里不再留一个同值副本。
    let uploadImages: String

    // 顶栏工具
    let sort: String
    let perPage: String
    let perPageCount: @Sendable (Int) -> String
    let uploadHelp: String

    // 侧栏
    let searchPlaceholder: String
    let availableSpace: @Sendable (String) -> String
    let signOutHelp: String
}

extension NavStrings {
    /// 分区名的取词口,也是唯一的一份——`Section_.label` 反过来调这里,
    /// 免得模型层再存一套跟着语言变的显示名。
    func section(_ s: Section_) -> String {
        switch s {
        case .overview: overview
        case .gallery: gallery
        case .upload: upload
        case .settings: settings
        }
    }

    static let zh = NavStrings(
        overview: "概览",
        gallery: "图库",
        upload: "上传",
        settings: "设置",
        uploadImages: "上传图片…",
        sort: "排序",
        perPage: "每页数量",
        perPageCount: { n in "\(n) 张/页" },
        uploadHelp: "上传 (⌘U)",
        searchPlaceholder: "搜索文件名",
        availableSpace: { size in "\(size) 可用" },
        signOutHelp: "退出登录（仅移除本机令牌）")

    static let en = NavStrings(
        overview: "Overview",
        gallery: "Gallery",
        upload: "Upload",
        settings: "Settings",
        uploadImages: "Upload Images…",
        sort: "Sort",
        perPage: "Images per Page",
        perPageCount: { n in "\(n) per page" },
        uploadHelp: "Upload (⌘U)",
        searchPlaceholder: "Search file names",
        availableSpace: { size in "\(size) available" },
        signOutHelp: "Sign Out (removes the token from this Mac only)")
}
