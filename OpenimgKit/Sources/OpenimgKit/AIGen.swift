import Foundation

/// 文生图。与后端 `internal/api/aigen_handlers.go` 一一对应。
///
/// 模型分成两半,是因为这件事本身分两半:`AIStatus` 回答「我这一刻还能生成
/// 几次」,`AIGeneration` 回答「刚才那一条到哪一步了」。提交只拿得到一条
/// pending 记录——上游要几十秒,请求挂在那里等只会先撞上代理超时——图得靠
/// 轮询 `/api/ai/generations` 等出来。

/// 这个部署有没有开 AI,以及当下的额度。
///
/// `enabled` 为假时功能应当**整个消失**而不是变灰:没配 APIMART_API_KEY 的
/// 自建实例根本没有这个能力,给一个点不动的按钮等于承诺了一件做不到的事。
public struct AIStatus: Decodable, Sendable, Equatable {
    public let enabled: Bool
    /// 本月余额。每月重置而非累加,签到可以往上加(封顶为月配额的两倍),
    /// 所以它可能大于 `monthly`。
    public let credits: Int
    public let usedToday: Int
    public let dailyLimit: Int
    /// 每月配给量,用来说明「一共有多少」,不是剩余。
    public let monthly: Int
    /// 这一刻真正还能生成几次 = min(credits, dailyLimit - usedToday)。
    public let remaining: Int
    public let sizes: [String]
    public let resolutions: [String]
    /// 本地免费额度见底后,还能不能从 pic.bi 扣。
    public let picbiLinked: Bool
    /// pic.bi 那边的余额。没关联、或那次查询失败时为 nil——它是锦上添花,
    /// 不该让对端抖一下就把整个状态接口拖垮。
    public let picbiCredits: Int?

    enum CodingKeys: String, CodingKey {
        case enabled, credits, monthly, remaining, sizes, resolutions
        case usedToday = "used_today"
        case dailyLimit = "daily_limit"
        case picbiLinked = "picbi_linked"
        case picbiCredits = "picbi_credits"
    }

    /// 关掉时服务器只回 `{"enabled": false}`,别的键根本不存在。逐个
    /// `decodeIfPresent` 而不是让整个响应解析失败——「没开」是正常答案。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        credits = try c.decodeIfPresent(Int.self, forKey: .credits) ?? 0
        usedToday = try c.decodeIfPresent(Int.self, forKey: .usedToday) ?? 0
        dailyLimit = try c.decodeIfPresent(Int.self, forKey: .dailyLimit) ?? 0
        monthly = try c.decodeIfPresent(Int.self, forKey: .monthly) ?? 0
        remaining = try c.decodeIfPresent(Int.self, forKey: .remaining) ?? 0
        sizes = try c.decodeIfPresent([String].self, forKey: .sizes) ?? []
        resolutions = try c.decodeIfPresent([String].self, forKey: .resolutions) ?? []
        picbiLinked = try c.decodeIfPresent(Bool.self, forKey: .picbiLinked) ?? false
        picbiCredits = try c.decodeIfPresent(Int.self, forKey: .picbiCredits)
    }

    /// 「用完了」有两种,解法完全不同:今日用完等明天就有,本月用完得靠签到
    /// 攒。界面必须说清是哪一种,否则用户只会一直点。
    public var dailyExhausted: Bool { dailyLimit > 0 && usedToday >= dailyLimit }
    public var monthlyExhausted: Bool { credits <= 0 }
    /// pic.bi 那边还剩多少能用。没关联就是 0。
    public var picbiRemaining: Int { picbiLinked ? (picbiCredits ?? 0) : 0 }

    /// 本地额度见底不等于不能生成:关联了 pic.bi 且那边还有钱时,服务端会
    /// 自动接管。只看 remaining 会把按钮封死在"pic.bi 正该出场"的那一刻,
    /// 整条付费路径永远走不到。
    public var canGenerate: Bool { enabled && (remaining > 0 || picbiRemaining > 0) }
}

