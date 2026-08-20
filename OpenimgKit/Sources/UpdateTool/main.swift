import CryptoKit
import Foundation
import OpenimgKit

// 打包与发布脚本用的小工具。
//
// 存在的理由是"公式与格式只有一份":build 号的算法、清单的字节形态、验签的
// 方式都在 OpenimgKit 里,由 KitCheck 钉住,脚本调这个工具去用,而不是在 bash
// 里再写一遍。两处各写各的迟早对不上,而对不上的表现是「明明发了新版,老客户
// 端检测不到」——不报错、不打日志,只是永远没有更新。

let args = Array(CommandLine.arguments.dropFirst())

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(1)
}

func usage() -> Never {
    die("""
    用法:
      UpdateTool build-number <版本号>
          把 0.3.0 换算成 CFBundleVersion

      UpdateTool keygen
          生成一对 Ed25519 密钥。私钥打印在 stderr(只此一次),公钥打印在 stdout。

      UpdateTool sign --key <私钥文件> --key-id <k1> --version <0.4.0> \\
                      --zip <包路径> --url <下载地址> [--notes-url <说明地址>] \\
                      [--revoked-below <版本>] [--out <清单路径>]
          生成并签一份更新清单。签完自己回验一遍。

      UpdateTool verify --pubkey <公钥> --key-id <k1> <清单文件>
          用公钥回验一份清单。发布前的自检。
    """)
}

