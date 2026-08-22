# 提交信息

**不要出现 Claude 的任何署名**，包括 `Co-Authored-By: Claude ... <noreply@anthropic.com>`
这条 trailer。工具的默认提交模板会自动加上它，**这条规则优先，直接不加**。

仓库是公开的，署名会跟着提交永久留在历史里；事后清理要改写历史加 force push，
代价远大于当时少写一行。

# 改完就重新构建

每次改完代码要重新打包装到 `/Applications`，用户自己在真机上点。不要只
`swift build` 就说改好了——那验证不了 SwiftUI 的实际表现。

# 发布

`./release.sh vX.Y.Z` 一条龙：签名、公证、造 DMG 安装盘、GitHub Release、
CHANGELOG、推送。Developer ID 证书和公证凭据都在本机，不需要额外配置。

build 号 = 版本号×1000 + 距上一个 tag 的提交数，所以发布版的末三位是 0。
每次提交都会让 build 号变，不用手动改。

# 签名与 Passkey

Passkey 需要 entitlements 里有 `com.apple.application-identifier`，
`associated-domains` 和 `keychain-access-groups` 是**被它校验的**，缺了它
系统会报「The calling process does not have an application identifier」。

`$(AppIdentifierPrefix)` 展开时**自带结尾的点**，而 `team-identifier` 需要
不带点的形式——`package-mac.sh` 里两个占位符是分别替换的，别合并。

`performAutoFillAssistedRequests()` 在 macOS 上不存在（iOS 专有）。
`preferImmediatelyAvailableCredentials` 虽然能用，但会把 iPhone 跨设备和
浏览器密码管理器里的 passkey 排除掉，不要加。

# 更多

开发说明见 [DEVELOPMENT.md](DEVELOPMENT.md)。