/// 一条生成记录的状态。只有 completed/failed 是终态。
public enum AIGenStatus: String, Codable, Sendable, Hashable {
    /// charging 是「额度已扣、还没递交给上游」的一瞬,服务端用它做日限计数。
    case charging, pending, running, completed, failed

    public var isTerminal: Bool { self == .completed || self == .failed }

    /// 认不出的状态按「还在跑」处理。这个字段只会朝终态走,把未知当终态会让
    /// 界面提前宣布结束、停掉轮询,然后那条记录永远停在错的样子上。
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AIGenStatus(rawValue: raw) ?? .running
    }
}

/// 这条记录是凭空生成的,还是照着已有的图改出来的。
///
/// 两件事共用一张表、一套额度、一条轮询路径,只有这个字段把它们分开——界面
/// 靠它把「生成」和「修图」两页的历史各归各页。
public enum AIGenKind: String, Codable, Sendable, Hashable {
    case generate, edit

    /// 认不出就算文生图。功能上线前的存量记录 kind 是空字符串(后端不写迁移
    /// 脚本改历史),而那批记录只可能是文生图;把空值当成未知而让整页解析失败,
    /// 换来的是一个「历史突然全没了」的界面。
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AIGenKind(rawValue: raw) ?? .generate
    }
}

/// 一次生成的全过程记录。
///
/// `imageID` 只在 completed 后才有,对应的图片在 `AIGenerationPage.images`
/// 里,字段与图库那份完全一致——从入库那一刻起它就是一张普通图片。
public struct AIGeneration: Decodable, Sendable, Identifiable, Hashable {
    public let id: String
    public let prompt: String
    public let model: String
    public let size: String
    public let resolution: String
    public let status: AIGenStatus
    /// 失败原因,照实显示即可。失败会退还余额(后端做的),今日次数不退。
    public let error: String?
    public let imageID: String?
    public let credits: Int
    public let createdAt: Date
    public let doneAt: Date?
    public let kind: AIGenKind
    /// 这次修图用的原图 id,按提交时的顺序。后端存成逗号分隔的一串;拆开的
    /// 活放在这里做一次,不然每个调用点都要重写同一段 split。纯生成时为空。
    public let sourceIDs: [String]

    public var isEdit: Bool { kind == .edit }

    enum CodingKeys: String, CodingKey {
        case id, prompt, model, size, resolution, status, error, credits, kind
        case imageID = "image_id"
        case createdAt = "created_at"
        case doneAt = "done_at"
        case sourceIDs = "source_ids"
    }

    /// 手写而不是让编译器合成:`kind` 与 `source_ids` 在老服务器上根本不存在,
    /// 合成的实现遇到缺键会整条抛错,于是"连上一个旧实例"的症状会是历史全空。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        prompt = try c.decode(String.self, forKey: .prompt)
        model = try c.decode(String.self, forKey: .model)
        size = try c.decode(String.self, forKey: .size)
        resolution = try c.decode(String.self, forKey: .resolution)
        status = try c.decode(AIGenStatus.self, forKey: .status)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        imageID = try c.decodeIfPresent(String.self, forKey: .imageID)
        credits = try c.decode(Int.self, forKey: .credits)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        doneAt = try c.decodeIfPresent(Date.self, forKey: .doneAt)
        kind = try c.decodeIfPresent(AIGenKind.self, forKey: .kind) ?? .generate
        let raw = try c.decodeIfPresent(String.self, forKey: .sourceIDs) ?? ""
        sourceIDs = raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// `GET /api/ai/generations` 的回应。
public struct AIGenerationPage: Decodable, Sendable {
    public let generations: [AIGeneration]
    /// 按图片 id 索引,与图库列表返回的对象同构。
    public let images: [String: RemoteImage]

    enum CodingKeys: String, CodingKey { case generations, images }

