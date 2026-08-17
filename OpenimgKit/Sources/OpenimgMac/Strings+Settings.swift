import Foundation
import OpenimgKit

/// 设置页与 Passkey 注册的文案。
///
/// 全站最大的一块:九张卡片(资料/外观/登录与安全/图片处理/自动上传目录/
/// 水印/存储位置/在网站上管理/这台设备)加上原生 Passkey 仪式的几条提示。
struct SettingsStrings: Sendable {
    // 个人资料
    let profile: String
    let nickname: String
    let avatarHelp: String
    let change: String
    let remove: String

    // 外观
    let appearance: String
    let language: String
    let languageHint: String
    let brandColor: String
    let brandColorHint: String
    /// 品牌色相的显示名。`BrandTint` 的 rawValue 是存进 UserDefaults 的稳定
    /// 标识,显示名单独取——切语言不该动到存的值。
    let tintName: @Sendable (BrandTint) -> String

    // 登录与安全 · 密码
    let security: String
    let changePassword: String
    let setPassword: String
    let confirmChange: String
    let confirmSet: String
    let codeValidHint: String
    let codeWillSendHint: String
    let codeSentTo: @Sendable (String) -> String
    let codeField: String
    let newPasswordField: String
    let passwordField: String
    let repeatPasswordField: String
    let passwordTooShort: String
    let passwordMismatch: String
    let resendIn: @Sendable (Int) -> String
    let resendCode: String
    let cancel: String
    let delete: String

    // 登录与安全 · Passkey
    let passkeyHint: String
    let noPasskeys: String
    let lastUsed: @Sendable (String) -> String
    let addedOn: @Sendable (String) -> String
    let passkeyNameField: String
    let addPasskey: String

    // 图片处理
    let processing: String
    let mode: String
    /// 上传模式与转换格式的显示名。枚举本身在共享的 Models.swift 里,不属于
    /// 界面层,所以文案在这边落地,调用点传闭包而不是 `\.label`。
    let modeLabel: @Sendable (UploadMode) -> String
    let modeDetail: @Sendable (UploadMode) -> String
    let variantLabel: @Sendable (VariantFormat) -> String
    let autoConvert: String
    let autoConvertOff: String
    let autoConvertHint: String
    let maxWidth: String
    let maxWidthOff: String
    let maxWidthHint: String
    let maxFileSize: String
    let dailyUpload: String
    let unlimited: String
    let formats: String
    let imageCount: @Sendable (Int) -> String

    // 自动上传目录
    let watchFolders: String
    let watchToggle: String
    let watchPaused: @Sendable (String) -> String
    let resume: String
    let removeFolderHelp: String
    let chooseFolderPrompt: String
    let addFolder: String
    let scanNow: String
    let watchNote: String

    // 水印
    let watermark: String
    let watermarkTextField: String
    let position: String
    let positionLabel: @Sendable (String) -> String
    let opacity: @Sendable (Int) -> String
    let size: String
    let sizeSmall: String
    let sizeMedium: String
    let sizeLarge: String
    let autoWatermarkWatch: String
    let watermarkNote: String
    /// 九宫格锚点的可读名,行优先与 WatermarkSpec.anchor 对齐。
    let anchorNames: [String]

    // 存储位置
    let storageAdd: String
    let storageAddTitle: String
    let storageEditTitle: String
    let storageName: String
    let storageEndpoint: String
    let storageRegion: String
    let storageBucket: String
    let storageKeyPrefix: String
    let storageAccessKey: String
    let storageSecretKey: String
    let storageAccessKeyKeep: String
    let storageSecretKeyKeep: String
    let storagePublicBase: String
    let storagePublicBaseHint: String
    let storageSave: String
    let storageTest: String
    let storageEdit: String
    let storageSetDefault: String
    let storageDefaultBadge: String
    let storageSaved: String
    let storageTestPassed: String
    let storageRemoved: String
    let storageDefaultSet: @Sendable (String) -> String
    let endpointKind: @Sendable (StorageProfileInput.EndpointKind) -> String
    let location: String
    let locationKeyNote: String
    let locationEmpty: String
    let kindPlatform: String
    let kindOwnBucket: @Sendable (String) -> String

    // 在网站上管理

    // 这台设备
    let device: String
    let deviceNote: String
    let signOut: String
    let openWebsite: String

    // 原生 Passkey 注册仪式
    let passkeyUnknownCredential: String
    let passkeyChallengeUnreadable: String
    let passkeyNoCredential: String
    let passkeyAdded: String
    let passkeyUnsignedBuild: String
}

