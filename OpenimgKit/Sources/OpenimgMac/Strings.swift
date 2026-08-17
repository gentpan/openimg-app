import Foundation

/// App 的文案目录。
///
/// 与网页端同一套约定:中文是事实来源,英文按同一形状写第二份;不同的是
/// Swift 没有 `typeof zh`,改用**逐区结构体 + 成员初始化器**拿同样的保证
/// ——英文那份漏一个字段就是编译错误,不会渲染出 `nil`。
///
/// 每个界面文件独占一个分区(`Strings+Gallery.swift` 之类),分区各自持有
/// 自己的 zh/en 两份实例。这样加文案永远只动一个文件,也不会有两处改动
/// 撞在同一张大表上。
///
/// 带变量的条目一律写成闭包,参数顺序由调用方定——中英文常常要把变量放在
/// 句子的不同位置。
struct Strings: Sendable {
    var common: CommonStrings
    var nav: NavStrings
    var login: LoginStrings
    var overview: OverviewStrings
    var gallery: GalleryStrings
    var upload: UploadStrings
    var generate: GenerateStrings
    var retouch: RetouchStrings
    var editor: EditorStrings
    var settings: SettingsStrings
    var watch: WatchStrings
    var errors: ErrorStrings

    static let zh = Strings(
        common: .zh, nav: .zh, login: .zh, overview: .zh, gallery: .zh,
        upload: .zh, generate: .zh, retouch: .zh, editor: .zh, settings: .zh,
        watch: .zh, errors: .zh)

    static let en = Strings(
        common: .en, nav: .en, login: .en, overview: .en, gallery: .en,
        upload: .en, generate: .en, retouch: .en, editor: .en, settings: .en,
        watch: .en, errors: .en)
}

/// 界面语言。默认跟随系统:简体中文环境用中文,其余用英文——和网页端
/// 首访按 navigator.language 判断是同一条规则。
enum AppLang: String, CaseIterable, Sendable {
    case zh, en

    var label: String { self == .zh ? "中文" : "English" }

    /// 日期与数字格式化用,别把界面语言和区域格式混为一谈。
    var locale: Locale { Locale(identifier: self == .zh ? "zh_CN" : "en_US") }

    static var systemDefault: AppLang {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("zh") ? .zh : .en
    }

    /// 当前语言与其文案。做成静态量的理由同 BrandTint.current:文案在
    /// ButtonStyle、nonisolated 辅助函数等拿不到 Environment 的地方也要用。
    nonisolated(unsafe) static var current: AppLang = {
        AppLang(rawValue: UserDefaults.standard.string(forKey: "appLang") ?? "") ?? systemDefault
    }()
}

/// 全局取词入口。写成一个字母是因为它会出现在几百处:`L.s.common.save`。
enum L {
    static var s: Strings { AppLang.current == .zh ? .zh : .en }
    static var locale: Locale { AppLang.current.locale }
}
