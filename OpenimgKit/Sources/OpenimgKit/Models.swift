import Foundation

/// The upload/list payload, mirroring `imageOut` in
/// `backend/internal/api/image_handlers.go`.
///
/// Only the fields a client acts on are declared. `imageOut` embeds the whole
/// `models.Image`, so it carries a good deal more — object keys, per-tier byte
/// counts, backup state — and decoding all of it would turn every backend
/// column addition into a client change.
public struct RemoteImage: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let origName: String
    public let ext: String
    public let width: Int
    public let height: Int
    public let sizeStored: Int64
    public let url: String
    public let thumbURL: String
    public let shortURL: String?
    public let markdown: String
    public let html: String
    public let bbcode: String
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case origName = "orig_name"
        case ext, width, height
        case sizeStored = "size_stored"
        case url
        case thumbURL = "thumb_url"
        case shortURL = "short_url"
        case markdown, html, bbcode
        case createdAt = "created_at"
    }
}

public struct UploadResponse: Codable, Sendable {
    public let image: RemoteImage
    /// True when the server already held these exact bytes and charged nothing.
    public let deduplicated: Bool
}

/// Mirrors SORTS in frontend/src/api.ts; the server validates against the same
/// whitelist and silently falls back to newest for anything else.
public enum SortKey: String, CaseIterable, Sendable, Identifiable {
    case newest, oldest, largest, smallest, widest, name
    public var id: String { rawValue }
    /// SF Symbol for menus. Chosen to read at a glance in a compact picker,
    /// where the label is often truncated.
    public var icon: String {
        switch self {
        case .newest: "arrow.down.to.line"
        case .oldest: "arrow.up.to.line"
        case .largest: "arrow.up.right.square"
        case .smallest: "arrow.down.right.square"
        case .widest: "aspectratio"
        // 不用 textformat.abc / character / abc 这一类:SF Symbols 会按界面
        // 语言换字形,中文下它们渲染成「甲乙丙」——那不是图标,是三个汉字挤在
        // 一枚图标的位置上,和旁边一排线条图形完全不是一回事。
        //
        // 判据是**别用带字母造型的符号**。这一列里只要含 A/Abc/ABC,就都有
        // CJK 变体。doc.text 没有字形,配上「文件名」这个标签也读得通。
        case .name: "doc.text"
        }
    }
    public var label: String {
        switch self {
        case .newest: "最新上传"
        case .oldest: "最早上传"
        case .largest: "占用最大"
        case .smallest: "占用最小"
        case .widest: "分辨率最高"
        case .name: "文件名"
        }
    }
}

public struct BulkDeleteResult: Codable, Sendable {
    public let deleted: Int
    public let remaining: Int
}

public struct ImagePage: Codable, Sendable {
    public let images: [RemoteImage]
    public let total: Int
    public let limit: Int
    public let offset: Int
}

/// What `GET /api/quota` reports. The tier block is the useful half: it is what
/// lets a client reject a file locally instead of spending one of the day's
/// uploads discovering the limit from a 413.
public struct Quota: Codable, Sendable {
    public let quotaBytes: Int64
    public let usedBytes: Int64
    public let availableBytes: Int64
    public let imageCount: Int
    public let uploadsToday: Int
    public let tier: Tier
    public let checkin: Checkin?
    /// 注册时间。等级要用。
    ///
    /// **必须是可选的。** 不发这个键的旧自建服务器会让整个 Quota 解析失败,
    /// 而那表现为空间卡整块空白——一个由"多加了一个字段"引起的、看不出因果的
    /// 故障。这个仓库为同一件事写过三处手写 decoder。
    public let memberSince: Date?

    /// Milestone rewards, so the client can say what the next one is worth
    /// instead of just counting days at the user.
    public struct Checkin: Codable, Sendable {
        public let checkedInToday: Bool
        public let streak: Int
        /// 累计签到天数。等级要用;可选,理由同 memberSince。
        public let totalDays: Int?
        public let weekBonus: Int64
        public let monthBonus: Int64
        public let daysPerWeek: Int
        public let daysPerMonth: Int

        enum CodingKeys: String, CodingKey {
            case checkedInToday = "checked_in_today"
            case totalDays = "total_days"
            case streak
            case weekBonus = "week_bonus"
            case monthBonus = "month_bonus"
            case daysPerWeek = "days_per_week"
            case daysPerMonth = "days_per_month"
        }
    }

