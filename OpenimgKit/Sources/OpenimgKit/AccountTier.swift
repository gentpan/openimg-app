import Foundation

/// 账号所在的用户组。
///
/// 服务端的组是**数据库里的一张表**,不是写死的枚举——`GET /api/quota` 回来的
/// `tier.name` 是那张表里的一行的名字。今天线上有三行(admin / trusted / free),
/// 但它是数据,不是常量。
///
/// 所以这里必须有 `.other`:把未知名字当成崩溃或者空白,等于让一次后台加组把
/// 客户端的资料卡打成一片空。网页端的 GroupBadge 已经立了这条规矩(未知组退回
/// 中性样式、原样显示名字),两端保持一致。
public enum AccountTier: Sendable, Equatable, Hashable {
    case admin
    case trusted
    case free
    /// 认不出来的组,带上原名。
    case other(String)

    public static func parse(_ raw: String) -> AccountTier {
        switch raw.lowercased() {
        case "admin": .admin
        case "trusted": .trusted
        case "free": .free
        default: .other(raw)
        }
    }

    /// 资料卡右上角那枚水印用的图形。
    ///
    /// 与网页端 GroupBadge 的图标一一对应,只是换成 SF Symbols:
    /// 盾牌 / 绶带 / 单人。都在 macOS 14 就有——`medal.fill` 要到 macOS 15,
    /// 这个项目的下限是 14,用它会在旧系统上画出一个空方框。
    public var symbol: String {
        switch self {
        case .admin: "shield.lefthalf.filled"
        case .trusted: "rosette"
        case .free: "person.fill"
        case .other: "person.2.fill"
        }
    }

    /// 组的原始名字。界面上要显示时用它,不要再去碰服务端那个字符串。
    public var rawName: String {
        switch self {
        case .admin: "admin"
        case .trusted: "trusted"
        case .free: "free"
        case .other(let n): n
        }
    }
}
