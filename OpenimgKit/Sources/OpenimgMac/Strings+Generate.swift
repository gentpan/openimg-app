import Foundation
import OpenimgKit

/// 生成分区:提示词、额度、历史。
///
/// 额度那几条是这一页最要紧的文案。「用完了」有两种,解法完全不同——今天用
/// 完等明天就有,这个月用完只能靠签到攒——所以它们各有各的句子,不共用一句
/// 含糊的「次数不足」。
struct GenerateStrings: Sendable {
    // 提示词
    let promptPlaceholder: String
    /// 已输入字数 / 上限。
    let promptCounter: @Sendable (Int, Int) -> String
    let promptTooLong: @Sendable (Int) -> String

    // 参数
    let sizeLabel: String
    let resolutionLabel: String
    /// 生成用的模型,放在历史行里当说明。
    let modelLabel: @Sendable (String) -> String

    // 提交
    let generateAction: String
    let generating: String
    let submitted: String
    /// 按钮上的悬浮说明:这件事要等。
    let takesAWhile: String
    /// 额度卡下的脚注:出来的图去哪了。两句分开,因为它们回答的是两个问题
    /// ——一句共用会让其中一处答非所问。
    let landsInGallery: String

    // 额度
    let remainingLabel: String
    /// 次数。中文的量词是「次」,英文要分单复数。
    let times: @Sendable (Int) -> String
    let todayLabel: String
    /// 今日已用 / 每日上限。
    let todayValue: @Sendable (Int, Int) -> String
    let monthlyLabel: String
    /// 本月余额 / 每月配给。余额可以靠签到超过配给,所以两个数不是包含关系。
    let monthlyValue: @Sendable (Int, Int) -> String
    /// 今天用完了:等明天。参数是每日上限。
    let dailyExhausted: @Sendable (Int) -> String
    /// 这个月用完了:靠签到。刻意不写死「1-3 次」,那是服务器上的可调值。
    let monthlyExhausted: String
    let goCheckin: String

    // 历史
    let historyTitle: String
    let historyEmpty: String
    let historyEmptyHint: String
    let statusLabel: @Sendable (AIGenStatus) -> String
    let inLibrary: String
    let viewInGallery: String
    let usePrompt: String
    let doneToast: String
    let failedToast: @Sendable (String) -> String

    // 提交失败
    let errDisabled: String
    let errNotVerified: String
    let errDailyLimit: String
    let errMonthlyExhausted: String
    let errBadPrompt: @Sendable (Int) -> String
    let errUpstream: @Sendable (String) -> String
}

extension GenerateStrings {
    static let zh = GenerateStrings(
        promptPlaceholder: "描述你想要的画面，越具体越好",
        promptCounter: { used, limit in "\(used) / \(limit)" },
        promptTooLong: { limit in "描述最多 \(limit) 字" },

        sizeLabel: "尺寸",
        resolutionLabel: "清晰度",
        modelLabel: { name in "模型 \(name)" },

        generateAction: "生成",
        generating: "生成中…",
        submitted: "已提交，出图约需几十秒",
        takesAWhile: "出图约需几十秒，期间可以去做别的",
        landsInGallery: "生成好的图会自动进图库，和手动上传的一样",

        remainingLabel: "还能生成",
        times: { n in "\(n) 次" },
        todayLabel: "今日已用",
        todayValue: { used, limit in "\(used) / \(limit)" },
        monthlyLabel: "本月余额",
        monthlyValue: { credits, monthly in "\(credits) / \(monthly)" },
        dailyExhausted: { limit in "今天的 \(limit) 次已经用完，明天再来" },
        monthlyExhausted: "这个月的次数已经用完，签到可以再攒一些",
        goCheckin: "去签到",

        historyTitle: "最近生成",
        historyEmpty: "还没有生成过",
        historyEmptyHint: "写一句描述，试试看",
        statusLabel: { s in
            switch s {
            case .pending: "排队中"
            case .running: "生成中"
            case .completed: "已完成"
            case .failed: "失败"
            }
        },
        inLibrary: "已存入图库",
        viewInGallery: "在图库里查看",
        usePrompt: "用这句再生成",
        doneToast: "生成完成，已存入图库",
        failedToast: { reason in "生成失败：\(reason)" },

        errDisabled: "这个部署没有开启 AI 生成",
        errNotVerified: "先验证邮箱才能使用生成",
        // 两句都得带上出路:今天用完的等明天,这个月用完的等明天也没用。
        errDailyLimit: "今天的生成次数已经用完了，明天再来",
        errMonthlyExhausted: "这个月的生成次数已经用完了，签到可以再攒一些",
        errBadPrompt: { limit in "描述不能为空，也不能超过 \(limit) 字" },
        errUpstream: { reason in "上游生成服务出错：\(reason)" })

    static let en = GenerateStrings(
        promptPlaceholder: "Describe the image you want — the more specific, the better",
        promptCounter: { used, limit in "\(used) / \(limit)" },
        promptTooLong: { limit in "\(limit) characters max" },

        sizeLabel: "Aspect Ratio",
        resolutionLabel: "Detail",
        modelLabel: { name in "Model \(name)" },

        generateAction: "Generate",
        generating: "Generating…",
        submitted: "Submitted — this usually takes under a minute",
        takesAWhile: "Usually under a minute — feel free to do something else",
        landsInGallery: "Finished images land in your gallery, same as uploaded ones",

        remainingLabel: "Left right now",
        times: { n in n == 1 ? "1 generation" : "\(n) generations" },
        todayLabel: "Used today",
        todayValue: { used, limit in "\(used) / \(limit)" },
        monthlyLabel: "This month",
        monthlyValue: { credits, monthly in "\(credits) / \(monthly)" },
        dailyExhausted: { limit in "That's all \(limit) for today — come back tomorrow" },
        monthlyExhausted: "You're out for this month. Checking in daily earns more.",
        goCheckin: "Check In",

        historyTitle: "Recent Generations",
        historyEmpty: "Nothing generated yet",
        historyEmptyHint: "Write a description and give it a try",
        statusLabel: { s in
            switch s {
            case .pending: "Queued"
            case .running: "Generating"
            case .completed: "Done"
            case .failed: "Failed"
            }
        },
        inLibrary: "In your gallery",
        viewInGallery: "View in Gallery",
        usePrompt: "Reuse This Prompt",
        doneToast: "Generated — saved to your gallery",
        failedToast: { reason in "Generation failed: \(reason)" },

        errDisabled: "This deployment doesn’t have AI generation turned on",
        errNotVerified: "Verify your email address before generating",
        errDailyLimit: "You’ve used all of today’s generations — come back tomorrow",
        errMonthlyExhausted: "You’re out for this month. Checking in daily earns more.",
        errBadPrompt: { limit in "A description is required, and it can’t exceed \(limit) characters" },
        errUpstream: { reason in "The upstream generator failed: \(reason)" })
}
