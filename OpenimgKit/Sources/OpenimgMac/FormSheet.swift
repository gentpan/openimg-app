import SwiftUI

/// 设置页里那些"要填一会儿"的表单的容器。
///
/// 原来它们是就地展开的:点一下按钮,卡片自己长高,后面的卡跟着往下跳。表单
/// 一多就分不清哪块属于哪张卡,填到一半滚动位置还会变。macOS 对这种"一次
/// 只做一件事"的输入本来就有答案——模态窗:焦点收在一处,Esc 取消,回车确认,
/// 关掉后设置页原样不动。
///
/// 三个表单(改密码、添加 Passkey、存储位置)共用这一个容器,免得各写一套
/// 标题栏和按钮排布,慢慢长歪。
struct FormSheet<Content: View, Footer: View>: View {
    let title: String
    /// 标题下的一句话,说清这个窗要干什么。
    var subtitle: String?
    var width: CGFloat = 420
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider().overlay(Color.white.opacity(0.06))

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    content
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // 内容不多时不该撑出一片空白,多了又要能滚。
            .frame(maxHeight: 460)

            Divider().overlay(Color.white.opacity(0.06))

            HStack(spacing: 8) {
                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: width)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