    public struct Tier: Codable, Sendable {
        public let name: String
        public let maxFileSize: Int64
        public let dailyUploadCount: Int
        public let allowedFormats: [String]

        enum CodingKeys: String, CodingKey {
            case name
            case maxFileSize = "max_file_size"
            case dailyUploadCount = "daily_upload_count"
            case allowedFormats = "allowed_formats"
        }
    }

    enum CodingKeys: String, CodingKey {
        case quotaBytes = "quota_bytes"
        case usedBytes = "used_bytes"
        case availableBytes = "available_bytes"
        case imageCount = "image_count"
        case uploadsToday = "uploads_today"
        case tier, checkin
        case memberSince = "member_since"
    }
}

/// Conversion preferences. These only affect future uploads — flipping a
/// switch does not re-derive an existing library.
public enum UploadMode: String, CaseIterable, Sendable, Identifiable {
    case optimized, original
    public var id: String { rawValue }
    public var label: String { self == .optimized ? "压缩优化" : "保留原图" }
    public var detail: String {
        self == .optimized
            ? "重新编码并抹除元数据，通常更小"
            : "原样保存，保留拍摄参数（仅 JPEG 抹除定位信息）"
    }
}

public enum VariantFormat: String, CaseIterable, Sendable, Identifiable {
    case none, webp, avif
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .none: "不转换"
        case .webp: "WebP"
        case .avif: "AVIF"
        }
    }
}

/// Server-side whitelist; anything else is rejected with a 400.
public let allowedMaxWidths = [0, 1280, 1920, 2560, 3840]

public struct Account: Codable, Sendable {
    public let id: String
    public let email: String
    public let name: String
    public let role: String
    /// Absolute, and not always on our own origin: an uploaded avatar lives on
    /// the CDN, but one that came from Google or GitHub still points at their
    /// host. Optional because the server omits the key when it is empty.
    public let avatarURL: String?
    public let uploadMode: String?
    public let variantFormat: String?
    public let maxImageWidth: Int?
    /// 没有密码的账号(只用 OAuth/Passkey 注册的)界面上说"设置密码"而不是
    /// "修改密码"。旧服务器不返回此字段时按 true 处理,措辞退回保守说法。
    public let hasPassword: Bool?
    /// 是否关联了 pic.bi 账号——关联的是额度,不是登录方式:这个字段为真
    /// 不代表能用 pic.bi 登录本站。旧服务器不返回,按"未关联"处理。
    public let picbiConnected: Bool?

    /// What to draw when there is no picture. Prefers the nickname over the
    /// address so a letter the user chose wins over one they did not.
    public var initial: String {
        String((name.isEmpty ? email : name).prefix(1)).uppercased()
    }

    enum CodingKeys: String, CodingKey {
        case id, email, name, role
        case avatarURL = "avatar_url"
        case hasPassword = "has_password"
        case picbiConnected = "picbi_connected"
        case uploadMode = "upload_mode"
        case variantFormat = "variant_format"
        case maxImageWidth = "max_image_width"
    }
}

/// The link shapes the web UI offers, so a menu bar app can put the same set
/// behind one picker instead of inventing its own formatting.
public enum LinkFormat: String, CaseIterable, Sendable, Identifiable {
    case url, markdown, html, bbcode

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .url: "直链"
        case .markdown: "Markdown"
        case .html: "HTML"
        case .bbcode: "BBCode"
        }
    }

    public func render(_ image: RemoteImage) -> String {
        switch self {
        case .url: image.url
        case .markdown: image.markdown
        case .html: image.html
        case .bbcode: image.bbcode
        }
    }
}

/// `GET /api/storage/summary` — where the quota actually went.
///
/// The three size columns are the interesting part: users see "存储占用" larger
/// than the file they uploaded and have no way to tell whether that is the
/// primary, the WebP/AVIF derivative, or the thumbnails. This is that answer.
public struct StorageSummary: Codable, Sendable {
    public let images: Int
    public let sizeOrig: Int64
    public let sizeStored: Int64
    public let sizePrimary: Int64
    public let sizeVariants: Int64
    public let sizeThumbs: Int64
    public let sizeUnclassified: Int64
    public let byFormat: [FormatSlice]
    public let byProfile: [ProfileSlice]