    /// 一条记录都没有时 Go 那边的空切片会 marshal 成 `null`,不是 `[]`。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generations = try c.decodeIfPresent([AIGeneration].self, forKey: .generations) ?? []
        images = try c.decodeIfPresent([String: RemoteImage].self, forKey: .images) ?? [:]
    }

    public func image(for gen: AIGeneration) -> RemoteImage? {
        gen.imageID.flatMap { images[$0] }
    }

    /// 修图记录的原图。
    ///
    /// 只解析这份 map 里真有的 id:原图是图库里的普通图片,可能早在这条记录
    /// 之后被删了。取不到的直接跳过而不是留空位——一行缩略图里夹着灰块,看
    /// 起来像加载失败,而事实是那张图不在了。
    public func sources(for gen: AIGeneration) -> [RemoteImage] {
        gen.sourceIDs.compactMap { images[$0] }
    }
}

/// 提交失败的几种结局。
///
/// 单独一个错误类型,而不是复用 `OpenimgError`:同样是 429,在上传那条路上
/// 意思是「传太快了,等一分钟」,在这条路上意思是「今天的次数用完了,等明
/// 天」——把后者说成前者是个会让人白等的错建议。402 同理,那是「这个月用
/// 完了」,得靠签到而不是靠等。
public enum AIGenError: Error, LocalizedError, Equatable, Sendable {
    case disabled(String)
    case notVerified(String)
    case dailyLimit(String)
    case monthlyExhausted(String)
    case badPrompt(String)
    /// 一张原图都没给。界面本该拦住(没选图时提交按钮是灰的),留着是为了
    /// 万一——服务器说不行的时候,得说得出是哪儿不行。
    case noSource(String)
    /// 给的原图不存在,或者不属于这个账号。多半是选好图之后又在图库里把它
    /// 删了,所以文案要指向"重新选一张",而不是"稍后重试"。
    case sourceMissing(String)
    case upstream(String)
    case other(status: Int, message: String)

    /// 服务器带回的原话。界面优先用自己的 i18n 文案,拿不准时退回这一句。
    public var serverMessage: String {
        switch self {
        case .disabled(let m), .notVerified(let m), .dailyLimit(let m),
             .monthlyExhausted(let m), .badPrompt(let m), .upstream(let m),
             .noSource(let m), .sourceMissing(let m):
            m
        case .other(_, let m):
            m
        }
    }

    public var errorDescription: String? {
        if !serverMessage.isEmpty { return serverMessage }
        return switch self {
        case .disabled: "这个部署没有开启 AI 生成"
        case .notVerified: "请先验证邮箱"
        case .dailyLimit: "今天的生成次数已用完"
        case .monthlyExhausted: "这个月的生成次数已用完"
        case .badPrompt: "描述为空或过长"
        case .noSource: "至少要选一张原图"
        case .sourceMissing: "选中的原图已经不在了"
        case .upstream: "上游生成服务暂时不可用"
        case .other(let status, _): "服务器返回 \(status)"
        }
    }

    static func from(status: Int, body: Data) -> AIGenError {
        let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let message = obj["error"] as? String ?? ""
        // code 是后端专门给机器看的标识,与 error 里那句已经翻译过的人话分开。
        // 早先这里是拿 message 去 contains 匹配的,那必然落空——用户是中文
        // 界面时收到的是「至少要选一张图片」,里面没有任何 ASCII 标识。
        let code = obj["code"] as? String ?? ""
        return switch status {
        // 400 在修图这条路上有三种意思(描述空、描述太长、没给图),状态码分
        // 不开,靠 code 区分。认不出就退回"描述有问题",那是 400 里最常见的
        // 一种,也是没有 code 的旧后端唯一可能的意思。
        case 400: code == "no_source" ? .noSource(message) : .badPrompt(message)
        case 402: .monthlyExhausted(message)
        case 403: .notVerified(message)
        // 认 code 而不是只认状态码:一个没有修图接口的旧实例同样回 404,那时
        // 说「原图不在了」是句凭空捏造的解释。
        case 404 where code == "source_missing": .sourceMissing(message)
        case 429: .dailyLimit(message)
        case 502: .upstream(message)
        case 503: .disabled(message)
        default: .other(status: status, message: message)
        }
    }
}

