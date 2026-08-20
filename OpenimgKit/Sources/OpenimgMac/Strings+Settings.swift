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
    let nicknameEditHint: String
    let avatarHelp: String

    // 外观
    let appearance: String
    let appAndDevice: String
    let levelBadge: @Sendable (Int) -> String
    let levelMax: String
    let levelToNext: @Sendable (Int) -> String
    let levelHow: @Sendable (Int) -> String
    let appVersion: String
    let updateCheck: String
    let updateChecking: String
    let updateUpToDate: String
    let updateAvailable: @Sendable (String) -> String
    let updateNotes: String
    let updateStale: @Sendable (Int) -> String
    let updateUrgent: String
    let updateTooOld: @Sendable (String) -> String
    let updateWrongArch: String
    let updateFailed: String
    let updateHowTo: String
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
    let codeWillSendHint: String
    let codeSentTo: @Sendable (String) -> String
    let codeField: String
    let newPasswordField: String
    let passwordField: String
    let repeatPasswordField: String
    let passwordTooShort: String
    let passwordMismatch: String
    let resendIn: @Sendable (Int) -> String
    let sendCode: String
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

    // 账号关联
    /// 与「登录与安全」分开的一张卡片:关联 pic.bi 打通的是额度,不是登录
    /// 方式——把它并进登录那组会读成"还能用 pic.bi 登录",而那条路不存在。
    let linkedAccounts: String
    let linkedAccountsHint: String
    let picbiLinked: String
    let picbiLinkedNote: String
    let picbiNote: String
    let picbiLink: String
    let picbiLinkHint: String
    let picbiUnlink: String
    let picbiRefresh: String

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
    /// 上传前抹除元数据。与同卡片的另外三项不同源(那三项是账号偏好,这一项
    /// 只在这台 Mac 上生效),但用户找"我传上去的照片带不带定位"只会往这张卡
    /// 上找,所以放一起。
    let stripMetadata: String
    let stripMetadataHint: String

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
    /// 文字 / 图片两种模式的分段控件标题与两个选项。
    let wmMode: String
    let wmModeText: String
    let wmModeImage: String
    let watermarkTextField: String
    // 图片模式
    let wmChooseImage: String
    let wmReplaceImage: String
    let wmClearImage: String
    let wmNoImage: String
    /// 图片模式的大小滑块。文字模式那三档("小/中/大")在这里不适用:logo 的
    /// 合适尺寸随 logo 本身的形状变,得给个连续的数。
    let wmImageSize: @Sendable (Int) -> String
    let wmOpaqueNote: String
    let wmCutout: String
    let wmCutoutNoSubject: String
    let wmImageNote: String
    // AI 生成水印
    let wmGenTitle: String
    let wmGenPrompt: String
    let wmGenButton: String
    let wmGenSubmitted: String
    let wmGenPending: String
    let wmGenDone: String
    /// 抠图没抠出来时的说法:图能用,只是带着底。
    let wmGenDoneOpaque: String
    let wmGenFailed: @Sendable (String) -> String
    let wmGenNote: String
    let wmErrTooLarge: @Sendable (Int) -> String
    let wmErrNotAnImage: String
    let wmErrSaveFailed: String
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
        nicknameEditHint: "点一下改昵称",
        avatarHelp: "点击或拖入图片更换头像",

        appearance: "外观",
        appAndDevice: "应用与设备",
        levelBadge: { n in "Lv.\(n)" },
        levelMax: "已是最高等级",
        levelToNext: { n in "距下一级还差 \(n)" },
        levelHow: { d in "累计签到 \(d) 天，加上注册时长（每满 30 天算 1）。等级只是记录，不影响配额。" },
        appVersion: "版本",
        updateCheck: "检查更新",
        updateChecking: "正在检查…",
        updateUpToDate: "已是最新版本",
        updateAvailable: { v in "有新版本 \(v)" },
        updateNotes: "查看发布说明",
        updateStale: { d in "更新信息已过期 \(d) 天，建议去发布页确认一下" },
        updateUrgent: "这一版建议尽快升级",
        updateTooOld: { v in "新版需要 macOS \(v) 或更新版本" },
        updateWrongArch: "新版不适用于这台 Mac 的处理器",
        updateFailed: "检查更新没成功",
        updateHowTo: "下载后拖进「应用程序」覆盖即可，图库和登录状态都不受影响。",
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
        codeWillSendHint: "验证码会发到你的邮箱",
        codeSentTo: { mail in "验证码已发到 \(mail)" },
        codeField: "6 位验证码",
        newPasswordField: "新密码（至少 8 位）",
        passwordField: "密码（至少 8 位）",
        repeatPasswordField: "再输入一次",
        passwordTooShort: "密码至少 8 位",
        passwordMismatch: "两次输入不一致",
        resendIn: { s in "重发 (\(s)s)" },
        sendCode: "发送验证码",
        resendCode: "重发验证码",
        cancel: "取消",
        delete: "删除",

        passkeyHint: "免密码登录，用触控 ID 或手机确认",
        noPasskeys: "还没有添加 Passkey",
        lastUsed: { date in "最近使用 \(date)" },
        addedOn: { date in "添加于 \(date)" },
        passkeyNameField: "名称（如 MacBook Touch ID）",
        addPasskey: "添加 Passkey",

        linkedAccounts: "账号关联",
        linkedAccountsHint: "两边账号各自独立，关联只是把额度打通",
        picbiLinked: "已关联",
        picbiLinkedNote: "AI 生成先用本站的免费次数，用完才扣 pic.bi 的积分",
        picbiNote: "关联 pic.bi 后，AI 生成会多出 4K 清晰度",
        picbiLink: "关联",
        picbiLinkHint: "关联要在网站上完成，会在浏览器里打开",
        picbiUnlink: "在网站解绑",
        picbiRefresh: "我已完成关联",

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
        stripMetadata: "抹除定位与设备信息",
        stripMetadataHint: "上传前在这台 Mac 上删掉 GPS、机身序列号与厂商私有数据，光圈快门 ISO 保留。关掉就按原样上传——图床的链接是公开的，图里的拍摄地点会跟着一起公开。抹不掉的图（如动图）不会上传。",

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
        wmMode: "类型",
        wmModeText: "文字",
        wmModeImage: "图片",
        watermarkTextField: "水印文字（留空即不启用）",
        wmChooseImage: "选择图片…",
        wmReplaceImage: "换一张…",
        wmClearImage: "移除",
        wmNoImage: "还没有水印图",
        wmImageSize: { pct in "大小 \(pct)%" },
        wmOpaqueNote: "这张图没有透明背景，贴上去是一个不透明的方块。",
        wmCutout: "去背景",
        wmCutoutNoSubject: "认不出画面里的主体，这张图不适合自动去背景。换一张，或者用带透明背景的 PNG。",
        wmImageNote: "水印图存在本机（应用支持目录），不上传、不同步；最长边超过 1024 像素会缩到 1024，并统一转成 PNG 以保住透明通道。图片模式的大小是 logo 宽度占画面宽度的比例，与文字模式的字号比例各存各的。",
        wmGenTitle: "用 AI 生成一枚",
        wmGenPrompt: "只说画什么就行，例如：山峰、猫头鹰、字母 G",
        wmGenButton: "生成",
        wmGenSubmitted: "已提交，通常几十秒出图",
        wmGenPending: "正在生成…",
        wmGenDone: "水印图已更新",
        wmGenDoneOpaque: "水印已生成，但背景没能自动抠掉——可以点「去背景」再试",
        wmGenFailed: { reason in "生成水印失败：\(reason)" },
        wmGenNote: "风格不用你写。你只说主体，剩下的（扁平矢量、粗线条、纯白底、居中留白、不加多余文字）由程序补齐——这几条正是「缩到十几个百分点还看得清」和「背景抠得干净」的前提，漏一条就得重生成一次。\n\n比例锁 1:1、画质锁 1k：水印最终只按画面宽度的十几个百分点渲染，出 4k 只是白花最贵的一档。生成的图带底色，落地后会在本机自动抠掉背景（用系统的前景分割，不额外花额度）；抠不干净可以再点一次「去背景」。与其它 AI 产出一样计入额度、一样进图库，同时把本机这份设成当前水印。",
        wmErrTooLarge: { mb in "图片太大了，请选 \(mb) MB 以内的文件" },
        wmErrNotAnImage: "这个文件不是一张能读的图片",
        wmErrSaveFailed: "水印图没能存下来",
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
        nicknameEditHint: "Click to change your nickname",
        avatarHelp: "Click or drop an image to change your avatar",

        appearance: "Appearance",
        appAndDevice: "App & Device",
        levelBadge: { n in "Lv.\(n)" },
        levelMax: "Top level reached",
        levelToNext: { n in "\(n) to go" },
        levelHow: { d in "\(d) check-ins so far, plus one point per 30 days since you joined. Level is a record only — it does not change your quota." },
        appVersion: "Version",
        updateCheck: "Check for Updates",
        updateChecking: "Checking…",
        updateUpToDate: "You are on the latest version",
        updateAvailable: { v in "Version \(v) is available" },
        updateNotes: "Release notes",
        updateStale: { d in "This update info is \(d) days stale — worth checking the releases page" },
        updateUrgent: "Updating soon is recommended",
        updateTooOld: { v in "The new version needs macOS \(v) or later" },
        updateWrongArch: "The new version does not run on this Mac's processor",
        updateFailed: "Could not check for updates",
        updateHowTo: "Download it and drag it into Applications, replacing the old one. Your library and sign-in are unaffected.",
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
        codeWillSendHint: "We'll email you a code",
        codeSentTo: { mail in "Code sent to \(mail)" },
        codeField: "6-digit code",
        newPasswordField: "New password (at least 8 characters)",
        passwordField: "Password (at least 8 characters)",
        repeatPasswordField: "Enter it again",
        passwordTooShort: "Password must be at least 8 characters",
        passwordMismatch: "The two passwords don't match",
        resendIn: { s in "Resend (\(s)s)" },
        sendCode: "Send Code",
        resendCode: "Resend Code",
        cancel: "Cancel",
        delete: "Delete",

        passkeyHint: "Sign in without a password, using Touch ID or your phone",
        noPasskeys: "No passkeys yet",
        lastUsed: { date in "Last used \(date)" },
        addedOn: { date in "Added \(date)" },
        passkeyNameField: "Name (e.g. MacBook Touch ID)",
        addPasskey: "Add Passkey",

        linkedAccounts: "Connected Account",
        linkedAccountsHint: "The two accounts stay separate — connecting only shares the allowance",
        picbiLinked: "Connected",
        picbiLinkedNote: "AI generation uses this site's free runs first, then pic.bi credits",
        picbiNote: "Connect pic.bi to unlock 4K detail in AI generation",
        picbiLink: "Connect",
        picbiLinkHint: "Connecting happens on the website and opens in your browser",
        picbiUnlink: "Unlink on the web",
        picbiRefresh: "I've finished connecting",

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
        stripMetadata: "Remove location and device info",
        stripMetadataHint: "GPS, serial numbers and maker-private data are removed on this Mac before uploading; aperture, shutter and ISO are kept. Turn it off to upload untouched — image links are public, and so is anything the photo says about where it was taken. Images that can't be cleaned (animations, for one) aren't uploaded.",

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
        wmMode: "Type",
        wmModeText: "Text",
        wmModeImage: "Image",
        watermarkTextField: "Watermark text (leave empty to turn it off)",
        wmChooseImage: "Choose Image…",
        wmReplaceImage: "Replace…",
        wmClearImage: "Remove",
        wmNoImage: "No watermark image yet",
        wmImageSize: { pct in "Size \(pct)%" },
        wmOpaqueNote: "This image has no transparent background — it will land as an opaque rectangle.",
        wmCutout: "Remove Background",
        wmCutoutNoSubject: "No recognisable subject in this image, so it can't be cut out automatically. Try another one, or a PNG that already has a transparent background.",
        wmImageNote: "The watermark image stays on this Mac (in Application Support) — never uploaded, never synced. Anything longer than 1024px on its longest side is scaled down to 1024 and re-encoded as PNG so the alpha channel survives. In image mode the size is the logo's width as a share of the picture's width; text mode keeps its own, separate font-size share.",
        wmGenTitle: "Generate one with AI",
        wmGenPrompt: "Just say what to draw — a mountain, an owl, the letter G",
        wmGenButton: "Generate",
        wmGenSubmitted: "Submitted — this usually takes under a minute",
        wmGenPending: "Generating…",
        wmGenDone: "Watermark image updated",
        wmGenDoneOpaque: "Watermark ready, but the background could not be removed — try “Remove Background”",
        wmGenFailed: { reason in "Could not generate the watermark: \(reason)" },
        wmGenNote: "You do not write the style. Say what to draw and the rest — flat vector, bold strokes, plain white background, centred with margin, no stray text — is filled in for you. Those are exactly what make it readable once shrunk to a low double-digit percentage of the width, and what makes the background cut out cleanly; drop one and you pay for another attempt.\n\nLocked to 1:1 and the 1k tier: the watermark is only ever rendered small, so 4K would just spend the priciest tier for pixels nobody sees. The generated image comes with a background; it is cut out on this Mac afterwards using the system's foreground segmentation, at no extra cost. If anything is left behind, hit \u{201C}Remove Background\u{201D} again. It counts against your allowance and lands in your library like any other AI image; the local copy is set as the current watermark at the same time.",
        wmErrTooLarge: { mb in "That image is too large — pick a file under \(mb) MB" },
        wmErrNotAnImage: "That file isn't an image this Mac can read",
        wmErrSaveFailed: "Could not save the watermark image",
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