extension SettingsStrings {
    static let zh = SettingsStrings(
        profile: "个人资料",
        nickname: "昵称",
        avatarHelp: "点击或拖入图片更换头像",
        change: "更换",
        remove: "移除",

        appearance: "外观",
        language: "界面语言",
        languageHint: "切换后立即生效",
        brandColor: "品牌色",
        brandColorHint: "与网站同步的两套配色",
        tintName: { tint in
            switch tint {
            case .green: "绿色"
            case .violet: "紫色"
            }
        },

        security: "登录与安全",
        changePassword: "修改密码",
        setPassword: "设置密码",
        confirmChange: "确认修改",
        confirmSet: "确认设置",
        codeValidHint: "验证码 5 分钟内有效",
        codeWillSendHint: "验证码会发到你的邮箱",
        codeSentTo: { mail in "验证码已发到 \(mail)" },
        codeField: "6 位验证码",
        newPasswordField: "新密码（至少 8 位）",
        passwordField: "密码（至少 8 位）",
        repeatPasswordField: "再输入一次",
        passwordTooShort: "密码至少 8 位",
        passwordMismatch: "两次输入不一致",
        resendIn: { s in "重发 (\(s)s)" },
        resendCode: "重发验证码",
        cancel: "取消",
        delete: "删除",

        passkeyHint: "免密码登录，用触控 ID 或手机确认",
        noPasskeys: "还没有添加 Passkey",
        lastUsed: { date in "最近使用 \(date)" },
        addedOn: { date in "添加于 \(date)" },
        passkeyNameField: "名称（如 MacBook Touch ID）",
        addPasskey: "添加 Passkey",

        processing: "图片处理",
        mode: "处理方式",
        modeLabel: { mode in mode == .optimized ? "压缩优化" : "保留原图" },
        modeDetail: { mode in
            mode == .optimized
                ? "重新编码并抹除元数据，通常更小"
                : "原样保存，保留拍摄参数（仅 JPEG 抹除定位信息）"
        },
        variantLabel: { format in
            switch format {
            case .none: "不转换"
            case .webp: "WebP"
            case .avif: "AVIF"
            }
        },
        autoConvert: "上传自动转换",
        autoConvertOff: "原图模式下不转换",
        autoConvertHint: "选定后上传直接转成该格式存储，不保留原格式；动图除外",
        maxWidth: "最大宽度",
        maxWidthOff: "保留原图时不缩放",
        maxWidthHint: "超过就等比缩小，只影响之后上传的图片",
        maxFileSize: "单文件上限",
        dailyUpload: "每日上传",
        unlimited: "不限",
        formats: "支持格式",
        imageCount: { n in "\(n) 张" },

        watchFolders: "自动上传目录",
        watchToggle: "监控以下目录，图片自动上传",
        watchPaused: { reason in "已暂停：\(reason)" },
        resume: "继续",
        removeFolderHelp: "移除此目录（已上传的图片与记录不受影响）",
        chooseFolderPrompt: "选择目录",
        addFolder: "添加目录…",
        scanNow: "立即扫描",
        watchNote: "首次启用会上传目录内的全部现有图片（含子目录）。已上传的文件记录在本地清单，改名、移动或重启不会重复占用配额。配额不足、到每日上限或令牌失效会自动暂停（每日上限次日自动继续）。只上传，不会删除任何一端的文件。",

        watermark: "水印",
        watermarkTextField: "水印文字（留空即不启用）",
        position: "位置",
        positionLabel: { name in "水印位置：\(name)" },
        opacity: { pct in "透明度 \(pct)%" },
        size: "大小",
        sizeSmall: "小",
        sizeMedium: "中",
        sizeLarge: "大",
        autoWatermarkWatch: "对监控目录上传的图片自动加水印",
        watermarkNote: "水印在本机合成后上传。手动上传时在编辑器里按需勾选；原图模式下监控上传不加水印（字节原样是该模式的承诺），动图也不加（逐帧合成不支持）。",
        anchorNames: [
            "左上", "上中", "右上", "左中", "居中", "右中", "左下", "下中", "右下",
        ],

        storageAdd: "添加存储位置",
        storageAddTitle: "添加自有存储",
        storageEditTitle: "修改存储配置",
        storageName: "名称（如 我的 R2）",
        storageEndpoint: "Endpoint",
        storageRegion: "区域",
        storageBucket: "存储桶",
        storageKeyPrefix: "路径前缀（可选）",
        storageAccessKey: "Access Key",
        storageSecretKey: "Secret Key",
        storageAccessKeyKeep: "Access Key（留空不改）",
        storageSecretKeyKeep: "Secret Key（留空不改）",
        storagePublicBase: "公开访问地址",
        storagePublicBaseHint: "图片外链用它拼出来，通常是你桶的自定义域名。保存前会先探测能否写入——写不进去的桶比没有桶更糟。",
        storageSave: "保存",
        storageTest: "仅测试",
        storageEdit: "修改配置",
        storageSetDefault: "设为默认",
        storageDefaultBadge: "默认",
        storageSaved: "存储配置已保存",
        storageTestPassed: "连接正常，可以写入",
        storageRemoved: "存储位置已移除",
        storageDefaultSet: { name in "以后上传到 \(name)" },
        endpointKind: { k in
            switch k {
            case .r2: "看起来是 Cloudflare R2"
            case .s3: "看起来是 Amazon S3"
            case .b2: "看起来是 Backblaze B2"
            case .spaces: "看起来是 DigitalOcean Spaces"
            case .oss: "看起来是阿里云 OSS"
            case .cos: "看起来是腾讯云 COS"
            case .custom: "自定义 S3 兼容服务"
            }
        },
        location: "存储位置",
        locationKeyNote: "新增或修改存储位置需要填写密钥，见下方「在网站上管理」",
        locationEmpty: "还没有图片，看不出存的位置",
        kindPlatform: "平台存储池",
        kindOwnBucket: { kind in "\(kind) · 自有存储桶" },


        device: "这台设备",
        deviceNote: "凭证保存在钥匙串里，重开应用会自动登录。退出登录只会从这台\n设备移除它，服务器上的令牌需要在网站里删除。",
        signOut: "退出登录",
        openWebsite: "在网站上打开",

        passkeyUnknownCredential: "系统返回了未知的凭证类型",
        passkeyChallengeUnreadable: "服务器返回的注册挑战无法解析",
        passkeyNoCredential: "系统未返回注册凭证",
        passkeyAdded: "Passkey 已添加",
        passkeyUnsignedBuild: "系统拒绝创建：此构建未正式签名，无法证明域名归属。请先在网站上添加，正式签名版发布后 App 内即可直接添加。")

