import Foundation
import OpenimgKit

// 打包与发布脚本用的小工具。
//
// 存在的唯一理由是"公式只有一份":build 号的算法在 OpenimgKit 里,由 KitCheck
// 钉住,打包脚本调这个工具去取,而不是在 bash 里再写一遍同样的算术。两处各写各
// 的迟早对不上,而对不上的表现是「明明发了新版,老客户端检测不到」——不报错、
// 不打日志,只是永远没有更新。

let args = Array(CommandLine.arguments.dropFirst())

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(1)
}

guard let cmd = args.first else {
    die("""
    用法:
      UpdateTool build-number <版本号>   把 0.3.0 换算成 CFBundleVersion
    """)
}

switch cmd {
case "build-number":
    guard args.count == 2 else { die("用法: UpdateTool build-number <版本号>") }
    guard let v = SemanticVersion(args[1]) else {
        die("解不出版本号: \(args[1]) —— 要形如 0.3.0 或 v0.3.0")
    }
    guard let n = v.buildNumber else {
        die("\(v) 没有 build 号 —— 预发布版本不支持(见 SemanticVersion.buildNumber 的注释)")
    }
    print(n)

default:
    die("不认识的子命令: \(cmd)")
}