    public struct FormatSlice: Codable, Sendable, Identifiable {
        public let ext: String
        public let bytes: Int64
        public let images: Int
        public var id: String { ext }
    }
    public struct ProfileSlice: Codable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let kind: String
        public let bytes: Int64
        public let images: Int
    }

    enum CodingKeys: String, CodingKey {
        case images
        case sizeOrig = "size_orig"
        case sizeStored = "size_stored"
        case sizePrimary = "size_primary"
        case sizeVariants = "size_variants"
        case sizeThumbs = "size_thumbs"
        case sizeUnclassified = "size_unclassified"
        case byFormat = "by_format"
        case byProfile = "by_profile"
    }
}

public struct QuotaTransaction: Codable, Sendable, Identifiable {
    public let id: String
    public let type: String
    public let bytes: Int64
    public let quotaAfter: Int64
    public let usedAfter: Int64
    public let reason: String
    public let createdAt: Date

    /// The ledger mixes capacity grants with consumption, and a chart that
    /// plots them on one axis is meaningless. Grants are positive space you
    /// gained; the rest is space you spent.
    public var isGrant: Bool {
        ["signup_grant", "checkin", "referral", "admin_grant", "delete_refund"].contains(type)
    }
    public var label: String {
        switch type {
        case "signup_grant": "注册赠送"
        case "checkin": "每日签到"
        case "referral": "邀请奖励"
        case "admin_grant": "管理员调整"
        case "upload": "上传"
        case "delete_refund": "删除退还"
        default: type
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, type, bytes, reason
        case quotaAfter = "quota_after"
        case usedAfter = "used_after"
        case createdAt = "created_at"
    }
}

public struct TransactionPage: Codable, Sendable {
    public let transactions: [QuotaTransaction]?
    public let total: Int
}

public struct CheckinRecord: Codable, Sendable, Identifiable {
    public let id: String
    /// yyyy-mm-dd in UTC, as stored.
    public let date: String
    public let bytes: Int64
    public let streak: Int
}

public struct CheckinResult: Codable, Sendable {
    public let grantedBytes: Int64
    public let streak: Int
    public let quotaBytes: Int64
    public let capped: Bool

    enum CodingKeys: String, CodingKey {
        case grantedBytes = "granted_bytes"
        case streak
        case quotaBytes = "quota_bytes"
        case capped
    }
}


/// What a mailed code may be spent on. The server keeps these apart, so a code
/// cannot be obtained under one purpose and presented under another.
/// `POST /api/account/otp` 的回应。
public struct OTPSent: Codable, Sendable {
    public let email: String
    public let resendIn: Int

    enum CodingKeys: String, CodingKey {
        case email
        case resendIn = "resend_in"
    }
}

public enum AccountCodePurpose: String, Sendable {
    case password
    case passkey
    case storage
}

public struct PasskeyCredential: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let createdAt: Date?
    /// Absent on credentials never used since the server started recording it.
    public let lastUsedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
    }

    /// Decoded by hand because these two are the odd ones out.
    ///
    /// Every other date in the API comes from Postgres and carries fractional
    /// seconds, so the client's decoder is set to
    /// `.iso8601WithFractionalSeconds`. These are formatted by Go with
    /// `time.RFC3339`, which has none — feeding them to that strategy fails the
    /// whole response, and it fails at runtime rather than at build time.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = Self.date(try c.decodeIfPresent(String.self, forKey: .createdAt))
        lastUsedAt = Self.date(try c.decodeIfPresent(String.self, forKey: .lastUsedAt))
    }

    /// Accepts RFC3339 with or without fractional seconds, and gives back nil
    /// rather than throwing: a credential with an unparsable timestamp is still
    /// a credential the user needs to see and be able to delete.
    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: raw) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: raw)
    }
}

/// 按天的上传趋势。
///
/// 来自 `GET /api/stats/uploads`,而不是拿图库当前那一页聚合——那份数据受排序与
/// 搜索影响,把排序切成「占用最大」再看趋势,画出来的图不是不全,是彻底错的;
/// 而想画 30 天更不可能,一页只有几十张。
public struct UploadTrend: Decodable, Sendable, Equatable {
    public let days: Int
    public let points: [Point]

    public struct Point: Decodable, Sendable, Equatable, Identifiable {
        /// YYYY-MM-DD,用户所在时区。
        public let date: String
        public let count: Int
        public let bytes: Int64
        public var id: String { date }

        /// 解成 Date 供图表用。服务端补齐过缺口,所以这里不会有断点。
        public var day: Date? {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            // 服务端给的是用户所在时区的自然日,当地时区解回去才落在同一天。
            f.timeZone = .current
            return f.date(from: date)
        }
    }
}