func value(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func required(_ name: String) -> String {
    guard let v = value(name) else { die("缺少参数 \(name)") }
    return v
}

guard let cmd = args.first else { usage() }

switch cmd {

case "build-number":
    guard args.count == 2 else { die("用法: UpdateTool build-number <版本号>") }
    guard let v = SemanticVersion(args[1]) else {
        die("解不出版本号: \(args[1]) —— 要形如 0.3.0 或 v0.3.0")
    }
    guard let n = v.buildNumber else {
        die("\(v) 没有 build 号 —— 预发布版本不支持(见 SemanticVersion.buildNumber)")
    }
    print(n)

case "keygen":
    let sk = Curve25519.Signing.PrivateKey()
    // 私钥走 stderr:管道重定向 stdout 的调用方不会把它写进文件或日志里,
    // 而人在终端上仍然看得见。它只会出现这一次。
    FileHandle.standardError.write(Data("""
    私钥(只此一次,离线保管,别进版本库):
    \(sk.rawRepresentation.base64EncodedString())

    """.utf8))
    print(sk.publicKey.rawRepresentation.base64EncodedString())

case "sign":
    let keyPath = required("--key")
    let keyID = required("--key-id")
    let versionRaw = required("--version")
    let zipPath = required("--zip")
    let url = required("--url")
    let notesURL = value("--notes-url")
    let revokedBelow = value("--revoked-below")
    let out = value("--out")

    guard let v = SemanticVersion(versionRaw) else { die("解不出版本号: \(versionRaw)") }
    guard let build = v.buildNumber else { die("\(v) 没有 build 号") }
    guard let zip = FileManager.default.contents(atPath: zipPath) else {
        die("读不到包: \(zipPath)")
    }
    guard let keyText = try? String(contentsOfFile: keyPath, encoding: .utf8),
          let keyData = Data(base64Encoded: keyText.trimmingCharacters(in: .whitespacesAndNewlines)),
          let sk = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) else {
        die("读不出私钥: \(keyPath)")
    }
    // 地址在生成时就过白名单,不要等到客户端才发现——发布前发现比线上发现便宜。
    guard UpdateURL.check(url) != nil else { die("下载地址不在白名单里: \(url)") }
    if let n = notesURL, UpdateURL.check(n) == nil { die("说明地址不在白名单里: \(n)") }

    let sha = SHA256.hash(data: zip).map { String(format: "%02x", $0) }.joined()
    let now = Date()
    let fmt = ISO8601DateFormatter()

    var payloadObj: [String: Any] = [
        "schema": 1,
        // seq 用签发时的 Unix 秒,不是 `git tag | wc -l`。
        //
        // 后者不单调:删掉一个打错的 tag 会让它下降,而客户端已经持久化了见过
        // 的最大值——**所有见过的客户端会永久拒收此后一切清单,服务端无法补救**。
        // 用时间戳还顺带让"不发版也能重签续期"成立。
        "seq": Int(now.timeIntervalSince1970),
        "issuedAt": fmt.string(from: now),
        // 90 天。过期只是提示,不是闸门——做成闸门的话,想续期就得重签,重签就
        // 要换 seq,于是"不发版就无法续期",而三个月不发版正是最可能发生的。
        "expiresAt": fmt.string(from: now.addingTimeInterval(90 * 86400)),
        "channel": "stable",
        "latest": [
            "version": v.description,
            "build": build,
            "minimumSystemVersion": "14.0.0",
            "arch": "arm64",
            "url": url,
            "size": zip.count,
            "sha256": sha,
        ],
        "revokeKeys": [String](),
    ]
    if var latest = payloadObj["latest"] as? [String: Any], let n = notesURL {
        latest["notesURL"] = n
        payloadObj["latest"] = latest
    }
    if let rb = revokedBelow, !rb.isEmpty {
        guard SemanticVersion(rb) != nil else { die("revoked-below 解不出: \(rb)") }
        payloadObj["revokedBelow"] = rb
    }

    guard let payload = try? JSONSerialization.data(withJSONObject: payloadObj,
                                                    options: [.sortedKeys]) else {
        die("清单序列化失败")
    }
    guard let sig = try? sk.signature(for: payload) else { die("签名失败") }

    let envelope: [String: Any] = [
        "payload": payload.base64EncodedString(),
        "sig": sig.base64EncodedString(),
        "keyId": keyID,
    ]
    guard let env = try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]) else {
        die("信封序列化失败")
    }

    // 签完立刻用配套公钥回验一遍。发布前发现问题比线上发现便宜得多,而这一步
    // 走的正是客户端将来会走的那条代码路径。
    do {
        let m = try UpdateManifest.parse(
            env, contentType: "application/json", status: 200,
            publicKeys: [keyID: sk.publicKey.rawRepresentation])
        guard m.latest.version == v, m.latest.sha256 == sha else {
            die("自检失败:回验出来的内容与写入的不一致")
        }
    } catch {
        die("自检失败:签完的清单自己验不过 —— \(error.localizedDescription)")
    }

    if let out {
        try? env.write(to: URL(fileURLWithPath: out))
        // pretty 版只给人看,贴进 release notes。客户端永远不读它,所以不给它
        // 开路由——少一个端点。
        if let pretty = try? JSONSerialization.data(withJSONObject: payloadObj,
                                                    options: [.prettyPrinted, .sortedKeys]) {
            try? pretty.write(to: URL(fileURLWithPath: out + ".pretty.json"))
        }
        FileHandle.standardError.write(Data("清单已写入 \(out)(自检通过)\n".utf8))
    } else {
        print(String(decoding: env, as: UTF8.self))
    }

case "verify":
    let pub = required("--pubkey")
    let keyID = required("--key-id")
    guard let path = args.last, !path.hasPrefix("--") else { die("缺少清单文件") }
    guard let data = FileManager.default.contents(atPath: path) else { die("读不到清单: \(path)") }
    guard let raw = Data(base64Encoded: pub.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        die("公钥不是合法 base64")
    }
    do {
        let m = try UpdateManifest.parse(data, contentType: "application/json", status: 200,
                                         publicKeys: [keyID: raw])
        print("验签通过:\(m.latest.version) (build \(m.latest.build)) seq=\(m.seq)")
    } catch {
        die("验签失败:\(error.localizedDescription)")
    }

default:
    usage()
}
