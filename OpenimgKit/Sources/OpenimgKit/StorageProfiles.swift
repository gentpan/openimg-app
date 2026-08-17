import Foundation

/// 一个存储位置。凭据永远不下发——服务器只给打码后的 access key。
public struct StorageProfile: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let kind: String
    public let name: String
    public let endpoint: String
    public let region: String
    public let bucket: String
    public let keyPrefix: String
    public let pathStyle: Bool
    public let accessKeyMask: String
    public let publicBaseURL: String
    public let isDefault: Bool
    public let isPlatform: Bool
    public let backupOfID: String?
    public let status: String
    public let lastError: String?
    public let imageCount: Int64
    public let storedBytes: Int64

    enum CodingKeys: String, CodingKey {
        case id, kind, name, endpoint, region, bucket, status
        case keyPrefix = "key_prefix"
        case pathStyle = "path_style"
        case accessKeyMask = "access_key_mask"
        case publicBaseURL = "public_base_url"
        case isDefault = "is_default"
        case isPlatform = "is_platform"
        case backupOfID = "backup_of_id"
        case lastError = "last_error"
        case imageCount = "image_count"
        case storedBytes = "stored_bytes"
    }

    public var isActive: Bool { status == "active" }
}

/// 新建或修改一个存储位置的入参。
///
/// `secretKey` 留空表示"沿用已存的那把"——服务器从不回传密钥,编辑时不填
/// 就是不改。`code` 是令牌调用时的二次因子:这组接口能把后续上传导去别处,
/// 单靠泄露的令牌不该做得成(网页会话免除,它已经是一次登录)。
public struct StorageProfileInput: Encodable, Sendable {
    public var name = ""
    public var endpoint = ""
    public var region = "auto"
    public var bucket = ""
    public var keyPrefix = ""
    public var accessKey = ""
    public var secretKey = ""
    public var publicBaseURL = ""
    public var testOnly = false
    public var code = ""

    public init() {}

    enum CodingKeys: String, CodingKey {
        case name, endpoint, region, bucket, code
        case keyPrefix = "key_prefix"
        case accessKey = "access_key"
        case secretKey = "secret_key"
        case publicBaseURL = "public_base_url"
        case testOnly = "test_only"
    }

    /// 从常见服务商的 endpoint 猜出一句人话,让用户在保存前能自查填对没有。
    /// 与网页端 describeEndpoint 同一张表。
    public static func describeEndpoint(_ endpoint: String) -> EndpointKind? {
        let e = endpoint.lowercased()
        guard !e.isEmpty else { return nil }
        if e.contains("r2.cloudflarestorage.com") { return .r2 }
        if e.contains("amazonaws.com") { return .s3 }
        if e.contains("backblazeb2.com") { return .b2 }
        if e.contains("digitaloceanspaces.com") { return .spaces }
        if e.contains("aliyuncs.com") { return .oss }
        if e.contains("myqcloud.com") { return .cos }
        return .custom
    }

    public enum EndpointKind: Sendable {
        case r2, s3, b2, spaces, oss, cos, custom
    }
}
