import Foundation
import OpenimgKit

/// 这个 app 自己的版本。
///
/// 两个键都读:`CFBundleShortVersionString` 是人看的(0.3.0),
/// `CFBundleVersion` 是机器比的(3000)。后者原来在打包脚本里恒为 1 —— 而它的
/// 单调性正是系统、以及将来的更新检查用来判断"哪个更新"的唯一依据,恒为 1
/// 等于把那条依据整个作废了。
enum AppVersion {
    /// 人看的版本号,如 `0.3.0`。取不到时给一个明显不对的值,而不是空字符串:
    /// 界面上出现「版本 」比出现「版本 —」更难被发现。
    static var short: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    /// 机器比的 build 号。
    static var build: Int {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              let n = Int(s) else { return 0 }
        return n
    }

    /// 解析成可比较的形式,给将来的更新检查用。裸可执行文件(没有 bundle)下
    /// 拿不到,所以是可选的。
    static var semantic: SemanticVersion? { SemanticVersion(short) }

    /// 设置页上显示的那一行。build 号跟在后面加括号:它平时没人看,但用户报
    /// 问题时那个数字能一眼分清是不是同一个包。
    static var display: String {
        build > 0 ? "\(short) (\(build))" : short
    }
}