    static let en = SettingsStrings(
        profile: "Profile",
        nickname: "Nickname",
        avatarHelp: "Click or drop an image to change your avatar",
        change: "Change",
        remove: "Remove",

        appearance: "Appearance",
        language: "Language",
        languageHint: "Applies immediately",
        brandColor: "Brand color",
        brandColorHint: "The same two palettes as the website",
        tintName: { tint in
            switch tint {
            case .green: "Green"
            case .violet: "Violet"
            }
        },

        security: "Sign-In & Security",
        changePassword: "Change Password",
        setPassword: "Set Password",
        confirmChange: "Change Password",
        confirmSet: "Set Password",
        codeValidHint: "The code is valid for 5 minutes",
        codeWillSendHint: "We'll email you a code",
        codeSentTo: { mail in "Code sent to \(mail)" },
        codeField: "6-digit code",
        newPasswordField: "New password (at least 8 characters)",
        passwordField: "Password (at least 8 characters)",
        repeatPasswordField: "Enter it again",
        passwordTooShort: "Password must be at least 8 characters",
        passwordMismatch: "The two passwords don't match",
        resendIn: { s in "Resend (\(s)s)" },
        resendCode: "Resend Code",
        cancel: "Cancel",
        delete: "Delete",

        passkeyHint: "Sign in without a password, using Touch ID or your phone",
        noPasskeys: "No passkeys yet",
        lastUsed: { date in "Last used \(date)" },
        addedOn: { date in "Added \(date)" },
        passkeyNameField: "Name (e.g. MacBook Touch ID)",
        addPasskey: "Add Passkey",

        processing: "Image Processing",
        mode: "Mode",
        modeLabel: { mode in mode == .optimized ? "Optimized" : "Keep original" },
        modeDetail: { mode in
            mode == .optimized
                ? "Re-encoded with metadata stripped, usually smaller"
                : "Stored as-is with EXIF kept (GPS wiped from JPEG only)"
        },
        variantLabel: { format in
            switch format {
            case .none: "No conversion"
            case .webp: "WebP"
            case .avif: "AVIF"
            }
        },
        autoConvert: "Convert on Upload",
        autoConvertOff: "No conversion in original mode",
        autoConvertHint: "Uploads are stored in this format instead of the original. Animated images are left alone.",
        maxWidth: "Max Width",
        maxWidthOff: "No resizing when keeping originals",
        maxWidthHint: "Anything wider is scaled down. Applies to future uploads only.",
        maxFileSize: "Max file size",
        dailyUpload: "Daily uploads",
        unlimited: "Unlimited",
        formats: "Formats",
        imageCount: { n in n == 1 ? "1 image" : "\(n) images" },

        watchFolders: "Auto-Upload Folders",
        watchToggle: "Upload images from these folders automatically",
        watchPaused: { reason in "Paused: \(reason)" },
        resume: "Resume",
        removeFolderHelp: "Stop watching this folder (uploaded images and records are untouched)",
        chooseFolderPrompt: "Choose",
        addFolder: "Add Folder…",
        scanNow: "Scan Now",
        watchNote: "Turning this on uploads every image already in the folders, subfolders included. Uploaded files are recorded in a local list, so renaming, moving or restarting never spends quota twice. Running out of quota, reaching the daily limit or an expired token pauses it automatically — the daily limit resumes by itself the next day. It only uploads; nothing is ever deleted on either end.",

        watermark: "Watermark",
        watermarkTextField: "Watermark text (leave empty to turn it off)",
        position: "Position",
        positionLabel: { name in "Watermark position: \(name)" },
        opacity: { pct in "Opacity \(pct)%" },
        size: "Size",
        sizeSmall: "Small",
        sizeMedium: "Medium",
        sizeLarge: "Large",
        autoWatermarkWatch: "Watermark images uploaded from watched folders",
        watermarkNote: "The watermark is composited on this Mac before uploading. For manual uploads, switch it on in the editor. Watched folders are never watermarked in original mode — untouched bytes are what that mode promises — and animated images are skipped as well, since frame-by-frame compositing isn't supported.",
        anchorNames: [
            "Top left", "Top center", "Top right",
            "Middle left", "Center", "Middle right",
            "Bottom left", "Bottom center", "Bottom right",
        ],

        storageAdd: "Add Storage",
        storageAddTitle: "Add your own bucket",
        storageEditTitle: "Edit storage",
        storageName: "Name (e.g. My R2)",
        storageEndpoint: "Endpoint",
        storageRegion: "Region",
        storageBucket: "Bucket",
        storageKeyPrefix: "Key prefix (optional)",
        storageAccessKey: "Access Key",
        storageSecretKey: "Secret Key",
        storageAccessKeyKeep: "Access Key (blank keeps current)",
        storageSecretKeyKeep: "Secret Key (blank keeps current)",
        storagePublicBase: "Public base URL",
        storagePublicBaseHint: "Image links are built from this, usually your bucket's custom domain. The bucket is probed before saving — one that can't be written to is worse than none.",
        storageSave: "Save",
        storageTest: "Test only",
        storageEdit: "Edit",
        storageSetDefault: "Set as default",
        storageDefaultBadge: "Default",
        storageSaved: "Storage saved",
        storageTestPassed: "Connected — writes work",
        storageRemoved: "Storage removed",
        storageDefaultSet: { name in "Uploads now go to \(name)" },
        endpointKind: { k in
            switch k {
            case .r2: "Looks like Cloudflare R2"
            case .s3: "Looks like Amazon S3"
            case .b2: "Looks like Backblaze B2"
            case .spaces: "Looks like DigitalOcean Spaces"
            case .oss: "Looks like Aliyun OSS"
            case .cos: "Looks like Tencent COS"
            case .custom: "Custom S3-compatible service"
            }
        },
        location: "Storage Location",
        locationKeyNote: "Adding or changing a storage location needs access keys — see Manage on the Web below.",
        locationEmpty: "No images yet, so there's nothing to show",
        kindPlatform: "Platform pool",
        kindOwnBucket: { kind in "\(kind) · Your own bucket" },


        device: "This Device",
        deviceNote: "Your credentials live in the Keychain, so the app signs in again on its own. Signing out only removes them from this Mac — the token on the server has to be deleted on the website.",
        signOut: "Sign Out",
        openWebsite: "Open Website",

        passkeyUnknownCredential: "The system returned an unknown credential type",
        passkeyChallengeUnreadable: "The registration challenge from the server couldn't be read",
        passkeyNoCredential: "The system didn't return a credential",
        passkeyAdded: "Passkey added",
        passkeyUnsignedBuild: "The system refused: this build isn't properly signed, so it can't prove it owns the domain. Add the passkey on the website for now — a signed release will be able to do it right here.")
}
