import SwiftUI
import OpenimgKit

/// 版本号下面那一行:检查更新的状态与入口。
///
/// 这一版只发现、不安装。所以这里最重要的不是那颗按钮,而是**说清楚拿到新版
/// 之后要做什么**——「下载后拖进应用程序覆盖,图库和登录状态都不受影响」。
/// 不说这一句的话,人第一反应是"覆盖会不会把我的东西弄丢"。
struct UpdateRow: View {
    @ObservedObject var checker: UpdateChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                status
                Spacer(minLength: 8)
                if case .checking = checker.state {
                    ProgressView().controlSize(.small)
                } else {
                    Button(L.s.settings.updateCheck) { Task { await checker.check() } }
                        .buttonStyle(QuietButton())
                        .controlSize(.small)
                }
            }

            if case .available(let r, let stale, let urgent) = checker.state {
                // 「怎么装」跟着「有新版」一起出现,而不是等用户点开某处才说。
                Text(L.s.settings.updateHowTo)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if urgent {
                    Text(L.s.settings.updateUrgent)
                        .font(.caption2).foregroundStyle(.orange)
                }
                if let stale {
                    // 过期是提示不是拦截:清单可能只是很久没重签了,不代表这条
                    // 消息是错的。
                    Text(L.s.settings.updateStale(stale))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                if let notes = r.notesURL {
                    Button(L.s.settings.updateNotes) { NSWorkspace.shared.open(notes) }
                        .buttonStyle(BrandButton())
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch checker.state {
        case .idle:
            EmptyView()
        case .checking:
            Text(L.s.settings.updateChecking).font(.caption).foregroundStyle(.secondary)
        case .upToDate:
            Text(L.s.settings.updateUpToDate).font(.caption).foregroundStyle(.secondary)
        case .available(let r, _, _):
            Text(L.s.settings.updateAvailable(r.version.description))
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.brand)
        case .blocked(let why, let latest):
            // 「有新版但你这台装不了」必须说全,不能显示成"已是最新"——用户在
            // 别处看到有新版而这里说最新,会以为检查坏了。
            VStack(alignment: .leading, spacing: 2) {
                Text(L.s.settings.updateAvailable(latest.description))
                    .font(.callout).foregroundStyle(.secondary)
                switch why {
                case .systemTooOld(let needs):
                    Text(L.s.settings.updateTooOld(needs.description))
                        .font(.caption2).foregroundStyle(.orange)
                case .wrongArch:
                    Text(L.s.settings.updateWrongArch)
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        case .failed(let why):
            // 检查更新失败不该打扰人。原因留在这里给想看的人,不弹任何东西。
            VStack(alignment: .leading, spacing: 2) {
                Text(L.s.settings.updateFailed).font(.caption).foregroundStyle(.secondary)
                Text(why).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
            }
        }
    }
}
