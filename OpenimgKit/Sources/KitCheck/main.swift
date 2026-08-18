import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import OpenimgKit

// Self-checks for OpenimgKit. Run with `swift run KitCheck`; exits non-zero on
// the first failure so CI can gate on it. See Package.swift for why this is an
// executable and not a test target.

var failures = 0
var checks = 0

// @MainActor because top-level code in main.swift is main-actor isolated under
// Swift 6, and these mutate counters that live there.
@MainActor
func check(_ name: String, _ ok: @autoclosure () -> Bool) {
    checks += 1
    if ok() {
        print("  ✓ \(name)")
    } else {
        print("  ✗ \(name)")
        failures += 1
    }
}

@MainActor
func section(_ s: String) { print("\n\(s)") }

// MARK: - Server address

section("服务器地址")

// The token rides in a header on every request, so a typo'd hostname over
// plain http hands it to whoever answers.
do {
    _ = try OpenimgClient(server: URL(string: "http://example.com")!, token: "oimg_x")
    check("明文 http 被拒绝", false)
} catch let e as OpenimgError {
    check("明文 http 被拒绝", e == .insecureServer(host: "example.com"))
} catch {
    check("明文 http 被拒绝", false)
}

for host in ["http://localhost:8080", "http://127.0.0.1:8080", "https://openimg.io"] {
    var ok = false
    do {
        _ = try OpenimgClient(server: URL(string: host)!, token: "oimg_x")
        ok = true
    } catch { ok = false }
    check("\(host) 放行", ok)
}

// MARK: - Error mapping

section("错误映射")

let resp429 = HTTPURLResponse(url: URL(string: "https://x")!, statusCode: 429,
                              httpVersion: nil, headerFields: nil)!

