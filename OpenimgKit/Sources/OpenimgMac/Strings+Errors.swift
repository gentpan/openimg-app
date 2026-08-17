import Foundation

/// AppModel 的提示条、错误映射与确认对话框文案。
///
/// 这一区里的东西大多不是「界面上的标签」而是「刚刚发生了什么」,所以句子
/// 比别处长,变量也多——中文习惯把数量放句首(「已上传 3 张」),英文习惯把
/// 名词放句尾(「3 images uploaded」),闭包参数顺序由调用方定正是为了这个。
struct ErrorStrings: Sendable {
    // 连接
    /// 参数:邮箱、警告后缀(通常为空串)
    let connected: @Sendable (String, String) -> String
    let tokenNotSaved: String

    // 签到
    let checkinCapped: String
    /// 参数:本次发放的容量、连续天数
    let checkinDone: @Sendable (String, Int) -> String

    // 删除确认
    let deleteTitle: @Sendable (Int) -> String
    /// 参数:张数、退还的容量。中文用不上张数,英文要靠它决定 file/files
    /// 与 it/they——标题已经分了单复数,正文再说 "The files" 就露馅。
    let deleteBody: @Sendable (Int, String) -> String
    let deleteConfirm: String
    let deleteCancel: String
    let deleted: @Sendable (Int) -> String

    // 上传
    let pickImages: String
    let cancelled: String
    let uploadedOne: String
    let uploadedMany: @Sendable (Int) -> String
    /// 参数:单文件上限
    let fileTooLarge: @Sendable (String) -> String
    /// 参数:扩展名(已转大写)
    let formatNotAllowed: @Sendable (String) -> String

    // 账号安全
    /// 参数:收到验证码的邮箱
    let codeSentTo: @Sendable (String) -> String
    let passwordChanged: String
    /// 参数:通行密钥名称
    let passkeyRemoved: @Sendable (String) -> String
    let unlinked: String

    // 个人资料
    let nicknameCleared: String
    let nicknameChanged: @Sendable (String) -> String
    let pickAvatar: String
    let avatarTooLarge: String
    let avatarUpdated: String
    let avatarRemoved: String
}

extension ErrorStrings {
    static let zh = ErrorStrings(
        connected: { email, warning in "已连接 \(email)\(warning)" },
        tokenNotSaved: "（令牌未能保存，下次启动需重新填写）",

        checkinCapped: "签到成功，但空间已达上限，本次未发放",
        checkinDone: { size, streak in "签到成功，+\(size)，连续 \(streak) 天" },

        deleteTitle: { n in "删除 \(n) 张图片？" },
        deleteBody: { _, size in "对象会被清除，占用的 \(size) 退还到你的空间。此操作不可撤销。" },
        deleteConfirm: "删除",
        deleteCancel: "取消",
        deleted: { n in "已删除 \(n) 张" },

        pickImages: "选择图片或文件夹",
        cancelled: "已取消",
        uploadedOne: "已上传，链接已复制",
        uploadedMany: { n in "已上传 \(n) 张，最后一条链接已复制" },
        fileTooLarge: { limit in "超过单文件上限 \(limit)" },
        formatNotAllowed: { ext in "你的用户组不支持 \(ext)" },

        codeSentTo: { email in "验证码已发到 \(email)" },
        passwordChanged: "密码已修改",
        passkeyRemoved: { name in "已删除 \(name)" },
        unlinked: "已解除绑定",

        nicknameCleared: "已清除昵称",
        nicknameChanged: { name in "昵称已改为 \(name)" },
        pickAvatar: "选择一张图片作为头像",
        avatarTooLarge: "头像图片超过 8 MB，请换小一点的",
        avatarUpdated: "头像已更新",
        avatarRemoved: "已移除头像")

    static let en = ErrorStrings(
        connected: { email, warning in "Connected as \(email)\(warning)" },
        tokenNotSaved: " (the token wasn’t saved — you’ll have to sign in again next time you open the app)",

        checkinCapped: "Checked in, but your storage is at its cap — nothing granted this time",
        checkinDone: { size, streak in "Checked in. +\(size), \(streak)-day streak" },

        deleteTitle: { n in n == 1 ? "Delete this image?" : "Delete \(n) images?" },
        deleteBody: { n, size in
            let erased = n == 1
                ? "The file is erased and the \(size) it used"
                : "The files are erased and the \(size) they used"
            return "\(erased) goes back to your storage. This cannot be undone."
        },
        deleteConfirm: "Delete",
        deleteCancel: "Cancel",
        deleted: { n in n == 1 ? "1 image deleted" : "\(n) images deleted" },

        pickImages: "Choose images or folders",
        cancelled: "Cancelled",
        uploadedOne: "Uploaded — link copied",
        uploadedMany: { n in "Uploaded \(n) images — last link copied" },
        fileTooLarge: { limit in "Over the \(limit) per-file limit" },
        formatNotAllowed: { ext in "Your tier doesn’t allow \(ext)" },

        codeSentTo: { email in "Verification code sent to \(email)" },
        passwordChanged: "Password changed",
        passkeyRemoved: { name in "Removed \(name)" },
        unlinked: "Unlinked",

        nicknameCleared: "Nickname cleared",
        nicknameChanged: { name in "Nickname changed to \(name)" },
        pickAvatar: "Choose an image to use as your avatar",
        avatarTooLarge: "Avatar image is over 8 MB — pick a smaller one",
        avatarUpdated: "Avatar updated",
        avatarRemoved: "Avatar removed")
}
