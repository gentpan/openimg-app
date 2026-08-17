import Foundation
import CryptoKit
import Security

/// Keychain-backed storage for the personal access token.
///
/// A token is the whole account as far as the image library goes: it can list,
/// upload, and bulk-delete 500 images per call with no second confirmation. It
/// does not belong in UserDefaults, and it does not belong in a plist next to
/// the app.
///
/// The data-protection keychain is preferred and not required. It is the one
/// place iOS and macOS disagree by default — a non-sandboxed macOS process
/// otherwise lands in the older file-based keychain, where the item is
/// exportable with the `security` command line tool and `kSecAttrAccessible`
/// does not mean what it means on iOS.
///
/// But asking for it needs a keychain-access-group entitlement, which is tied
/// to a team identifier, which an ad-hoc signature does not have. A locally
/// built app therefore gets errSecMissingEntitlement (-34018) and cannot store
/// anything at all. Since the choice is between the older keychain and no
/// keychain, every operation falls back to the older one.
public struct TokenStore: Sendable {
    public let service: String
    public init(service: String = "io.openimg.token") { self.service = service }

    /// One entry per server, so connecting to a self-hosted instance does not
    /// silently overwrite the credential for the public one.
    private func query(server: String, dataProtection: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: server,
        ]
        if dataProtection { q[kSecUseDataProtectionKeychain as String] = true }
        return q
    }

    /// ad-hoc 构建的持久化出口。旧式钥匙串按代码签名身份做访问控制,而
    /// ad-hoc 签名每次重新打包身份都变——上一个构建存的令牌,下一个构建
    /// 读不回来,表现就是「每次打开都要重新登录」。0600 的本地文件在防护
    /// 上与旧式钥匙串相差无几(后者本来就能被 `security` 命令导出),而
    /// 令牌按设计不能删号、不能再铸令牌,泄露半径有限。真签名构建(带
    /// keychain entitlement)走数据保护钥匙串,永远不会落到这条路;钥匙串
    /// 写入成功时顺手删掉历史文件,完成迁移。
    private func fileURL(server: String) -> URL {
        let digest = SHA256.hash(data: Data(server.utf8))
            .prefix(8).map { String(format: "%02x", $0) }.joined()
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("io.openimg.mac/token-\(digest)")
    }

    public func save(_ token: String, server: String) throws {
        var attrs = query(server: server, dataProtection: true)
        SecItemDelete(attrs as CFDictionary) // upsert; add-then-update races
        attrs[kSecValueData as String] = Data(token.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status == errSecSuccess {
            try? FileManager.default.removeItem(at: fileURL(server: server))
            return
        }
        guard status == errSecMissingEntitlement else { throw KeychainError(status: status) }
        let url = fileURL(server: server)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(token.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: url.path)
    }

    public func load(server: String) -> String? {
        // 数据保护钥匙串 → 旧式钥匙串(老构建的存量,只读迁移) → 文件
        for dp in [true, false] {
            var q = query(server: server, dataProtection: dp)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: CFTypeRef?
            if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
               let data = out as? Data {
                return String(data: data, encoding: .utf8)
            }
        }
        guard let data = try? Data(contentsOf: fileURL(server: server)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func delete(server: String) -> Bool {
        // Both keychains, not just whichever answers first: a build that
        // gained entitlements mid-life would otherwise leave the old copy.
        var removed = false
        for dp in [true, false] {
            if SecItemDelete(query(server: server, dataProtection: dp) as CFDictionary) == errSecSuccess {
                removed = true
            }
        }
        if (try? FileManager.default.removeItem(at: fileURL(server: server))) != nil {
            removed = true
        }
        return removed
    }
}

public struct KeychainError: Error, LocalizedError {
    public let status: OSStatus
    public var errorDescription: String? {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "未知错误"
        return "钥匙串操作失败（\(status)）：\(detail)"
    }
    /// True when the app simply is not allowed to use the keychain, as opposed
    /// to the keychain refusing this particular item. Callers can carry on
    /// without persistence instead of treating it as a hard failure.
    public var isEntitlementProblem: Bool { status == errSecMissingEntitlement }
}
