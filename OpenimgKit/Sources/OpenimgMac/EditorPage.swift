import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OpenimgKit

/// 编辑页。
///
/// 编辑器原来只是上传页弹出来的一张 sheet,而它现在能裁剪、打码、旋转、加
/// 水印、去背景、自动增强——这已经是一件独立的事,不该寄居在别人的弹窗里。
/// 提成主页面之后:窗口有多大画布就有多大,笔刷精度跟着涨;换页面回来编辑
/// 状态还在;上传页也不必再替它承担一个入口。
struct EditorPage: View {
    @ObservedObject var model: AppModel
    @State private var dropping = false

    var body: some View {
        Group {
            if let target = model.editTarget {
                EditorCanvas(model: model, source: target.url)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 没有在编辑时,整页就是一个入口——和上传页的投放区同一套语言。
    private var emptyState: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(dropping ? Color.brand.opacity(0.14) : .white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(dropping ? Color.brand : .white.opacity(0.14),
                                      style: StrokeStyle(lineWidth: dropping ? 2 : 1.2, dash: [7, 5]))
                )
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "crop.rotate")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(Color.brand)
                            .frame(width: 88, height: 88)
                            .background(Circle().fill(Color.brand.opacity(0.12)))
                        Text(L.s.editor.pageTitle).font(.title2.weight(.medium))
                        Text(L.s.editor.pageHint)
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { model.pickAndEdit() }
                .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
                    Task {
                        if let url = await Self.firstFileURL(from: providers) {
                            model.openEditor(url)
                        }
                    }
                    return true
                }
                .animation(.easeOut(duration: 0.15), value: dropping)

            HStack(spacing: 18) {
                capability("crop", L.s.editor.capCrop)
                capability("mosaic.fill", L.s.editor.capMosaic)
                capability("wand.and.stars", L.s.editor.capEnhance)
                capability("person.and.background.dotted", L.s.editor.capCutout)
                capability("signature", L.s.editor.capWatermark)
            }
            .padding(.bottom, 4)

            Text(L.s.editor.localOnlyNote)
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 18)
    }

    private func capability(_ icon: String, _ label: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.brand)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.white.opacity(0.05)))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private static func firstFileURL(from providers: [NSItemProvider]) async -> URL? {
        for p in providers {
            let data: Data? = await withCheckedContinuation { cont in
                _ = p.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { d, _ in
                    cont.resume(returning: d)
                }
            }
            if let data, let url = URL(dataRepresentation: data, relativeTo: nil) { return url }
        }
        return nil
    }
}