// 429 arrives for two unrelated reasons. The per-minute limit clears on its
// own; the daily upload count does not clear until tomorrow. A tool that
// uploads screenshots hits the second one far more often, and telling the user
// to "try again shortly" there is simply wrong.
check("每日上限识别为 dailyLimitReached",
      OpenimgClient.failure(status: 429,
                            body: Data(#"{"error":"今日上传数量已达上限","used":50,"limit":50}"#.utf8),
                            headers: resp429) == .dailyLimitReached(used: 50, limit: 50))

check("突发限流识别为 rateLimited",
      OpenimgClient.failure(status: 429,
                            body: Data(#"{"error":"上传过于频繁","retry_after":37}"#.utf8),
                            headers: resp429) == .rateLimited(retryAfter: 37))

let respRetry = HTTPURLResponse(url: URL(string: "https://x")!, statusCode: 429,
                                httpVersion: nil, headerFields: ["Retry-After": "12"])!
check("响应体没带秒数时回退到 Retry-After 头",
      OpenimgClient.failure(status: 429, body: Data("{}".utf8), headers: respRetry)
        == .rateLimited(retryAfter: 12))

let resp507 = HTTPURLResponse(url: URL(string: "https://x")!, statusCode: 507,
                              httpVersion: nil, headerFields: nil)!
check("507 识别为配额耗尽",
      OpenimgClient.failure(status: 507, body: Data(#"{"error":"空间不足"}"#.utf8),
                            headers: resp507) == .quotaExhausted("空间不足"))

let resp401 = HTTPURLResponse(url: URL(string: "https://x")!, statusCode: 401,
                              httpVersion: nil, headerFields: nil)!
check("401 识别为令牌无效",
      OpenimgClient.failure(status: 401, body: Data(#"{"error":"auth: token expired"}"#.utf8),
                            headers: resp401) == .unauthorized("auth: token expired"))

// MARK: - Multipart

section("multipart 组装")

// A filename carrying a quote or a newline would otherwise break out of the
// Content-Disposition header and let the caller forge extra parts.
let hdr = MultipartBody.header(fieldName: "file", filename: "a\"b\r\nc.png", boundary: "B")
check("文件名里的引号被转义", hdr.contains(#"filename="a\"bc.png""#))
check("文件名里的换行被去掉", !hdr.contains("\na"))
// The blank line is what separates headers from body. Without it the server
// reads the image bytes as more header lines and the part is malformed.
check("头部以空行收尾", hdr.hasSuffix("\r\n\r\n"))
check("头部恰好三行", hdr.components(separatedBy: "\r\n").count == 5)

check("HEIC 的 MIME", MultipartBody.mimeType(for: "photo.HEIC") == "image/heic")
check("未知扩展名回退", MultipartBody.mimeType(for: "x.zzz") == "application/octet-stream")

do {
    let dir = FileManager.default.temporaryDirectory
    let src = dir.appendingPathComponent("kitcheck-\(UUID().uuidString).png")
    let payload = Data((0..<300_000).map { UInt8($0 % 251) }) // 越过 1 MB 分块边界
    try payload.write(to: src)
    defer { try? FileManager.default.removeItem(at: src) }

    let out = try MultipartBody.write(fileURL: src, fieldName: "file",
                                      filename: "t.png", boundary: "BOUND")
    defer { try? FileManager.default.removeItem(at: out) }
    let body = try Data(contentsOf: out)

    check("以 boundary 开头", body.starts(with: Data("--BOUND\r\n".utf8)))
    check("以结束 boundary 收尾", body.suffix(13) == Data("\r\n--BOUND--\r\n".utf8))
    check("图片内容在分块写入中未被改动", body.range(of: payload) != nil)
} catch {
    check("multipart 写入不抛错（\(error)）", false)
}

// MARK: - Decoding

section("响应解析")

let dec = JSONDecoder()
dec.dateDecodingStrategy = .iso8601WithFractionalSeconds

// Go's time.Time marshals with nanoseconds, and .iso8601 rejects that outright
// — one fractional second makes the entire response fail to decode.
let withNanos = """
{"id":"1","orig_name":"a.png","ext":"png","width":10,"height":8,"size_stored":123,
 "url":"https://cdn/x.png","thumb_url":"https://cache/x.webp","markdown":"M",
 "html":"H","bbcode":"B","created_at":"2026-08-05T14:32:08.123456789Z"}
"""
if let img = try? dec.decode(RemoteImage.self, from: Data(withNanos.utf8)) {
    check("带纳秒的时间可解析", true)
    check("short_url 缺失不影响解析", img.shortURL == nil)
    check("链接格式取服务端拼好的字符串", LinkFormat.markdown.render(img) == "M")
    check("四种链接格式齐全", LinkFormat.allCases.count == 4)
} else {
    check("带纳秒的时间可解析", false)
}

let plain = """
{"id":"1","orig_name":"a.png","ext":"png","width":1,"height":1,"size_stored":1,
 "url":"U","thumb_url":"T","markdown":"M","html":"H","bbcode":"B",
 "created_at":"2026-08-05T14:32:08Z"}
"""
check("不带小数秒的时间同样可解析",
      (try? dec.decode(RemoteImage.self, from: Data(plain.utf8))) != nil)

// The tier block is what lets a client reject a file locally instead of
// spending one of the day's uploads finding the limit out from a 413.
let quotaJSON = """
{"quota_bytes":1073741824,"used_bytes":1024,"available_bytes":1073740800,
 "image_count":3,"uploads_today":7,
 "tier":{"name":"free","max_file_size":20971520,"daily_upload_count":50,
         "allowed_formats":["jpeg","png","webp"]}}
"""
if let q = try? dec.decode(Quota.self, from: Data(quotaJSON.utf8)) {
    check("配额解析", q.availableBytes == 1_073_740_800)
    check("档位限制解析", q.tier.maxFileSize == 20_971_520 && q.tier.dailyUploadCount == 50)
    check("允许格式解析", q.tier.allowedFormats.contains("png"))
} else {
    check("配额解析", false)
}

// 服务端的 avatar_url 带 omitempty：没有头像的账号响应里根本没有这个键，
// 声明成非可选会让整条账号解析失败，而症状是"登录不上"而不是"头像没了"。
section("账号解析")

let withAvatar = #"{"id":"1","email":"a@b.c","name":"西风","role":"admin","avatar_url":"https://cdn/x.avif"}"#
if let a = try? dec.decode(Account.self, from: Data(withAvatar.utf8)) {
    check("带头像可解析", a.avatarURL == "https://cdn/x.avif")
    check("首字母取昵称而非邮箱", a.initial == "西")
} else {
    check("带头像可解析", false)
}

let noAvatar = #"{"id":"1","email":"zoe@b.c","name":"","role":"user"}"#
if let a = try? dec.decode(Account.self, from: Data(noAvatar.utf8)) {
    check("缺 avatar_url 仍可解析", a.avatarURL == nil)
    check("无昵称时首字母回退到邮箱", a.initial == "Z")
    // 旧服务器不认识 pic.bi。字段缺失必须落到"未关联",而不是解析失败——
    // 症状同样会是"登录不上"。
    check("缺 picbi_connected 时按未关联", (a.picbiConnected ?? false) == false)
} else {
    check("缺 avatar_url 仍可解析", false)
}

let picbiLinked = #"{"id":"1","email":"a@b.c","name":"n","role":"user","picbi_connected":true}"#
check("picbi_connected 解析",
      (try? dec.decode(Account.self, from: Data(picbiLinked.utf8)))?.picbiConnected == true)

section("Passkey 解析")

// 服务端用 time.RFC3339 格式化，不带小数秒；而客户端解码器全局设的是
// iso8601WithFractionalSeconds。这两处对不上会在运行时整个响应解析失败。
let pkJSON = """
{"passkeys":[
 {"id":"a1","name":"MacBook Pro","created_at":"2026-08-01T10:30:00Z",
  "last_used_at":"2026-08-05T18:00:00Z"},
 {"id":"a2","name":"iPhone","created_at":"2026-07-20T09:00:00Z"}]}
"""
struct PKWrap: Decodable { let passkeys: [PasskeyCredential]? }
let pkDec = JSONDecoder()
pkDec.dateDecodingStrategy = .iso8601WithFractionalSeconds   // 与 Client 同款
let pk = try? pkDec.decode(PKWrap.self, from: Data(pkJSON.utf8))
check("RFC3339 无小数秒也能解析", pk?.passkeys?.count == 2)
check("解出了创建时间", pk?.passkeys?.first?.createdAt != nil)
check("缺 last_used_at 不影响解析", pk?.passkeys?.last?.lastUsedAt == nil)
check("外层 key 是 passkeys 而非 credentials", pk?.passkeys?.first?.name == "MacBook Pro")
check("时间戳无法解析时返回 nil 而不是抛错",
      PasskeyCredential.date("不是时间") == nil && PasskeyCredential.date(nil) == nil)

section("AI 文生图解析")

// 没配 APIMART_API_KEY 的部署只回这一个键。声明成非可选会让整条状态解析
// 失败,而症状是"AI 入口时有时无"而不是"这个部署没开 AI"。
if let off = try? dec.decode(AIStatus.self, from: Data(#"{"enabled":false}"#.utf8)) {
    check("关闭时只有 enabled 也能解析", !off.enabled)
    check("缺失的额度字段归零", off.credits == 0 && off.remaining == 0 && off.sizes.isEmpty)
} else {
    check("关闭时只有 enabled 也能解析", false)
}

let statusJSON = """
{"enabled":true,"credits":42,"used_today":5,"daily_limit":5,"monthly":50,
 "remaining":0,"sizes":["1:1","16:9"],"resolutions":["1k","2k"]}
"""
if let s = try? dec.decode(AIStatus.self, from: Data(statusJSON.utf8)) {
    check("额度字段的 snake_case 映射", s.usedToday == 5 && s.dailyLimit == 5)
    // 「用完了」的两种解法完全不同:今天用完等明天,这个月用完得靠签到。
    // 界面按这两个布尔选句子,选反了就是一句让人白等一天的话。
    check("余额还有、今日用完 → 今日上限", s.dailyExhausted && !s.monthlyExhausted)
    check("remaining 为 0 时不可生成", !s.canGenerate)
} else {
    check("额度字段的 snake_case 映射", false)
}

let outOfCredits = """
{"enabled":true,"credits":0,"used_today":1,"daily_limit":5,"monthly":50,"remaining":0,
 "sizes":[],"resolutions":[]}
"""
check("余额为零识别为本月用完",
      (try? dec.decode(AIStatus.self, from: Data(outOfCredits.utf8)))?.monthlyExhausted == true)

// 每日上限为 0(后端视作不限)的部署里 remaining 也会是 0,但那不叫"今天
// 用完了"——界面若照着 remaining 说话,会冒出"今天的 0 次已经用完"。
let noDailyCap = """
{"enabled":true,"credits":3,"used_today":2,"daily_limit":0,"monthly":50,"remaining":0,
 "sizes":[],"resolutions":[]}
"""
check("每日上限为 0 时不算今日用完",
      (try? dec.decode(AIStatus.self, from: Data(noDailyCap.utf8)))?.dailyExhausted == false)

// Go 的空切片 marshal 成 null 而不是 []。
check("generations 为 null 时解析成空数组",
      (try? dec.decode(AIGenerationPage.self,
                       from: Data(#"{"generations":null,"images":{}}"#.utf8)))?.generations.isEmpty == true)

let genJSON = """
{"generations":[
 {"id":"g1","prompt":"一只猫","model":"gpt-image-2","size":"1:1","resolution":"1k",
  "status":"completed","image_id":"i1","credits":1,
  "created_at":"2026-08-17T10:00:00.123456789Z","done_at":"2026-08-17T10:00:41.5Z"},
 {"id":"g2","prompt":"待办","model":"gpt-image-2","size":"16:9","resolution":"2k",
  "status":"pending","credits":1,"created_at":"2026-08-17T10:02:00Z"}],
 "images":{"i1":{"id":"i1","orig_name":"一只猫.png","ext":"png","width":1024,"height":1024,
   "size_stored":900,"url":"U","thumb_url":"T","markdown":"M","html":"H","bbcode":"B",
   "created_at":"2026-08-17T10:00:41Z"}}}
"""
if let page = try? dec.decode(AIGenerationPage.self, from: Data(genJSON.utf8)) {
    check("生成记录解析", page.generations.count == 2)
    check("缺 error/image_id/done_at 仍可解析",
          page.generations[1].error == nil && page.generations[1].imageID == nil
            && page.generations[1].doneAt == nil)
    check("完成的记录能取到同构的图片对象",
          page.image(for: page.generations[0])?.thumbURL == "T")
    check("未完成的记录取不到图片", page.image(for: page.generations[1]) == nil)
    check("终态判定", page.generations[0].status.isTerminal && !page.generations[1].status.isTerminal)
} else {
    check("生成记录解析", false)
}

// 服务端将来加一个状态,不该让整页解析失败,更不该被当成终态——那会让轮询
// 提前收工,记录永远停在错的样子上。
check("认不出的状态按在途处理",
      (try? JSONDecoder().decode(AIGenStatus.self, from: Data("\"queued\"".utf8)))?.isTerminal == false)

// 402 与 429 在这条路上是两件事:一个靠签到,一个等明天。通用的 failure()
// 会把 429 说成"传太快了,等 60 秒",那是句会让人白等的错建议。
check("429 是今日用完而非限流",
      AIGenError.from(status: 429, body: Data(#"{"error":"今日已达上限"}"#.utf8))
        == .dailyLimit("今日已达上限"))
check("402 是本月用完",
      AIGenError.from(status: 402, body: Data(#"{"error":"次数已用完"}"#.utf8))
        == .monthlyExhausted("次数已用完"))
check("503 是这个部署没开",
      AIGenError.from(status: 503, body: Data("{}".utf8)) == .disabled(""))
// 后端在邮箱没验证时挡在额度之前,这一条与"次数用完"是两件事。
check("403 是邮箱未验证",
      AIGenError.from(status: 403, body: Data(#"{"error":"请先验证邮箱"}"#.utf8))
        == .notVerified("请先验证邮箱"))
check("没带 error 字段时退回本地兜底说法",
      AIGenError.from(status: 503, body: Data("{}".utf8)).errorDescription == "这个部署没有开启 AI 生成")

section("AI 修图")

// 上面那两条记录都没有 kind:功能上线前的存量记录就长这样,而它们只可能是
// 文生图。当成未知而让整页解析失败,症状会是"历史突然全没了"。
if let page = try? dec.decode(AIGenerationPage.self, from: Data(genJSON.utf8)) {
    check("缺 kind 的存量记录算作文生图",
          page.generations.allSatisfy { $0.kind == .generate && !$0.isEdit })
    check("缺 source_ids 时原图为空", page.generations[0].sourceIDs.isEmpty)
}

let editJSON = """
{"generations":[
 {"id":"e1","prompt":"去掉水印","model":"gpt-image-2","size":"1:1","resolution":"1k",
  "status":"completed","image_id":"i2","credits":1,"kind":"edit",
  "source_ids":"s1,s2","created_at":"2026-08-17T10:00:00Z","done_at":"2026-08-17T10:00:30Z"},
 {"id":"e2","prompt":"换背景","model":"gpt-image-2","size":"1:1","resolution":"1k",
  "status":"pending","credits":1,"kind":"","source_ids":"","created_at":"2026-08-17T10:05:00Z"}],
 "images":{"s1":{"id":"s1","orig_name":"原图.png","ext":"png","width":8,"height":8,
   "size_stored":1,"url":"U1","thumb_url":"T1","markdown":"M","html":"H","bbcode":"B",
   "created_at":"2026-08-17T09:00:00Z"}}}
"""
if let page = try? dec.decode(AIGenerationPage.self, from: Data(editJSON.utf8)) {
    check("kind=edit 解析", page.generations[0].isEdit)
    check("source_ids 按逗号拆开", page.generations[0].sourceIDs == ["s1", "s2"])
    // 后端不写迁移脚本改存量,空字符串就是"没标过种类"。
    check("kind 为空串按文生图处理", page.generations[1].kind == .generate)
    check("source_ids 为空串不产生空 id", page.generations[1].sourceIDs.isEmpty)
    // 原图是图库里的普通图片,可能在这条记录之后被删了——取不到就跳过,
    // 一行缩略图里夹着灰块看起来像加载失败,而事实是那张图不在了。
    check("原图只解析 map 里真有的那些",
          page.sources(for: page.generations[0]).map(\.id) == ["s1"])
} else {
    check("kind=edit 解析", false)
}

// 400 在修图这条路上有三种意思,状态码分不开,靠 code 区分。
//
// error 里是已经翻译过的人话,拿它去匹配标识必然落空——中文界面收到的是
// 「至少要选一张图片」,里面没有任何 ASCII 标识。这两条断言按后端真实发出
// 的报文形状写:error 是译文,code 是给机器看的。
check("400 带 code=no_source 是没给原图",
      AIGenError.from(status: 400,
                      body: Data(#"{"error":"至少要选一张图片","code":"no_source"}"#.utf8))
        == .noSource("至少要选一张图片"))
check("光看译文不认标识",
      AIGenError.from(status: 400, body: Data(#"{"error":"至少要选一张图片"}"#.utf8))
        == .badPrompt("至少要选一张图片"))
check("其余 400 仍是描述有问题",
      AIGenError.from(status: 400, body: Data(#"{"error":"描述太长了"}"#.utf8))
        == .badPrompt("描述太长了"))
check("404 带 code=source_missing 是原图不在了",
      AIGenError.from(status: 404,
                      body: Data(#"{"error":"选中的图片不存在","code":"source_missing"}"#.utf8))
        == .sourceMissing("选中的图片不存在"))
// 没有修图接口的旧实例同样回 404。那时说"原图不在了"是句凭空捏造的解释。
check("旧实例的 404 不冒充原图丢失",
      AIGenError.from(status: 404, body: Data("{}".utf8)) == .other(status: 404, message: ""))

section("图库网格")

// 默认窗口 1240x820 下网格的可用区。这两个数是从离屏渲染里打印出来的实测
// 值，不是从内边距推算的——推算过一次，结果差了 180pt。
let deskGrid = CGSize(width: 972, height: 637)
let f50 = GridFit.solve(count: 50, in: deskGrid, spacing: 12, minCell: 72)
check("50 张不用滚动", !f50.scrolls)
check("行列容得下 50 张（\(f50.columns)x\(f50.rows)）", f50.columns * f50.rows >= 50)
check("横向不溢出",
      Double(f50.columns) * f50.cellWidth + 12 * Double(f50.columns - 1) <= 972.5)
check("纵向不溢出",
      Double(f50.rows) * f50.cellHeight + 12 * Double(f50.rows - 1) <= 637.5)
check("格子是正方（\(Int(f50.cellWidth))x\(Int(f50.cellHeight))）",
      f50.cellWidth == f50.cellHeight)
check("格子不至于太小", f50.cellWidth >= 72)

// 换页大小：都要能铺满，且张数越多格子越小
let sizes = [25, 50, 100, 200].map { GridFit.solve(count: $0, in: deskGrid, spacing: 12, minCell: 72) }
// 默认窗口在 72pt 下限内最多摆 13x7=91 格，所以 100/200 注定要滚动。
// 这正是想要的：宁可滚动，也不把格子压到看不清。
check("25/50 铺满不滚动", !sizes[0].scrolls && !sizes[1].scrolls)
check("100/200 改为滚动而不是压小格子",
      sizes[2].scrolls && sizes[3].scrolls
      && sizes[2].cellWidth >= 72 && sizes[3].cellWidth >= 72)
check("张数越多格子越小",
      sizes[0].cellWidth > sizes[1].cellWidth && sizes[1].cellWidth > sizes[2].cellWidth)

// 最小窗口：宁可滚动也不要 40pt 的格子
let tiny = GridFit.solve(count: 50, in: CGSize(width: 632, height: 362), spacing: 12, minCell: 72)
check("窗口太小时滚动", tiny.scrolls)
check("滚动时格子仍不小于下限", tiny.cellWidth >= 72)

// 少量图片时不该被拉成长条
let three = GridFit.solve(count: 3, in: deskGrid, spacing: 12, minCell: 72)
check("3 张时也是正方", three.cellWidth == three.cellHeight)

// 退化输入
check("0 张不崩", GridFit.solve(count: 0, in: deskGrid, spacing: 12, minCell: 72).columns >= 1)
check("尺寸为 0 不崩", GridFit.solve(count: 50, in: .zero, spacing: 12, minCell: 72).scrolls)
check("尺寸为 NaN 不崩",
      GridFit.solve(count: 50, in: CGSize(width: CGFloat.nan, height: CGFloat.nan),
                    spacing: 12, minCell: 72).scrolls)

section("本地缩放")

/// The sample is drawn here rather than read from disk.
///
/// It used to point at a file in a scratch directory, guarded by a
/// `fileExists` check that printed "跳过" and moved on. The directory was
/// eventually cleaned, and this section quietly shrank from six assertions to
/// one — the suite still said "全部通过" while testing almost nothing. A test
/// that can skip itself is a test that will.
func makeSamplePNG(width: Int, height: Int) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("kitcheck-\(width)x\(height).png")

    // Per-pixel noise, written straight into the buffer.
    //
    // The first attempt filled 4x4 blocks of flat colour, which PNG squeezed to
    // 94 KB for a 2752x1536 image — and downscaling it produced a *larger* file
    // (518 KB), because interpolation turns crisp block edges into gradients
    // that no longer run-length encode. LocalResize correctly refused to call
    // that a shrink, so the assertion failed on a fixture that was nothing like
    // a photograph. Real photographs are incompressible at the pixel level,
    // which is the property being tested.
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    var seed: UInt64 = 0x2545F4914F6CDD1D
    for i in stride(from: 0, to: pixels.count, by: 4) {
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        pixels[i]     = UInt8(truncatingIfNeeded: seed)
        pixels[i + 1] = UInt8(truncatingIfNeeded: seed >> 8)
        pixels[i + 2] = UInt8(truncatingIfNeeded: seed >> 16)
        pixels[i + 3] = 255
    }

    let img: CGImage = pixels.withUnsafeMutableBytes { buf in
        let ctx = CGContext(data: buf.baseAddress, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    return url
}

let bigPNG = makeSamplePNG(width: 2752, height: 1536)
defer { try? FileManager.default.removeItem(at: bigPNG) }

let before = (try! bigPNG.resourceValues(forKeys: [.fileSizeKey]).fileSize)!

if let out = LocalResize.shrink(bigPNG, maxWidth: 1920) {
    defer { try? FileManager.default.removeItem(at: out) }
    let after = (try! out.resourceValues(forKeys: [.fileSizeKey]).fileSize)!
    let src = CGImageSourceCreateWithURL(out as CFURL, nil)!
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
    let w = props[kCGImagePropertyPixelWidth] as! Int

    check("缩到了指定宽度（\(w)px）", w == 1920)
    check("格式没变（仍是 PNG）", (CGImageSourceGetType(src)! as String) == UTType.png.identifier)
    check("体积确实变小（\(before/1024)KB → \(after/1024)KB）", after < before)
} else {
    check("2752px 的图应当被缩", false)
}

// 已经够小的不该动，白花一次编码
check("宽度已达标时返回 nil", LocalResize.shrink(bigPNG, maxWidth: 4000) == nil)
check("未设上限时返回 nil", LocalResize.shrink(bigPNG, maxWidth: 0) == nil)

check("非图片文件安全返回 nil",
      LocalResize.shrink(URL(fileURLWithPath: "/etc/hosts"), maxWidth: 1920) == nil)

// MARK: - WatchManifest

section("WatchManifest(监控目录清单)")

var wm = WatchManifest()
let we = WatchManifest.Entry(path: "/a/p.jpg", size: 100, mtime: 1000,
                             sha256: "aa11", imageID: "id1", url: "https://x/p.webp")
wm.record(we)
check("收录后快路径命中", wm.isCurrent(path: "/a/p.jpg", size: 100, mtime: 1000))
check("size 变了快路径失效", !wm.isCurrent(path: "/a/p.jpg", size: 101, mtime: 1000))
check("mtime 变了快路径失效", !wm.isCurrent(path: "/a/p.jpg", size: 100, mtime: 2000))
check("未收录路径不命中", !wm.isCurrent(path: "/a/q.jpg", size: 100, mtime: 1000))
check("按 sha 找到已传内容", wm.known(sha: "aa11")?.imageID == "id1")
check("陌生 sha 返回 nil", wm.known(sha: "bb22") == nil)

// 改名收编:同内容换路径不重传,新路径指向旧上传记录
wm.adopt(path: "/a/renamed.jpg", size: 100, mtime: 3000, from: we)
check("收编后新路径快路径命中", wm.isCurrent(path: "/a/renamed.jpg", size: 100, mtime: 3000))
check("收编保留原上传信息", wm.entry(path: "/a/renamed.jpg")?.url == "https://x/p.webp")
check("原路径仍在(复制场景两路径都合法)", wm.entry(path: "/a/p.jpg") != nil)

// 序列化往返
if let data = try? wm.encoded() {
    let back = WatchManifest.decode(data)
    check("编码往返条目数一致", back.count == wm.count)
    check("往返后 sha 索引重建", back.known(sha: "aa11")?.url == "https://x/p.webp")
} else {
    check("清单可编码", false)
}
check("损坏数据解码为空清单而非崩溃", WatchManifest.decode(Data("not json".utf8)).count == 0)

// MARK: - EditGeometry(编辑几何)

section("EditGeometry(编辑几何)")

let full = CGRect(x: 0, y: 0, width: 1, height: 1)
check("整幅裁剪夹取后不变", EditGeometry.clampCrop(full) == full)
check("越界裁剪被夹回 0-1", {
    let r = EditGeometry.clampCrop(CGRect(x: -0.2, y: 0.5, width: 0.4, height: 0.9))
    return r.minX >= 0 && r.minY >= 0 && r.maxX <= 1.0001 && r.maxY <= 1.0001
}())
check("零面积裁剪被撑到最小边", {
    let r = EditGeometry.clampCrop(CGRect(x: 0.5, y: 0.5, width: 0, height: 0))
    return r.width >= 0.02 && r.height >= 0.02
}())

check("旋转 1 次尺寸互换", EditGeometry.rotatedSize(CGSize(width: 300, height: 200), quarters: 1) == CGSize(width: 200, height: 300))
check("旋转 2 次尺寸不变", EditGeometry.rotatedSize(CGSize(width: 300, height: 200), quarters: 2) == CGSize(width: 300, height: 200))

// 顺时针 90°:左上角 (0,0) 应到右上角 (1,0)
check("点旋转:左上→右上", EditGeometry.rotateQuarterCW(CGPoint(x: 0, y: 0)) == CGPoint(x: 1, y: 0))
check("点旋转:中心不动", EditGeometry.rotateQuarterCW(CGPoint(x: 0.5, y: 0.5)) == CGPoint(x: 0.5, y: 0.5))
check("点旋转四次回原位", {
    var p = CGPoint(x: 0.2, y: 0.7)
    for _ in 0..<4 { p = EditGeometry.rotateQuarterCW(p) }
    return abs(p.x - 0.2) < 1e-9 && abs(p.y - 0.7) < 1e-9
}())
check("矩形旋转四次回原位", {
    var r = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
    for _ in 0..<4 { r = EditGeometry.rotateQuarterCW(r) }
    return abs(r.minX - 0.1) < 1e-9 && abs(r.minY - 0.2) < 1e-9
        && abs(r.width - 0.3) < 1e-9 && abs(r.height - 0.4) < 1e-9
}())

check("配方整体旋转:计数+1 且笔迹跟转", {
    var s = EditSpec()
    s.strokes = [MosaicStroke(points: [CGPoint(x: 0, y: 0)], radius: 0.02)]
    let r = EditGeometry.rotateSpecCW(s)
    return r.rotationQuarters == 1 && r.strokes[0].points[0] == CGPoint(x: 1, y: 0)
        && r.strokes[0].radius == 0.02
}())

// 九宫格(CG 坐标 y 向上):锚 0=视觉左上 → 高 y;锚 8=视觉右下 → 低 y
let ts = CGSize(width: 100, height: 20)
let cv = CGSize(width: 1000, height: 500)
check("水印锚点:左上", {
    let o = EditGeometry.watermarkOrigin(anchor: 0, textSize: ts, canvas: cv, margin: 10)
    return o.x == 10 && o.y == 500 - 20 - 10
}())
check("水印锚点:居中", {
    let o = EditGeometry.watermarkOrigin(anchor: 4, textSize: ts, canvas: cv, margin: 10)
    return o.x == 450 && o.y == 240
}())
check("水印锚点:右下", {
    let o = EditGeometry.watermarkOrigin(anchor: 8, textSize: ts, canvas: cv, margin: 10)
    return o.x == 1000 - 100 - 10 && o.y == 10
}())

check("比例约束 1:1 得到像素正方形", {
    let r = EditGeometry.applyRatio(CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
                                    pixelRatio: 1, canvas: CGSize(width: 2000, height: 1000))
    let pw = r.width * 2000, ph = r.height * 1000
    return abs(pw - ph) < 1
}())

// 锚点版比例约束:拖角时固定角必须钉死(中心重锚版会让它漂移)
check("锚点比例:固定角钉死且像素比恒真", {
    let cv = CGSize(width: 2000, height: 1000)
    let r = EditGeometry.applyRatio(anchor: CGPoint(x: 0.2, y: 0.2),
                                    cursor: CGPoint(x: 0.9, y: 0.4),
                                    pixelRatio: 1, canvas: cv)
    let anchorFixed = abs(r.minX - 0.2) < 1e-9 && abs(r.minY - 0.2) < 1e-9
    let pw = r.width * 2000, ph = r.height * 1000
    return anchorFixed && abs(pw - ph) < 0.5
}())
check("锚点比例:反方向拖动锚在右下", {
    let cv = CGSize(width: 1000, height: 1000)
    let r = EditGeometry.applyRatio(anchor: CGPoint(x: 0.8, y: 0.8),
                                    cursor: CGPoint(x: 0.2, y: 0.5),
                                    pixelRatio: 1, canvas: cv)
    return abs(r.maxX - 0.8) < 1e-9 && abs(r.maxY - 0.8) < 1e-9
}())
check("锚点比例:顶到画布边等比缩回不越界", {
    let cv = CGSize(width: 1000, height: 1000)
    let r = EditGeometry.applyRatio(anchor: CGPoint(x: 0.9, y: 0.9),
                                    cursor: CGPoint(x: 2.0, y: 2.0),
                                    pixelRatio: 1, canvas: cv)
    return r.maxX <= 1.0001 && r.maxY <= 1.0001 && abs(r.width - r.height) < 1e-6
}())

// 水印文字度量:CJK 每字约 1em,估算 0.62em 那种偏差必须被同源度量取代
check("水印度量:CJK 宽度接近 1em/字", {
    let s = ImageEdit.watermarkTextSize("水印文字", fontSize: 24)
    return s.width > 24 * 4 * 0.9 && s.width < 24 * 4 * 1.2
}())

// MARK: - ImageEdit(渲染冒烟)

section("ImageEdit(渲染冒烟)")

// 32x16 纯色 PNG 走完整管线:旋转+裁剪+马赛克+水印
let editPNG: URL = {
    let ctx = CGContext(data: nil, width: 32, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 16))
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("kitcheck-edit.png")
    let d = CGImageDestinationCreateWithURL(u as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(d)
    return u
}()
defer { try? FileManager.default.removeItem(at: editPNG) }

check("静态图可编辑", ImageEdit.editable(editPNG))
check("空配方不渲染(返回 nil)", ImageEdit.render(source: editPNG, spec: EditSpec()) == nil)
if true {
    var s = EditSpec()
    s.rotationQuarters = 1
    s.crop = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
    s.strokes = [MosaicStroke(points: [CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.7, y: 0.7)], radius: 0.05)]
    s.watermark = WatermarkSpec(text: "openimg.io")
    if let out = ImageEdit.render(source: editPNG, spec: s),
       let src = CGImageSourceCreateWithURL(out as CFURL, nil),
       let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
       let w = props[kCGImagePropertyPixelWidth] as? Int,
       let h = props[kCGImagePropertyPixelHeight] as? Int {
        // 32x16 转 90° 后 16x32,再裁一半 → 8x16
        check("全管线渲染:旋转+裁剪后尺寸正确", w == 8 && h == 16)
        check("产物保留源文件名", out.deletingPathExtension().lastPathComponent == "kitcheck-edit")
        try? FileManager.default.removeItem(at: out.deletingLastPathComponent())
    } else {
        check("全管线渲染成功", false)
    }
}

// 渲染位置断言:尺寸对不等于方向对——旋转/裁剪的坐标系颠倒在尺寸上不可见。
// 4x2 图:左上角一颗红像素,其余蓝。顺时针 90° 后红点应在右上角;
// 裁掉左半后应不含红点。
func pixelAt(_ url: URL, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8)? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
          let ctx = CGContext(data: nil, width: img.width, height: img.height,
                              bitsPerComponent: 8, bytesPerRow: img.width * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    guard let data = ctx.data else { return nil }
    // CGContext 的坐标 y 向上,但底层缓冲区首行是视觉顶行——内存本来就是
    // 自顶向下的,直接用视觉 y 当行号,不要再翻一次。
    let p = data.advanced(by: (y * img.width + x) * 4).assumingMemoryBound(to: UInt8.self)
    return (p[0], p[1], p[2])
}

let posPNG: URL = {
    let ctx = CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 2))
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 1, width: 1, height: 1))   // CG y 向上:视觉左上角
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("kitcheck-pos.png")
    let d = CGImageDestinationCreateWithURL(u as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(d)
    return u
}()
defer { try? FileManager.default.removeItem(at: posPNG) }

if let p = pixelAt(posPNG, 0, 0), p.r > 200, p.b < 60 {
    check("位置基准:源图左上角是红", true)
} else {
    check("位置基准:源图左上角是红", false)
}
if true {
    var s = EditSpec()
    s.rotationQuarters = 1
    if let out = ImageEdit.render(source: posPNG, spec: s),
       let tr = pixelAt(out, 1, 0), let tl = pixelAt(out, 0, 0) {
        // 视觉顺时针 90°:左上角 → 右上角(2x4 图的右上是 x=1,y=0)
        check("旋转方向:红点到右上角", tr.r > 200 && tr.b < 60 && tl.b > 200)
        try? FileManager.default.removeItem(at: out.deletingLastPathComponent())
    } else {
        check("旋转方向:红点到右上角", false)
    }
}
if true {
    var s = EditSpec()
    s.crop = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)   // 右半
    if let out = ImageEdit.render(source: posPNG, spec: s),
       let p0 = pixelAt(out, 0, 0), let p1 = pixelAt(out, 1, 0) {
        check("裁剪位置:右半不含红点", p0.b > 200 && p1.b > 200 && p0.r < 60)
        try? FileManager.default.removeItem(at: out.deletingLastPathComponent())
    } else {
        check("裁剪位置:右半不含红点", false)
    }
}
if true {
    var s = EditSpec()
    s.crop = CGRect(x: 0, y: 0, width: 0.25, height: 0.5)   // 左上角那格
    if let out = ImageEdit.render(source: posPNG, spec: s),
       let p0 = pixelAt(out, 0, 0) {
        check("裁剪位置:左上角保留红点", p0.r > 200 && p0.b < 60)
        try? FileManager.default.removeItem(at: out.deletingLastPathComponent())
    } else {
        check("裁剪位置:左上角保留红点", false)
    }
}
if true {
    var s = EditSpec()
    s.strokes = [MosaicStroke(points: [CGPoint(x: 0.125, y: 0.25)], radius: 0.12)]
    s.mosaicStyle = .solid
    if let out = ImageEdit.render(source: posPNG, spec: s),
       let p0 = pixelAt(out, 0, 0), let p3 = pixelAt(out, 3, 1) {
        // 纯色涂抹在视觉左上角:红点被抹黑,远端右下角保持蓝
        check("马赛克位置:左上角被涂黑,远角不受影响",
              p0.r < 60 && p0.b < 60 && p3.b > 200)
        try? FileManager.default.removeItem(at: out.deletingLastPathComponent())
    } else {
        check("马赛克位置:左上角被涂黑,远角不受影响", false)
    }
}

// MARK: - 标注(几何)

section("标注几何")

func near(_ a: Double, _ b: Double, _ eps: Double = 1e-6) -> Bool { abs(a - b) <= eps }
func dist(_ a: CGPoint, _ b: CGPoint) -> Double {
    ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
}

// 归一化换算:线宽的含义是"对角线的百分之几",所以同一份标注在任何导出
// 尺寸上粗细必须严格成比例——这正是不按宽度归一化的理由。
if true {
    let c1 = CGSize(width: 1000, height: 750)     // 对角线 1250
    let c3 = CGSize(width: 3000, height: 2250)
    check("对角线换算", near(AnnotationGeometry.diagonal(c1), 1250))
    check("线宽 1x→3x 严格三倍",
          near(AnnotationGeometry.pixels(0.004, canvas: c3),
               AnnotationGeometry.pixels(0.004, canvas: c1) * 3))
    // 转 90° 后画面宽高互换,对角线不变 → 粗细不变。按宽度归一化会在这里跳。
    let rotated = CGSize(width: 750, height: 1000)
    check("线宽旋转不变",
          near(AnnotationGeometry.pixels(0.004, canvas: c1),
               AnnotationGeometry.pixels(0.004, canvas: rotated)))
}

// 归一化(y 向下)→ CG 像素(y 向上)
if true {
    let c = CGSize(width: 100, height: 50)
    check("点映射:左上角 → CG 左上", AnnotationGeometry.point(CGPoint(x: 0, y: 0), canvas: c) == CGPoint(x: 0, y: 50))
    check("点映射:右下角 → CG 原点", AnnotationGeometry.point(CGPoint(x: 1, y: 1), canvas: c) == CGPoint(x: 100, y: 0))
    let r = AnnotationGeometry.rect(CGRect(x: 0, y: 0, width: 0.5, height: 0.5), canvas: c)
    check("矩形映射:视觉左上半 → CG 上半", r == CGRect(x: 0, y: 25, width: 50, height: 25))
    // 拖拽中间态会出现负宽高,映射前必须 standardize,否则整块跑到画外。
    let neg = AnnotationGeometry.rect(CGRect(x: 0.5, y: 0.5, width: -0.5, height: -0.5), canvas: c)
    check("矩形映射:负宽高等价于正向", neg == CGRect(x: 0, y: 25, width: 50, height: 25))
}

// 箭头头部
if true {
    let lw = 4.0
    let head = AnnotationGeometry.arrowHead(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 0), lineWidth: lw)
    if let h = head {
        check("箭头:尖端就是终点", h.tip == CGPoint(x: 200, y: 0))
        check("箭头:头长随线宽(3.6×)", near(h.length, lw * 3.6))
        check("箭头:半宽随线宽(1.5×)", near(h.halfWidth, lw * 1.5))
        check("箭头:两底角对称于轴", near(h.left.y, -h.right.y) && near(h.left.x, h.right.x))
        check("箭头:底边落在头长处", near(h.left.x, 200 - lw * 3.6))
        // 杆停在底边前 15%,圆线帽才不会从三角形两侧探出来。
        check("箭头:杆咬进头部 15%", near(dist(h.tip, h.shaftEnd), h.length * 0.85))
    } else {
        check("箭头:可构造", false)
    }
    // 线宽翻倍 → 整个头等比放大(未封顶时)
    if let a = AnnotationGeometry.arrowHead(from: .zero, to: CGPoint(x: 200, y: 0), lineWidth: 4),
       let b = AnnotationGeometry.arrowHead(from: .zero, to: CGPoint(x: 200, y: 0), lineWidth: 8) {
        check("箭头:头随线宽等比放大", near(b.length, a.length * 2) && near(b.halfWidth, a.halfWidth * 2))
    } else {
        check("箭头:头随线宽等比放大", false)
    }
    // 短箭头:理想头长 14.4 比整根还长,封顶到一半,且宽度同比缩——只削长度
    // 会得到一把钝斧头。
    if let s = AnnotationGeometry.arrowHead(from: .zero, to: CGPoint(x: 10, y: 0), lineWidth: 4) {
        check("短箭头:头长封顶在杆长一半", near(s.length, 5))
        check("短箭头:宽度同比缩,形状不变", near(s.halfWidth / s.length, 1.5 / 3.6))
    } else {
        check("短箭头:可构造", false)
    }
    // 斜箭头:3-4-5,底边中点必须落在轴上、两底角到轴等距。
    if let d = AnnotationGeometry.arrowHead(from: .zero, to: CGPoint(x: 30, y: 40), lineWidth: 2) {
        let mid = CGPoint(x: (d.left.x + d.right.x) / 2, y: (d.left.y + d.right.y) / 2)
        check("斜箭头:底边中点在轴上", near(dist(mid, d.tip), d.length, 1e-9) && near(mid.x / mid.y, 30.0 / 40.0))
        check("斜箭头:底边宽 = 2×半宽", near(dist(d.left, d.right), d.halfWidth * 2))
    } else {
        check("斜箭头:可构造", false)
    }
    check("箭头:首尾同点不成立",
          AnnotationGeometry.arrowHead(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5, y: 5), lineWidth: 4) == nil)
}

// 文字落位:换行宽度与越界回收
if true {
    let c = CGSize(width: 1000, height: 500)
    check("文字:排版宽取到右边距", near(AnnotationGeometry.textWrapWidth(originX: 0.1, canvas: c, margin: 10), 890))
    // 贴右边缘落笔时残宽只有 40px,一行一个字没法看——给到画宽的 25%,
    // 溢出部分交给 textBlockRect 往左推。
    check("文字:贴边落笔仍有可用宽", near(AnnotationGeometry.textWrapWidth(originX: 0.95, canvas: c, margin: 10), 250))

    let normal = AnnotationGeometry.textBlockRect(origin: CGPoint(x: 0.1, y: 0.1),
                                                 blockSize: CGSize(width: 100, height: 20),
                                                 canvas: c, margin: 10)
    check("文字:画面内不挪动", normal == CGRect(x: 100, y: 430, width: 100, height: 20))

    let rightEdge = AnnotationGeometry.textBlockRect(origin: CGPoint(x: 0.95, y: 0.1),
                                                    blockSize: CGSize(width: 100, height: 20),
                                                    canvas: c, margin: 10)
    check("文字:右溢出往左推回画内", near(rightEdge.maxX, 990))

    let bottom = AnnotationGeometry.textBlockRect(origin: CGPoint(x: 0.1, y: 0.99),
                                                 blockSize: CGSize(width: 100, height: 20),
                                                 canvas: c, margin: 10)
    check("文字:下溢出抬回画内", near(bottom.minY, 10))

    // 比画面还高的一段:必须保住**开头**可见(块顶贴上边距),溢出的是结尾。
    let tall = AnnotationGeometry.textBlockRect(origin: CGPoint(x: 0.1, y: 0.5),
                                               blockSize: CGSize(width: 100, height: 600),
                                               canvas: c, margin: 10)
    check("文字:超高时保住开头", near(tall.maxY, 490))
}

// 旋转:与 EditSpec 同一套规则,线宽/字号不受影响
if true {
    let items = [
        Annotation.arrow(from: CGPoint(x: 0.1, y: 0.2), to: CGPoint(x: 0.4, y: 0.6), lineWidth: 0.007),
        Annotation.rect(CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)),
        Annotation.text("说明", at: CGPoint(x: 0.1, y: 0.2), fontScale: 0.05),
    ]
    var turned = items
    for _ in 0..<4 { turned = AnnotationGeometry.rotateQuarterCW(turned) }
    var roundTrip = true
    for (a, b) in zip(items, turned) {
        roundTrip = roundTrip && near(a.normalizedBounds.minX, b.normalizedBounds.minX)
            && near(a.normalizedBounds.minY, b.normalizedBounds.minY)
            && near(a.lineWidth, b.lineWidth)
    }
    check("旋转:转四次回到原位", roundTrip)
    let once = AnnotationGeometry.rotateQuarterCW(items)
    if case .arrow(let from, _) = once[0].kind {
        check("旋转:点变换与 EditGeometry 一致",
              from == EditGeometry.rotateQuarterCW(CGPoint(x: 0.1, y: 0.2)))
    } else {
        check("旋转:点变换与 EditGeometry 一致", false)
    }
    if case .text(let s, _, let f) = once[2].kind {
        check("旋转:字号与内容不变", s == "说明" && near(f, 0.05))
    } else {
        check("旋转:字号与内容不变", false)
    }
}

// MARK: - 标注(渲染)

section("标注渲染")

func solidImage(_ w: Int, _ h: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

/// 取整幅 RGBA。逐像素比对用得上——撤销是否等价于"没画过"只能这样验。
func rgbaBytes(_ img: CGImage) -> [UInt8] {
    let w = img.width, h = img.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return [] }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let d = ctx.data else { return [] }
    return Array(UnsafeBufferPointer(start: d.assumingMemoryBound(to: UInt8.self), count: w * h * 4))
}

/// 视觉坐标(y 向下)取色,口径同 pixelAt。
func sample(_ buf: [UInt8], _ w: Int, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
    let i = (y * w + x) * 4
    return (buf[i], buf[i + 1], buf[i + 2])
}
func isWhite(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.r > 245 && p.g > 245 && p.b > 245 }
func isInk(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.r > 150 && p.g < 90 && p.b < 90 }

let blank = solidImage(1000, 1000)   // 对角线 1414

check("空数组不改图", renderAnnotations([], on: blank) === blank)

if true {
    // 水平画笔穿过画面中线
    let line = Annotation.freehand(points: [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.9, y: 0.5)],
                                   lineWidth: 0.01)
    let out = rgbaBytes(renderAnnotations([line], on: blank))
    check("画笔:中线着色、远角干净",
          isInk(sample(out, 1000, 500, 500)) && isWhite(sample(out, 1000, 10, 10)))
    check("画笔:笔迹外沿之外不着色", isWhite(sample(out, 1000, 500, 470)))
}

if true {
    // 矩形/椭圆按截图习惯是描边:边上有色,中心必须干净,否则会盖住被圈的内容
    let box = Annotation.rect(CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6), lineWidth: 0.006)
    let out = rgbaBytes(renderAnnotations([box], on: blank))
    check("矩形:是描边不是填充",
          isInk(sample(out, 1000, 500, 200)) && isWhite(sample(out, 1000, 500, 500)))
    let oval = Annotation.ellipse(CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6), lineWidth: 0.006)
    let out2 = rgbaBytes(renderAnnotations([oval], on: blank))
    check("椭圆:是描边不是填充,且不是矩形",
          isInk(sample(out2, 1000, 500, 200)) && isWhite(sample(out2, 1000, 500, 500))
              && isWhite(sample(out2, 1000, 200, 200)))
}

if true {
    // 头部必须明显比杆宽:偏离轴线 8px 处,头部区域有色而杆身区域干净。
    // lw = 0.006×1414 ≈ 8.5px(半宽 4.2),头长 ≈ 30.6、底边半宽 ≈ 12.7。
    let arrow = Annotation.arrow(from: CGPoint(x: 0.2, y: 0.5), to: CGPoint(x: 0.8, y: 0.5),
                                 lineWidth: 0.006)
    let out = rgbaBytes(renderAnnotations([arrow], on: blank))
    check("箭头:头部比杆宽",
          isInk(sample(out, 1000, 775, 508)) && isWhite(sample(out, 1000, 400, 508)))
    check("箭头:杆身在轴上连续",
          isInk(sample(out, 1000, 400, 500)) && isInk(sample(out, 1000, 700, 500)))
    check("箭头:尾端之外不着色", isWhite(sample(out, 1000, 150, 500)))
}

if true {
    // 换行:同一段文字给一个贴右边缘的锚点,必须排到多行且整块留在画内——
    // 而不是一行冲出右边界后被裁掉。
    let long = String(repeating: "标注文字 ", count: 12)
    let a = renderAnnotations([Annotation.text(long, at: CGPoint(x: 0.9, y: 0.1), fontScale: 0.02)],
                              on: blank)
    let buf = rgbaBytes(a)
    var inked = 0
    for y in 0..<1000 where !isWhite(sample(buf, 1000, 995, y)) { inked += 1 }
    check("文字:不越过右边距", inked == 0)
    var rows = Set<Int>()
    for y in stride(from: 0, to: 1000, by: 2) {
        for x in stride(from: 0, to: 1000, by: 2) where !isWhite(sample(buf, 1000, x, y)) {
            rows.insert(y / 20)
            break
        }
    }
    check("文字:长文本换成多行", rows.count >= 3)
}

if true {
    // 撤销的全部实现就是 removeLast:去掉末项后重渲,必须和"从没画过它"
    // 逐像素相同。模型里没有别的状态需要跟着回滚,这条断言就是它的证明。
    var items: [Annotation] = [
        .rect(CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)),
        .freehand(points: [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.9, y: 0.9)], color: .blue),
    ]
    let both = rgbaBytes(renderAnnotations(items, on: blank))
    let onlyFirst = rgbaBytes(renderAnnotations([items[0]], on: blank))
    items.removeLast()
    let afterUndo = rgbaBytes(renderAnnotations(items, on: blank))
    check("撤销:removeLast 后与未画过逐像素相同", afterUndo == onlyFirst && afterUndo != both)
}

if true {
    // 同一份标注在预览尺寸与导出尺寸上"看起来一样粗":线宽占对角线的比例
    // 相同,量出来的笔迹宽度之比应等于尺寸之比。
    func inkWidth(_ side: Int) -> Int {
        let img = solidImage(side, side)
        let line = Annotation.freehand(points: [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.9, y: 0.5)],
                                       lineWidth: 0.02)
        let buf = rgbaBytes(renderAnnotations([line], on: img))
        return (0..<side).reduce(0) { $0 + (isWhite(sample(buf, side, side / 2, $1)) ? 0 : 1) }
    }
    let small = inkWidth(400), large = inkWidth(1200)
    check("尺寸无关:1x 与 3x 笔迹粗细成比例(\(small)→\(large))",
          abs(Double(large) - Double(small) * 3) <= 3)
}

// MARK: - 翻转几何

section("翻转几何")

check("点水平翻转:左上→右上", EditGeometry.flipH(CGPoint(x: 0, y: 0)) == CGPoint(x: 1, y: 0))
check("点垂直翻转:左上→左下", EditGeometry.flipV(CGPoint(x: 0, y: 0)) == CGPoint(x: 0, y: 1))
// 容差而非严格相等:1-(1-x) 在二进制浮点下不恒等于 x(0.3 就差一个 ulp)。
// 归一化坐标全程都是这个量级的漂移,断言要求精确相等只会测出浮点本身。
check("翻转两次回原位", {
    let p = CGPoint(x: 0.3, y: 0.8)
    let h = EditGeometry.flipH(EditGeometry.flipH(p))
    let v = EditGeometry.flipV(EditGeometry.flipV(p))
    return abs(h.x - p.x) < 1e-12 && abs(h.y - p.y) < 1e-12
        && abs(v.x - p.x) < 1e-12 && abs(v.y - p.y) < 1e-12
}())
check("矩形水平翻转:保尺寸、换左右", {
    let r = EditGeometry.flipH(CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
    return abs(r.minX - 0.6) < 1e-9 && abs(r.minY - 0.2) < 1e-9
        && abs(r.width - 0.3) < 1e-9 && abs(r.height - 0.4) < 1e-9
}())
check("矩形垂直翻转:保尺寸、换上下", {
    let r = EditGeometry.flipV(CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
    return abs(r.minX - 0.1) < 1e-9 && abs(r.minY - 0.4) < 1e-9
        && abs(r.width - 0.3) < 1e-9 && abs(r.height - 0.4) < 1e-9
}())

check("配方水平翻转:标志切换且笔迹跟翻", {
    var s = EditSpec()
    s.strokes = [MosaicStroke(points: [CGPoint(x: 0.25, y: 0.6)], radius: 0.02)]
    let f = EditGeometry.flipSpecH(s)
    return f.flipHorizontal && !f.flipVertical
        && abs(f.strokes[0].points[0].x - 0.75) < 1e-9
        && abs(f.strokes[0].points[0].y - 0.6) < 1e-9
}())
check("配方翻转两次回原样", {
    var s = EditSpec()
    s.crop = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
    let b = EditGeometry.flipSpecV(EditGeometry.flipSpecV(s))
    return b.flipVertical == s.flipVertical
        && abs(b.crop!.minX - 0.1) < 1e-12 && abs(b.crop!.minY - 0.2) < 1e-12
        && abs(b.crop!.width - 0.3) < 1e-12 && abs(b.crop!.height - 0.4) < 1e-12
}())

// 变换定义是 flip ∘ rotate^q,转 90° 要把 R 挪到最外层,恒等式 R∘F_h = F_v∘R
// 会让"恰好翻了一个轴"的情形换轴。这一条错了,界面上转完再翻会朝反方向翻。
check("转 90° 时单轴翻转换轴 H→V", {
    var s = EditSpec()
    s.flipHorizontal = true
    let r = EditGeometry.rotateSpecCW(s)
    return r.rotationQuarters == 1 && !r.flipHorizontal && r.flipVertical
}())
check("转 90° 时双轴翻转不变(等于 180°,与旋转交换)", {
    var s = EditSpec()
    s.flipHorizontal = true
    s.flipVertical = true
    let r = EditGeometry.rotateSpecCW(s)
    return r.flipHorizontal && r.flipVertical && r.rotationQuarters == 1
}())
check("转四次 90° 后整份配方回原样", {
    var s = EditSpec()
    s.flipHorizontal = true
    s.crop = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
    var r = s
    for _ in 0..<4 { r = EditGeometry.rotateSpecCW(r) }
    return r.rotationQuarters == 0 && r.flipHorizontal == s.flipHorizontal
        && r.flipVertical == s.flipVertical
        && abs(r.crop!.minX - 0.1) < 1e-9 && abs(r.crop!.minY - 0.2) < 1e-9
}())

// MARK: - 色彩调整与滤镜预设

section("色彩调整与滤镜预设")

check("默认即中性", ColorAdjustments().isNeutral && ColorAdjustments.neutral.isNeutral)
// 中性值不统一是 0:乘数型参数(对比/饱和)中性是 1,把它们当成 0 起点会让
// 默认配方直接把图压成全黑。
check("乘数型参数的中性值是 1",
      ColorAdjustments.neutral.contrast == 1 && ColorAdjustments.neutral.saturation == 1)
check("叠加型参数的中性值是 0",
      ColorAdjustments.neutral.brightness == 0 && ColorAdjustments.neutral.hue == 0
        && ColorAdjustments.neutral.sepia == 0 && ColorAdjustments.neutral.blur == 0)
check("任一分量偏离即非中性", {
    var a = ColorAdjustments()
    a.blur = 0.2
    return !a.isNeutral
}())
// 滑块拖回中间落在 0.9999 是常态,严格相等会让这张图白跑一遍 Core Image。
check("容差内仍算中性", {
    var a = ColorAdjustments()
    a.saturation = 1 - ColorAdjustments.epsilon / 2
    a.brightness = ColorAdjustments.epsilon / 2
    return a.isNeutral
}())
check("吸附把容差内的分量归到精确中性", {
    var a = ColorAdjustments()
    a.contrast = 1 + ColorAdjustments.epsilon / 2
    return a.snapped() == ColorAdjustments.neutral
}())
check("夹取挡住会毁图的疯值", {
    var a = ColorAdjustments(brightness: 99, contrast: -5, saturation: 88, hue: 99, sepia: 9, blur: 9)
    a = a.clamped()
    return ColorAdjustments.brightnessRange.contains(a.brightness)
        && ColorAdjustments.contrastRange.contains(a.contrast)
        && ColorAdjustments.saturationRange.contains(a.saturation)
        && ColorAdjustments.hueRange.contains(a.hue)
        && ColorAdjustments.sepiaRange.contains(a.sepia)
        && ColorAdjustments.blurRange.contains(a.blur)
}())
check("对比度下限不允许压成灰卡", ColorAdjustments.contrastRange.lowerBound > 0)

// 预设的本质是一组调整取值,不是另一条渲染路径。
check("原图预设就是中性", FilterPreset.none.adjustments.isNeutral)
check("六个预设齐全", FilterPreset.allCases.count == 6)
check("黑白预设把饱和归零", FilterPreset.mono.adjustments.saturation == 0)
check("除原图外每个预设都真的改了东西",
      FilterPreset.allCases.filter { $0 != .none }.allSatisfy { !$0.adjustments.isNeutral })
check("每个预设都能被认回来",
      FilterPreset.allCases.allSatisfy { FilterPreset.matching($0.adjustments) == $0 })
// 选了预设再拖滑块 = 自定义,界面上不该再有预设高亮。
check("微调后不再匹配任何预设", {
    var a = FilterPreset.vivid.adjustments
    a.brightness += 0.2
    return FilterPreset.matching(a) == nil
}())
check("吸附后的中性认作原图预设", {
    var a = ColorAdjustments()
    a.hue = ColorAdjustments.epsilon / 3
    return FilterPreset.matching(a.snapped()) == FilterPreset.none
}())

// MARK: - 导出选项

section("导出选项")

check("四档倍率", ExportScale.allCases.count == 4)
check("1.5x 的标签不被整数化", ExportScale.x1_5.label == "1.5x" && ExportScale.x2.label == "2x")

// 倍率只与限宽相乘:没设限宽时它无效,否则 3x 会把 4000px 的源图插值放到
// 12000px——没有新信息,只是让别人多下几 MB。
check("没设限宽时倍率无效", {
    var s = EditSpec()
    s.exportScale = .x3
    return s.effectiveMaxWidth == 0
}())
check("倍率乘在限宽上", {
    var s = EditSpec()
    s.exportMaxWidth = 800
    s.exportScale = .x2
    return s.effectiveMaxWidth == 1600
}())
check("1.5x 取整", {
    var s = EditSpec()
    s.exportMaxWidth = 801
    s.exportScale = .x1_5
    return s.effectiveMaxWidth == 1202   // 1201.5 四舍五入
}())

// resolve 的优先级:alpha > 可写性 > 用户选择 > 源格式
let allWritable: Set<ExportFormat> = [.jpeg, .png, .webp, .heic]
let noWebP: Set<ExportFormat> = [.jpeg, .png, .heic]

check("auto 跟着源走:JPEG 源出 JPEG",
      ExportFormat.resolve(requested: .auto, sourceType: .jpeg, requiresAlpha: false,
                           writable: allWritable) == .jpeg)
check("auto 跟着源走:HEIC 源出 HEIC",
      ExportFormat.resolve(requested: .auto, sourceType: .heic, requiresAlpha: false,
                           writable: allWritable) == .heic)
check("auto 遇到认不出的源退到 PNG",
      ExportFormat.resolve(requested: .auto, sourceType: nil, requiresAlpha: false,
                           writable: allWritable) == .png)
check("显式选择盖过源格式",
      ExportFormat.resolve(requested: .png, sourceType: .jpeg, requiresAlpha: false,
                           writable: allWritable) == .png)
// 写不出的格式必须换一个,不能让 render 返回 nil——那对用户表现为"点了导出
// 什么都没发生"。
check("写不了 WebP 时有损换 JPEG",
      ExportFormat.resolve(requested: .webp, sourceType: .png, requiresAlpha: false,
                           writable: noWebP) == .jpeg)
check("auto 遇到 WebP 源且写不了 WebP 也要换",
      ExportFormat.resolve(requested: .auto, sourceType: .webP, requiresAlpha: false,
                           writable: noWebP) == .jpeg)
// alpha 最强:抠图产物落到 JPEG 就是一张黑底废图。
check("抠图把 JPEG 顶成 PNG",
      ExportFormat.resolve(requested: .jpeg, sourceType: .jpeg, requiresAlpha: true,
                           writable: allWritable) == .png)
check("抠图 + auto + JPEG 源同样出 PNG",
      ExportFormat.resolve(requested: .auto, sourceType: .jpeg, requiresAlpha: true,
                           writable: allWritable) == .png)
check("抠图 + 写不了 WebP:先回退再补 alpha,最终 PNG 而不是 JPEG",
      ExportFormat.resolve(requested: .webp, sourceType: .png, requiresAlpha: true,
                           writable: noWebP) == .png)
check("抠图时能存 alpha 的格式保留用户选择",
      ExportFormat.resolve(requested: .heic, sourceType: .jpeg, requiresAlpha: true,
                           writable: allWritable) == .heic)
check("resolve 永不返回 auto", {
    let sources: [UTType?] = [nil, .jpeg, .png, .heic, .webP, .gif]
    return ExportFormat.allCases.allSatisfy { req in
        sources.allSatisfy { s in
            [true, false].allSatisfy { alpha in
                ExportFormat.resolve(requested: req, sourceType: s, requiresAlpha: alpha,
                                     writable: noWebP) != .auto
            }
        }
    }
}())
check("JPEG 是唯一存不下 alpha 的格式",
      ExportFormat.allCases.filter { !$0.supportsAlpha } == [.jpeg])
// 本机 ImageIO 至今写不出 WebP。这条断言不是在测系统,是在守住"必须运行期
// 探测"这个决定——哪天系统补上了,它会红,那正是该去掉回退分支的信号。
check("本机可写集合至少含 JPEG/PNG",
      ExportFormat.writable.isSuperset(of: [.jpeg, .png]))

// MARK: - hasEdits(空转闸门)

section("hasEdits(空转闸门)")

check("默认配方无编辑", !EditSpec().hasEdits)
// 中性参数不得进入管线,否则每张图都白跑一遍 Core Image。
check("中性调整不算编辑", {
    var s = EditSpec()
    s.adjustments = FilterPreset.none.adjustments
    return !s.hasEdits
}())
check("容差内的调整也不算编辑", {
    var s = EditSpec()
    s.adjustments.saturation = 1 + ColorAdjustments.epsilon / 2
    return !s.hasEdits
}())
check("选了滤镜预设算编辑", {
    var s = EditSpec()
    s.adjustments = FilterPreset.vintage.adjustments
    return s.hasEdits
}())
check("翻转算编辑", {
    var s = EditSpec()
    s.flipHorizontal = true
    return s.hasEdits
}())
// 倍率单独不算:没有限宽时它本来就无效。
check("只调倍率不算编辑", {
    var s = EditSpec()
    s.exportScale = .x3
    return !s.hasEdits
}())
check("显式选格式算编辑", {
    var s = EditSpec()
    s.exportFormat = .png
    return s.hasEdits
}())
check("auto 格式不算编辑", EditSpec().exportFormat == .auto && !EditSpec().hasEdits)
check("抠图 + 选了 JPEG 时预告会被改成 PNG", {
    var s = EditSpec()
    s.cutout = true
    s.exportFormat = .jpeg
    return s.requiresAlpha && s.forcesPNG
}())
check("抠图 + 选了 PNG 不算被迫改格式", {
    var s = EditSpec()
    s.cutout = true
    s.exportFormat = .png
    return !s.forcesPNG
}())

// MARK: - 翻转渲染方向

section("翻转渲染方向")

// 尺寸对不等于方向对:翻转在正方形图上、在两个轴上都错的时候,尺寸完全一样。
// 沿用上面的 posPNG:4x2,视觉左上角一颗红像素,其余蓝。
if true {
    var s = EditSpec()
    s.flipHorizontal = true
    if let out = ImageEdit.render(source: posPNG, spec: s),
       let tr = pixelAt(out, 3, 0), let tl = pixelAt(out, 0, 0) {
        check("水平翻转:红点到右上角", tr.r > 200 && tr.b < 60 && tl.b > 200)
        try? FileManager.default.removeItem(at: out.deletingLastPathComponent())
    } else {
        check("水平翻转:红点到右上角", false)
    }
}
if true {
    var s = EditSpec()
    s.flipVertical = true
    if let out = ImageEdit.render(source: posPNG, spec: s),
       let bl = pixelAt(out, 0, 1), let tl = pixelAt(out, 0, 0) {
        check("垂直翻转:红点到左下角", bl.r > 200 && bl.b < 60 && tl.b > 200)
        try? FileManager.default.removeItem(at: out.deletingLastPathComponent())
    } else {
        check("垂直翻转:红点到左下角", false)
    }
}
// 组合顺序的判据。变换定义是 flip ∘ rotate(先转再翻):4x2 转 90° 成 2x4、
// 红点到右上 (1,0),再水平翻 → (0,0)。若实现写成了 rotate ∘ flip,红点会落在
// (1,3)。两种顺序尺寸都是 2x4,只有像素位置能分辨。
if true {
    var s = EditSpec()
    s.rotationQuarters = 1
    s.flipHorizontal = true
    if let out = ImageEdit.render(source: posPNG, spec: s),
       let a = pixelAt(out, 0, 0), let b = pixelAt(out, 1, 3) {
        check("旋转+翻转的合成顺序是 flip∘rotate", a.r > 200 && a.b < 60 && b.b > 200)
        try? FileManager.default.removeItem(at: out.deletingLastPathComponent())
    } else {
        check("旋转+翻转的合成顺序是 flip∘rotate", false)
    }
}
// rotateSpecCW 的换轴规则要与渲染一致:{q0,flipH} 的画面再转 90°,红点应从
// 右上转到右下;而 rotateSpecCW 把配方变成 {q1,flipV},渲染必须给出同一结果。
if true {
    var s = EditSpec()
    s.flipHorizontal = true
    let r = EditGeometry.rotateSpecCW(s)
    if let out = ImageEdit.render(source: posPNG, spec: r),
       let br = pixelAt(out, 1, 3), let tl = pixelAt(out, 0, 0) {
        check("换轴规则与渲染一致:红点转到右下角", br.r > 200 && br.b < 60 && tl.b > 200)
        try? FileManager.default.removeItem(at: out.deletingLastPathComponent())
    } else {
        check("换轴规则与渲染一致:红点转到右下角", false)
    }
}

// MARK: - 色彩调整渲染冒烟

section("色彩调整渲染冒烟")

// 中性参数必须原样返回同一个对象,而不是白跑一遍 Core Image 再编码回来。
if let same = ImageAdjust.apply(.neutral, to: CGImageSourceCreateImageAtIndex(
        CGImageSourceCreateWithURL(posPNG as CFURL, nil)!, 0, nil)!) {
    check("中性调整不进管线(尺寸不变)", same.width == 4 && same.height == 2)
} else {
    check("中性调整不进管线(尺寸不变)", false)
}
if true {
    var s = EditSpec()
    s.adjustments = FilterPreset.mono.adjustments
    if let out = ImageEdit.render(source: posPNG, spec: s), let p = pixelAt(out, 0, 0) {
        // 黑白预设后红点应当没有色彩偏向:三通道互相接近。
        let maxc = max(p.r, max(p.g, p.b)), minc = min(p.r, min(p.g, p.b))
        check("黑白预设:红点去色(通道差 \(Int(maxc) - Int(minc)))", Int(maxc) - Int(minc) < 24)
        try? FileManager.default.removeItem(at: out.deletingLastPathComponent())
    } else {
        check("黑白预设:红点去色", false)
    }
}
// 模糊半径按对角线折算,4x2 的 posPNG 上满强度也只有 0.09px——测不出东西。
// 这里另起一张左红右蓝的图:接缝处该混色,四角该保持纯色(边缘做了延拓)。
func makeSeamImage(width: Int, height: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
    return ctx.makeImage()!
}

func pixelIn(_ img: CGImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8)? {
    guard let ctx = CGContext(data: nil, width: img.width, height: img.height,
                              bitsPerComponent: 8, bytesPerRow: img.width * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    guard let data = ctx.data else { return nil }
    let p = data.advanced(by: (y * img.width + x) * 4).assumingMemoryBound(to: UInt8.self)
    return (p[0], p[1], p[2])
}

if true {
    var a = ColorAdjustments()
    a.blur = 1
    let seam = makeSeamImage(width: 256, height: 128)
    if let out = ImageAdjust.apply(a, to: seam),
       let mid = pixelIn(out, 128, 64), let corner = pixelIn(out, 0, 0) {
        check("模糊:接缝两侧混色(\(mid.r),\(mid.b))", mid.r > 40 && mid.b > 40)
        // 没有 clampedToExtent 的话高斯核会从画外取到透明,四角朝黑衰减。
        check("模糊:边缘做了延拓,左上角仍是纯红(\(corner.r),\(corner.b))",
              corner.r > 220 && corner.b < 40)
    } else {
        check("模糊:接缝两侧混色", false)
    }
}

// 半径归一化到对角线,是"预览与成品逐像素同构"这句话的全部依据。这一条塌了,
// 编辑器里看到的模糊就和上传出去的不是一回事。
//
// 用左半幅的平均蓝量而不是单点取样:单点极易落在离接缝几个半径之外的饱和区,
// 两个尺寸都是纯红,断言就成了摆设。平均蓝量正比于"蓝色渗过接缝的总量",
// 半径按对角线折算时它与图幅无关。
func meanBlueLeftHalf(_ img: CGImage) -> Double {
    let w = img.width, h = img.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return -1 }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let data = ctx.data else { return -1 }
    let p = data.assumingMemoryBound(to: UInt8.self)
    var sum = 0.0
    for y in 0..<h {
        for x in 0..<(w / 2) { sum += Double(p[(y * w + x) * 4 + 2]) }
    }
    return sum / Double(h * (w / 2))
}

if true {
    var a = ColorAdjustments()
    a.blur = 0.6
    if let s = ImageAdjust.apply(a, to: makeSeamImage(width: 128, height: 64)),
       let b = ImageAdjust.apply(a, to: makeSeamImage(width: 512, height: 256)) {
        let ms = meanBlueLeftHalf(s), mb = meanBlueLeftHalf(b)
        check("模糊确实渗过了接缝(左半均蓝 \(String(format: "%.2f", ms)))", ms > 1)
        check("模糊半径随图幅等比(128px \(String(format: "%.2f", ms)) vs 512px \(String(format: "%.2f", mb)))",
              abs(ms - mb) < 1.5)
    } else {
        check("模糊半径随图幅等比", false)
    }
}

// MARK: - TokenStore(令牌持久化)

section("TokenStore(令牌持久化)")

// CLI 环境没有 keychain entitlement,save 自动落到文件回退——正是 ad-hoc
// 构建的路径。真签名构建走数据保护钥匙串,此处测不到但接口相同。
let tokenStore = TokenStore(service: "io.openimg.token.kitcheck")
let fakeServer = "https://kitcheck.example.openimg.io"
do {
    try tokenStore.save("oimg_kitcheck_token_123", server: fakeServer)
    check("保存后能读回", tokenStore.load(server: fakeServer) == "oimg_kitcheck_token_123")
    try tokenStore.save("oimg_replaced", server: fakeServer)
    check("重复保存是覆盖", tokenStore.load(server: fakeServer) == "oimg_replaced")
    check("删除返回 true", tokenStore.delete(server: fakeServer))
    check("删除后读不到", tokenStore.load(server: fakeServer) == nil)
} catch {
    check("TokenStore 保存不抛错(\(error))", false)
}

// MARK: - WebAuthn(base64url 与注册模型)

section("WebAuthn(base64url 与注册模型)")

check("base64url 往返", Data(base64URL: Data([0xfb, 0xff, 0x00, 0x7e]).base64URLEncoded) == Data([0xfb, 0xff, 0x00, 0x7e]))
check("base64url 无填充", !Data([1, 2, 3, 4, 5]).base64URLEncoded.contains("="))
check("base64url 无 +/", {
    let s = Data((0...255).map { UInt8($0) }).base64URLEncoded
    return !s.contains("+") && !s.contains("/")
}())
check("接受带填充的输入", Data(base64URL: "AQID") == Data([1, 2, 3]) && Data(base64URL: "AQI=") == Data([1, 2]))
check("非法输入返回 nil", Data(base64URL: "!!!") == nil)

if let enc = try? JSONEncoder().encode(
    WebAuthnRegistration(credentialID: Data([1, 2]), attestationObject: Data([3]), clientDataJSON: Data([4]))),
   let obj = try? JSONSerialization.jsonObject(with: enc) as? [String: Any] {
    check("注册模型 type 固定 public-key", obj["type"] as? String == "public-key")
    check("注册模型 id 与 rawId 一致", obj["id"] as? String == obj["rawId"] as? String)
    check("注册模型嵌套 response", (obj["response"] as? [String: Any])?["attestationObject"] != nil)
} else {
    check("注册模型可编码", false)
}

// go-webauthn 下发形状的解码冒烟
let beginJSON = """
{"flow":"f1","options":{"publicKey":{"challenge":"AQID","rp":{"id":"openimg.io","name":"Openimg"},"user":{"id":"BAUG","name":"u@example.com","displayName":"U"}}}}
"""
if let d = try? JSONDecoder().decode(PasskeyEnrollStart.self, from: Data(beginJSON.utf8)) {
    check("begin 响应可解码", d.flow == "f1" && d.options.publicKey.rp.id == "openimg.io")
    check("挑战可还原为字节", Data(base64URL: d.options.publicKey.challenge) == Data([1, 2, 3]))
} else {
    check("begin 响应可解码", false)
}

// MARK: - 元数据读取与剥离

section("ImageMeta(EXIF 读取)")

/// 合成一张带完整"隐私负担"的 JPEG:GPS、机身、镜头、软件、序列号,外加
/// 一组正常的曝光参数和一个非默认方向。
///
/// 自造样张而不是找一张真照片来测:剥离断言必须先确知"剥之前确实有",拿
/// 外部文件当输入,哪天文件被清掉或换了一张没 GPS 的,断言会静默变成
/// "剥完没有 → 通过",测了个寂寞。参见上面 makeSamplePNG 的同类教训。
func makeGeotaggedJPEG(orientation: Int = 6) -> URL {
    let ctx = CGContext(data: nil, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.3, green: 0.7, blue: 0.4, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 6))

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("kitcheck-exif-\(UUID().uuidString).jpg")
    let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    // 天安门附近,北纬东经,好认;EXIF 存无符号度数 + 半球标记。
    let props: [CFString: Any] = [
        kCGImagePropertyOrientation: orientation,
        kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 39.9087,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 116.3975,
            kCGImagePropertyGPSLongitudeRef: "E",
            kCGImagePropertyGPSAltitude: 44.0,
            kCGImagePropertyGPSAltitudeRef: 0,
        ] as [CFString: Any],
        kCGImagePropertyTIFFDictionary: [
            kCGImagePropertyTIFFMake: "Apple",
            kCGImagePropertyTIFFModel: "iPhone 17 Pro",
            kCGImagePropertyTIFFSoftware: "18.2",
            kCGImagePropertyTIFFArtist: "西风",
        ] as [CFString: Any],
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifFNumber: 1.78,
            kCGImagePropertyExifExposureTime: 0.004,
            kCGImagePropertyExifISOSpeedRatings: [64],
            kCGImagePropertyExifFocalLength: 6.765,
            kCGImagePropertyExifFocalLenIn35mmFilm: 24,
            kCGImagePropertyExifDateTimeOriginal: "2026:08:17 21:30:05",
            kCGImagePropertyExifOffsetTimeOriginal: "+08:00",
            kCGImagePropertyExifLensModel: "iPhone 17 Pro back camera 6.765mm f/1.78",
            kCGImagePropertyExifBodySerialNumber: "F2LX9Q1ABCD",
        ] as [CFString: Any],
        kCGImagePropertyIPTCDictionary: [
            kCGImagePropertyIPTCCity: "北京",
            kCGImagePropertyIPTCSubLocation: "东城区",
        ] as [CFString: Any],
    ]
    CGImageDestinationAddImage(dst, ctx.makeImage()!, props as CFDictionary)
    CGImageDestinationFinalize(dst)
    return url
}

let dirtyJPEG = makeGeotaggedJPEG()
defer { try? FileManager.default.removeItem(at: dirtyJPEG) }

if let meta = ImageMetadata.read(dirtyJPEG) {
    check("像素尺寸", meta.pixelWidth == 8 && meta.pixelHeight == 6)
    check("格式识别为 JPEG", meta.utType?.conforms(to: .jpeg) == true)
    check("字节大小非零", meta.byteCount > 0)
    check("方向标签读回", meta.orientation == 6)
    check("单帧图 frameCount == 1", meta.frameCount == 1 && !meta.isAnimated)

    let e = meta.exif
    check("机身厂商/型号", e.cameraMake == "Apple" && e.cameraModel == "iPhone 17 Pro")
    check("镜头型号", e.lensModel?.contains("6.765mm") == true)
    check("软件", e.software == "18.2")
    check("光圈", e.aperture.map { abs($0 - 1.78) < 0.01 } == true)
    check("快门", e.shutterSeconds.map { abs($0 - 0.004) < 1e-6 } == true)
    check("ISO", e.iso == 64)
    check("焦距与等效焦距", e.focalLength.map { abs($0 - 6.765) < 0.01 } == true && e.focalLength35mm == 24)
    // 2026-08-17 21:30:05 +08:00 = 2026-08-17 13:30:05 UTC。写死 UTC 时刻是
    // 为了让断言在任何时区的机器上都成立——照本机时区算就等于没测偏移解析。
    check("拍摄时间(按 EXIF 时区偏移解析)", e.captureDate.map {
        abs($0.timeIntervalSince1970 - 1786973405) < 1
    } == true)
    check("GPS 坐标", e.latitude.map { abs($0 - 39.9087) < 1e-4 } == true
        && e.longitude.map { abs($0 - 116.3975) < 1e-4 } == true)
    check("海拔", e.altitude.map { abs($0 - 44) < 0.5 } == true)
    check("判定为含身份信息", e.hasLocation && e.hasIdentifyingInfo && !e.isEmpty)
} else {
    check("样张元数据可读", false)
}

// 南半球/西经:半球标记必须变成负号,否则会把悉尼标到中国内蒙古上空。
if true {
    let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("kitcheck-exif-sw.jpg")
    let d = CGImageDestinationCreateWithURL(u as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, ctx.makeImage()!, [
        kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 33.8688, kCGImagePropertyGPSLatitudeRef: "S",
            kCGImagePropertyGPSLongitude: 118.2437, kCGImagePropertyGPSLongitudeRef: "W",
            kCGImagePropertyGPSAltitude: 12.0, kCGImagePropertyGPSAltitudeRef: 1,
        ] as [CFString: Any],
    ] as CFDictionary)
    CGImageDestinationFinalize(d)
    defer { try? FileManager.default.removeItem(at: u) }
    let e = ImageMetadata.exif(u)
    check("南纬西经取负", e.latitude.map { $0 < 0 } == true && e.longitude.map { $0 < 0 } == true)
    check("海平面以下海拔取负", e.altitude.map { $0 < 0 } == true)
}

check("无 EXIF 的图返回空信息", ImageMetadata.exif(editPNG).isEmpty)

section("ImageMeta(元数据剥离)")

/// 解码后的原始像素字节。用来证明剥离没有重新编码。
func decodedBytes(_ url: URL) -> Data? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
          let data = img.dataProvider?.data else { return nil }
    return data as Data
}

check("StripLevel.none 不产出文件", ImageMetadata.strippedCopy(of: dirtyJPEG, level: .none) == nil)

// .location:只拿掉定位,曝光参数与机型留着(摄影者要的那部分)。
if let out = ImageMetadata.strippedCopy(of: dirtyJPEG, level: .location) {
    defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }
    let e = ImageMetadata.exif(out)
    check(".location 后读不到坐标", e.latitude == nil && e.longitude == nil && !e.hasLocation)
    check(".location 后读不到海拔", e.altitude == nil)
    check(".location 保留机型", e.cameraModel == "iPhone 17 Pro")
    check(".location 保留曝光参数", e.iso == 64 && e.aperture != nil && e.shutterSeconds != nil)
    // 校验按档位判定:.location 的产物必然还有机型,拿"全干净"去卡它会让
    // 每一次 .location 剥离都被判失败并删掉产物。
    check(".location 满足本档承诺", StripLevel.location.isSatisfied(by: ImageMetadata.residual(out)))
    check(".location 达不到 identifying 的标准",
          !StripLevel.identifying.isSatisfied(by: ImageMetadata.residual(out)))
    // 剥的是标签不是像素:AddImageFromSource 整段搬运压缩数据,解码结果必须
    // 逐字节相同。这条一旦失守,等于给每张上传的 JPEG 白叠一代有损。
    check(".location 像素逐字节不变", decodedBytes(dirtyJPEG) == decodedBytes(out))
} else {
    check(".location 剥离成功", false)
}

// .identifying:默认档,定位 + 设备身份全清,曝光参数留下。
if let out = ImageMetadata.strippedCopy(of: dirtyJPEG, level: .identifying) {
    defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }
    let e = ImageMetadata.exif(out)
    check(".identifying 后读不到坐标", !e.hasLocation && e.altitude == nil)
    check(".identifying 后读不到设备", e.cameraMake == nil && e.cameraModel == nil
        && e.lensModel == nil && e.software == nil)
    check(".identifying 判定为无身份信息", !e.hasIdentifyingInfo)
    check(".identifying 保留曝光参数", e.iso == 64 && e.aperture != nil)
    check(".identifying 回读校验通过", ImageMetadata.residual(out).isPrivacyClean)
    // 剥的是标签不是像素:尺寸与方向都得原样活着,否则竖拍照片会横过来。
    if let m = ImageMetadata.read(out) {
        check(".identifying 像素尺寸不变", m.pixelWidth == 8 && m.pixelHeight == 6)
        check(".identifying 方向标签存活", m.orientation == 6)
    } else {
        check(".identifying 产物可读", false)
    }
    check(".identifying 产物保留原文件名", out.lastPathComponent == dirtyJPEG.lastPathComponent)
} else {
    check(".identifying 剥离成功", false)
}

// .all:除方向外全清。
if let out = ImageMetadata.strippedCopy(of: dirtyJPEG, level: .all) {
    defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }
    let e = ImageMetadata.exif(out)
    check(".all 后 EXIF 为空", e.isEmpty)
    check(".all 回读校验通过", ImageMetadata.residual(out).isPrivacyClean)
    if let m = ImageMetadata.read(out) {
        check(".all 像素尺寸不变", m.pixelWidth == 8 && m.pixelHeight == 6)
        check(".all 方向标签存活", m.orientation == 6)
    } else {
        check(".all 产物可读", false)
    }
} else {
    check(".all 剥离成功", false)
}

// 校验本身要有效:拿原图(必然不干净)喂 residual,必须报脏。否则上面那串
// "回读校验通过"可能只是 residual 永远返回 clean。
check("residual 能认出脏文件", !ImageMetadata.residual(dirtyJPEG).isPrivacyClean)
check("residual 认出定位", ImageMetadata.residual(dirtyJPEG).hasLocation)
check("residual 认出设备", ImageMetadata.residual(dirtyJPEG).hasDeviceInfo)

// XMP 是 EXIF 之外的第二套元数据,常带 GPS 与作者的副本。ImageMeta 没为它
// 写任何专门代码,靠的是"传了属性字典 ImageIO 就重建整份 XMP"这条实测行为
// ——那是系统实现细节,不是契约,所以必须有断言盯着。这条炸了说明系统换了
// 行为,得回去补显式的 XMP 清理。
if true {
    let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("kitcheck-xmp.jpg")
    let d = CGImageDestinationCreateWithURL(u as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    let md = CGImageMetadataCreateMutable()
    CGImageMetadataSetValueMatchingImageProperty(md, kCGImagePropertyGPSDictionary,
                                                 kCGImagePropertyGPSLatitude, 39.9087 as CFNumber)
    CGImageMetadataSetValueMatchingImageProperty(md, kCGImagePropertyGPSDictionary,
                                                 kCGImagePropertyGPSLatitudeRef, "N" as CFString)
    CGImageMetadataSetValueMatchingImageProperty(md, kCGImagePropertyGPSDictionary,
                                                 kCGImagePropertyGPSLongitude, 116.3975 as CFNumber)
    CGImageMetadataSetValueMatchingImageProperty(md, kCGImagePropertyGPSDictionary,
                                                 kCGImagePropertyGPSLongitudeRef, "E" as CFString)
    // dc:creator 走自定义命名空间,属性字典里根本没有对应键——最能说明
    // "XMP 是被整份重建的"而不是"恰好每个键都被点名删了"。
    CGImageMetadataRegisterNamespaceForPrefix(
        md, "http://purl.org/dc/elements/1.1/" as CFString, "dc" as CFString, nil)
    if let tag = CGImageMetadataTagCreate("http://purl.org/dc/elements/1.1/" as CFString,
                                          "dc" as CFString, "creator" as CFString,
                                          .string, "西风 @ 家里" as CFString) {
        CGImageMetadataSetTagWithPath(md, nil, "dc:creator" as CFString, tag)
    }
    CGImageDestinationAddImageAndMetadata(d, ctx.makeImage()!, md, nil)
    CGImageDestinationFinalize(d)
    defer { try? FileManager.default.removeItem(at: u) }

    func xmpNames(_ url: URL) -> Set<String> {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil),
              let m = CGImageSourceCopyMetadataAtIndex(s, 0, nil),
              let tags = CGImageMetadataCopyTags(m) as? [CGImageMetadataTag] else { return [] }
        return Set(tags.compactMap { CGImageMetadataTagCopyName($0) as String? })
    }

    let beforeTags = xmpNames(u)
    check("样张 XMP 确实带定位与作者",
          beforeTags.contains("GPSLatitude") && beforeTags.contains("creator"))
    check("XMP 里的定位也被 residual 认出", ImageMetadata.residual(u).hasLocation)
    if let out = ImageMetadata.strippedCopy(of: u, level: .identifying) {
        defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }
        let afterTags = xmpNames(out)
        check("剥离后 XMP 无定位",
              !afterTags.contains("GPSLatitude") && !afterTags.contains("GPSLongitude"))
        check("剥离后 XMP 无自定义命名空间残留", !afterTags.contains("creator"))
        check("剥离后 XMP 定位回读为空", !ImageMetadata.residual(out).hasLocation)
    } else {
        check("带 XMP 的图剥离成功", false)
    }
}

section("SizePresets(比例与尺寸预设)")

check("比例选项齐全", SizePresets.ratios.count == 7 && SizePresets.ratios.first == .free)
check("自由裁剪无比例约束", CropRatio.free.pixelRatio == nil && CropRatio.free.intent == nil)
check("16:9 比例值", CropRatio.landscape16x9.pixelRatio.map { abs($0 - 16.0 / 9) < 1e-9 } == true)
check("9:16 是 16:9 的倒数", (CropRatio.portrait9x16.pixelRatio! * CropRatio.landscape16x9.pixelRatio!) == 1)
check("预设 id 唯一", Set(SizePresets.all.map(\.id)).count == SizePresets.all.count)
check("预设覆盖五个平台", Set(SizePresets.all.map(\.platform)) == Set(SocialPlatform.allCases))
check("公众号头条封面 900×383", SizePresets.preset(id: "wechat.mp.cover.head")?.pixels == PixelSize(900, 383))
check("小红书竖版 1080×1440 且为 3:4",
      SizePresets.preset(id: "xhs.note.portrait")?.pixels == PixelSize(1080, 1440)
      && abs((SizePresets.preset(id: "xhs.note.portrait")?.intent.pixelRatio ?? 0) - 0.75) < 1e-9)
check("抖音封面 1080×1920 且为 9:16",
      SizePresets.preset(id: "douyin.cover")?.pixels == PixelSize(1080, 1920))
check("按平台筛选", SizePresets.presets(for: .instagram).count == 4)
check("未知 id 返回 nil", SizePresets.preset(id: "nope") == nil)

// ratio 与 exact 的分界:前者只重塑裁剪框,后者还锁导出宽度。这条搞反了,
// 用户选个构图比例就会被偷偷降分辨率。
if true {
    let canvas = CGSize(width: 4000, height: 3000)
    var s = EditSpec()
    s.exportMaxWidth = 2400
    s.apply(.ratio(16.0 / 9), canvas: canvas)
    check("ratio 不动导出宽度", s.exportMaxWidth == 2400)
    let c = s.crop!
    let r = (c.width * canvas.width) / (c.height * canvas.height)
    check("ratio 重塑裁剪框到 16:9", abs(r - 16.0 / 9) < 1e-6)

    var t = EditSpec()
    t.exportMaxWidth = 2400
    t.apply(.exact(PixelSize(1080, 1440)), canvas: canvas)
    check("exact 锁定导出宽度", t.exportMaxWidth == 1080)
    let tc = t.crop!
    let tr = (tc.width * canvas.width) / (tc.height * canvas.height)
    check("exact 同时重塑裁剪框到 3:4", abs(tr - 0.75) < 1e-6)
    check("裁剪框仍在画布内",
          tc.minX >= -1e-9 && tc.minY >= -1e-9 && tc.maxX <= 1 + 1e-9 && tc.maxY <= 1 + 1e-9)
}

check("free 不改配方", {
    var s = EditSpec()
    s.apply(CropRatio.free, canvas: CGSize(width: 100, height: 100))
    return s.crop == nil && s.exportMaxWidth == 0
}())

// 导出只缩不放:源图不够宽时如实交付原尺寸,并让界面能提示。
if true {
    let intent = SizeIntent.exact(PixelSize(1080, 1440))
    let big = CGSize(width: 3000, height: 4000)
    let small = CGSize(width: 600, height: 800)
    check("大图缩到目标宽", intent.resultPixels(cropped: big) == CGSize(width: 1080, height: 1440))
    check("小图不放大", intent.resultPixels(cropped: small) == small)
    check("小图标记为需要放大", intent.needsUpscale(cropped: small) && !intent.needsUpscale(cropped: big))
    check("ratio 意图不谈像素", SizeIntent.ratio(1).resultPixels(cropped: small) == small
        && !SizeIntent.ratio(1).needsUpscale(cropped: small))
}

// 端到端:预设 → 配方 → 真渲染,产物像素必须落在目标尺寸上(取整误差 ±1)。
// 只断言配方字段等于没验证——渲染管线用不用得上这两个字段是另一回事。
if true {
    let src = makeSamplePNG(width: 2000, height: 1500)
    defer { try? FileManager.default.removeItem(at: src) }
    var s = EditSpec()
    s.apply(SizePresets.preset(id: "x.post.single")!.intent,
            canvas: CGSize(width: 2000, height: 1500))
    if let out = ImageEdit.render(source: src, spec: s), let m = ImageMetadata.read(out) {
        defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }
        check("预设端到端:导出宽 1600", m.pixelWidth == 1600)
        check("预设端到端:导出高 900(±1)", abs(m.pixelHeight - 900) <= 1)
    } else {
        check("预设端到端渲染成功", false)
    }
}

// MARK: - Result

print("\n\(checks - failures)/\(checks) 通过")
if failures > 0 {
    print("\(failures) 项失败")
    exit(1)
}