/// 描述的长度上限,与后端 `handleAIGenerate` 里的那道闸门一致。本地先拦,
/// 免得白跑一趟——按字符数(rune)算,不是字节数。
public let aiPromptLimit = 1000

/// 一次修图最多带几张原图。上游本身收得下 16 张,这里的 4 是后端接口定下的
/// 上限;本地先拦是为了让「加图」按钮在第 4 张之后就消失,而不是让人选到第
/// 5 张再被 400 打回来。
public let aiEditSourceLimit = 4

/// 概览页那张 AI 卡要显示的东西。
///
/// 存在的理由是「三本账不能摆成一池」:今日次数、本月额度、pic.bi 余额是三个
/// 互不相通的池子,而用完之后的解法也不同——今日用完只能等明天,本月用完可以去
/// 签到,pic.bi 用完要去那边充。混在一起显示,用户会以为总数是它们的和。
public struct AIQuotaReadout: Sendable, Equatable {
    /// 最大的那个数字:这一刻还能生成几次。
    public let headline: Int
    /// headline 是不是来自 pic.bi(本地额度已经见底)。
    public let fromPicbi: Bool
    public let usedToday: Int
    public let dailyLimit: Int
    /// 本月剩余与配给量。剩余可能大于配给量——签到会往上加。
    public let monthlyLeft: Int
    public let monthlyTotal: Int
    public let picbi: PicbiBalance
    /// 现在为什么不能生成。nil 表示能生成。
    public let blocked: Blocked?

    public enum PicbiBalance: Sendable, Equatable {
        /// 没关联。
        case none
        case known(Int)
        /// 关联了,但这次没查到余额。
        ///
        /// **必须与 known(0) 分开。** 显示成 0 会让人以为钱花光了,而实际上只是
        /// 对端抖了一下;这两种情况用户要做的事完全相反(一个去充值,一个等一会
        /// 儿再试)。
        case unknown
    }

    public enum Blocked: Sendable, Equatable {
        /// 今天的次数用完了,等明天。
        case daily
        /// 本月额度用完了,去签到。
        case monthly
    }

    public init(_ s: AIStatus) {
        usedToday = s.usedToday
        dailyLimit = s.dailyLimit
        monthlyLeft = s.credits
        monthlyTotal = max(s.monthly, s.credits)

        picbi = {
            guard s.picbiLinked else { return .none }
            guard let n = s.picbiCredits else { return .unknown }
            return .known(n)
        }()

        let dailyLeft = max(0, s.dailyLimit - s.usedToday)
        let localLeft = s.remaining

        if localLeft > 0 {
            headline = localLeft
            fromPicbi = false
            blocked = nil
        } else if case .known(let n) = picbi, n > 0 {
            // 本地见底但 pic.bi 还有:那就还能生成,只是花的是另一本账的钱。
            headline = n
            fromPicbi = true
            blocked = nil
        } else if case .unknown = picbi {
            // 查不到余额时不该拦人:也许有钱。让他点,真不行由接口报错——
            // 比在这里猜一个"没有"要诚实。
            headline = 0
            fromPicbi = false
            blocked = nil
        } else {
            headline = 0
            fromPicbi = false
            // 本月和今日同时用尽时报「本月」。两者的解法不同,而本月那条是用户
            // 现在就能动手的(去签到),今日那条只能等——先说能动手的那个。
            blocked = s.credits <= 0 ? .monthly : (dailyLeft <= 0 ? .daily : .monthly)
        }
    }
}
