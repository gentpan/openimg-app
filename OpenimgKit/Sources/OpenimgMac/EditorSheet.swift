import SwiftUI
import AppKit
import OpenimgKit

/// 编辑入口的载体:sheet(item:) 需要 Identifiable。
struct EditTarget: Identifiable {
    let id = UUID()
    let url: URL
}

extension AppModel {
    /// 挑一张图进编辑器;动图明说不支持,而不是静默取首帧丢动画。
    /// 从别处(上传页按钮、菜单)进编辑:选完图直接落到编辑页。
    func pickAndEdit() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = L.s.editor.pickPrompt
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openEditor(url)
    }

    func openEditor(_ url: URL) {
        switch ImageEdit.editability(url) {
        case .ok:
            editTarget = EditTarget(url: url)
        case .animated:
            announce(L.s.editor.animatedUnsupported)
        case .tooLarge:
            announce(L.s.editor.tooLarge(ImageEdit.maxEditPixels / 1_000_000))
        case .unreadable:
            announce(L.s.editor.unreadable)
        }
    }

    /// 从图库右键进编辑器:先把原图取回本地,再落到编辑页。
    ///
    /// 改出来的结果是**另一张图**,不是原地覆盖。已入库的对象是不可变的
    /// ——按 SHA 去重、进了 CDN 缓存、可能已经有短链在外面流传;原地改会
    /// 让所有已发出去的链接指向一张别的图。所以这里只负责把原图变成一份
    /// 本地素材,存盘时走的仍是正常的上传流水线。
    ///
    /// 取的是公开对象地址,不带令牌——与 Exporter 同一条纪律:令牌不发给
    /// 第三方存储主机。
    func editFromGallery(_ img: RemoteImage) async {
        guard let src = URL(string: img.url) else {
            announce(L.s.gallery.editFetchFailed)
            return
        }
        announce(L.s.gallery.editFetching)

        // 缓存到临时目录并按图片 ID 命名:同一张图反复编辑不必重下,而临时
        // 目录由系统回收,不用自己管生命周期。
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("edit-\(img.id).\(img.ext)")
        if !FileManager.default.fileExists(atPath: dest.path) {
            do {
                let (data, resp) = try await URLSession.shared.data(from: src)
                guard let http = resp as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode), !data.isEmpty else {
                    announce(L.s.gallery.editFetchFailed)
                    return
                }
                try data.write(to: dest, options: .atomic)
            } catch {
                announce(L.s.gallery.editFetchFailed)
                return
            }
        }

        // 能不能编辑(动图、超大图)交给 openEditor 判定,它会给出对应的说法。
        openEditor(dest)
        if editTarget != nil { section = .editor }
    }

    /// 拖放路由:开了"单张先编辑"且**拖的就是单个文件**时进编辑器——按
    /// 原始拖放物判定,不按 expand 展开后的数量,否则"恰好含一张图的文件
    /// 夹"也会弹编辑器,和开关文案矛盾。
    func handleDrop(_ urls: [URL]) async {
        if editOnDrop, urls.count == 1, let one = urls.first,
           (try? one.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true,
           ImageEdit.editable(one) {
            editTarget = EditTarget(url: one)
            return
        }
        await upload(expand(urls))
    }

    /// 编辑确认:渲染进现有上传队列。没有实际编辑就传原件——不为"点了
    /// 编辑"这个动作本身付一次重编码。
    ///
    /// 渲染失败**绝不回落上传原件**:马赛克的用途就是涂掉隐私,失败时把
    /// 未打码的原图静默传上去是这条管线最坏的失败模式。保持编辑器打开
    /// (笔迹还在),播报错误让用户重试。
    func confirmEdit(source: URL, spec: EditSpec) {
        Task {
            guard spec.hasEdits else {
                editTarget = nil
                await upload([source])
                return
            }
            editSubmitting = true
            defer { editSubmitting = false }
            let rendered = await Task.detached { ImageEdit.render(source: source, spec: spec) }.value
            guard let out = rendered else {
                announce(L.s.editor.renderFailed)
                return
            }
            editTarget = nil
            await upload([out])
            try? FileManager.default.removeItem(at: out.deletingLastPathComponent())
        }
    }
}

/// 上传前编辑器:裁剪 / 马赛克 / 旋转 / 水印。
///
/// 预览 = Kit 渲染的降采样底图(旋转+马赛克) + 画布叠加层(裁剪框、水印
/// 文字)——底图与成品走同一段渲染代码,所见即所得不靠两套绘制对齐。
struct EditorCanvas: View {
    @ObservedObject var model: AppModel
    let source: URL

    @State private var spec = EditSpec()
    @State private var mode: Mode = .crop
    @State private var brush = 0.018            // 归一化到对角线
    @State private var wmOn = false
    @State private var preview: CGImage?
    /// 预览底图(解码+变换+增强+抠图的结果)与它的生成键。
    ///
    /// 缓存它是因为这几步里有 Vision 的前景分割,一次几百毫秒;而调色是连续
    /// 滑块,拖一次能来几十帧。键相等就直接复用,只重跑便宜的那一半。
    @State private var previewBase: CGImage?
    @State private var previewBaseKey: ImageEdit.PreviewBaseKey?
    /// 源图像素尺寸,头部读取——画布几何基准从它+旋转次数推导,不依赖
    /// 预览是否渲染完,旋转窗口期的比例/手势才不会用错画布。
    @State private var sourcePixelSize: CGSize = .zero
    @State private var activeStroke: [CGPoint] = []   // 进行中的笔迹(归一化)
    /// 已提交、底图还没带上的笔迹:保持不透明叠加,别让刚遮住的内容在
    /// 渲染空窗里裸露闪现。
    @State private var pendingStroke: [CGPoint] = []
    @State private var pendingBrush = 0.018
    @State private var cropDrag: CropDrag?
    @State private var rendering = false
    /// 预览代数:连点旋转时旧渲染结果可能后到,只认最新一代。
    @State private var previewGen = 0
    @State private var showCancelConfirm = false
    @State private var suppressRatioReapply = false

    private static let transposedRatio = ["4:3": "3:4", "3:4": "4:3", "16:9": "9:16", "9:16": "16:9"]

    enum Mode: String, CaseIterable {
        case crop, mosaic

        /// rawValue 是稳定标识,显示名单独取——切语言不该动到状态值。
        var label: String {
            self == .crop ? L.s.editor.modeCrop : L.s.editor.modeMosaic
        }
    }

    private struct CropDrag {
        enum Kind { case move, new, corner(Int) }   // corner: 0 左上 1 右上 2 左下 3 右下
        var kind: Kind
        var startRect: CGRect
        var startPoint: CGPoint     // 归一化
    }

    private struct RatioPreset: Identifiable {
        let id: String              // 稳定标识,不随语言变
        let label: String
        let ratio: Double?          // 像素比 w/h,nil = 自由
    }
    /// 写成计算属性而非 static let:自由比例的显示名要跟着当前语言走,
    /// static let 只会在首次取用时定死一次。
    private static var ratios: [RatioPreset] {
        [
            .init(id: freeRatioID, label: L.s.editor.ratioFree, ratio: nil),
            .init(id: "1:1", label: "1:1", ratio: 1),
            .init(id: "4:3", label: "4:3", ratio: 4 / 3),
            .init(id: "16:9", label: "16:9", ratio: 16 / 9),
            .init(id: "3:4", label: "3:4", ratio: 3 / 4),
            .init(id: "9:16", label: "9:16", ratio: 9 / 16),
        ]
    }
    private static let freeRatioID = "free"
    @State private var ratioID = EditorCanvas.freeRatioID

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Color.white.opacity(0.08))
            canvas
            Divider().overlay(Color.white.opacity(0.08))
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.35))
        .task {
            sourcePixelSize = ImageEdit.pixelSize(of: source) ?? .zero
            await refreshPreview()
        }
        .onChange(of: mode) { _, _ in activeStroke = [] }
        .overlay {
            if showCancelConfirm {
                ConfirmDialog(
                    title: L.s.editor.discardTitle,
                    message: L.s.editor.discardMessage,
                    confirmTitle: L.s.editor.discardConfirm,
                    cancelTitle: L.s.editor.keepEditing,
                    onConfirm: { _ in showCancelConfirm = false; model.editTarget = nil },
                    onCancel: { showCancelConfirm = false })
            }
        }
        .animation(.easeOut(duration: 0.15), value: showCancelConfirm)
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack(spacing: 14) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.label) }
            }
            .pickerStyle(.segmented)
            .frame(width: 170)

            if mode == .crop {
                Picker(L.s.editor.ratioLabel, selection: $ratioID) {
                    ForEach(Self.ratios) { Text($0.label).tag($0.id) }
                }
                // 留给英文的 Ratio / Freeform:中文「比例」「自由」各两字,
                // 按中文收紧宽度英文就会截成 Freefor…。
                .frame(width: 160)
                .onChange(of: ratioID) { _, id in
                    // 旋转按钮转置比例时只换显示,框已被 rotateSpecCW 转好,
                    // 重套一遍反而会用错基准。
                    if suppressRatioReapply {
                        suppressRatioReapply = false
                        return
                    }
                    guard let ratio = Self.ratios.first(where: { $0.id == id })?.ratio else { return }
                    // 走 EditSpec.apply:它从整幅按比例重新起算(保留原框中心),
                    // 而不是拿当前框再削一刀——后者切来切去只会越切越小。
                    spec.apply(.ratio(ratio), canvas: rotatedPixelSize)
                }
                Button(L.s.editor.clearCrop) { spec.crop = nil; ratioID = Self.freeRatioID }
                    .buttonStyle(QuietButton())
                    .disabled(spec.crop == nil)
            }

            if mode == .mosaic {
                Picker("", selection: $spec.mosaicStyle) {
                    Text(L.s.editor.mosaicPixelate).tag(MosaicStyle.pixelate)
                    Text(L.s.editor.mosaicSolid).tag(MosaicStyle.solid)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .onChange(of: spec.mosaicStyle) { _, _ in Task { await refreshPreview() } }
                Text(L.s.editor.brush).font(.caption).foregroundStyle(.secondary)
                Slider(value: $brush, in: 0.006...0.06).frame(width: 110)
                Button(L.s.editor.undoStroke) {
                    _ = spec.strokes.popLast()
                    Task { await refreshPreview() }
                }
                .buttonStyle(QuietButton())
                .keyboardShortcut("z", modifiers: .command)
                .disabled(spec.strokes.isEmpty)
            }

            smartTools

            Button {
                spec = EditGeometry.rotateSpecCW(spec)
                // 比例随画面转置(16:9 → 9:16),只换显示不重套框。
                if let t = Self.transposedRatio[ratioID] {
                    suppressRatioReapply = true
                    ratioID = t
                }
                Task { await refreshPreview() }
            } label: { Label(L.s.editor.rotate, systemImage: "rotate.right") }
                .buttonStyle(QuietButton())

            Toggle(L.s.editor.watermark, isOn: $wmOn)
                .toggleStyle(.checkbox)
                .disabled(model.watermarkSpec() == nil)
                .help(model.watermarkSpec() == nil
                      ? L.s.editor.watermarkNeedsSetup : L.s.editor.watermarkHelp)

            Spacer()
            if rendering { ProgressView().controlSize(.small) }
            Text(source.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 200)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// 本机智能工具。全离线,不外发。开销比其它工具大(整幅重算),所以拆成
    /// 独立子视图——连同工具栏其余部分写在一个表达式里,类型检查器会直接
    /// 放弃诊断。
    @ViewBuilder private var smartTools: some View {
        Divider().frame(height: 18).overlay(Color.white.opacity(0.12))

        Toggle(isOn: $spec.enhance) {
            Label(L.s.editor.enhance, systemImage: "wand.and.stars")
        }
        .toggleStyle(.button)
        .disabled(rendering)
        .help(L.s.editor.enhanceHelp)
        .onChange(of: spec.enhance) { _, _ in
            Task { await refreshPreview() }
        }

        Toggle(isOn: $spec.cutout) {
            Label(L.s.editor.cutout, systemImage: "person.and.background.dotted")
        }
        .toggleStyle(.button)
        .disabled(rendering)
        .help(L.s.editor.cutoutHelp)
        .onChange(of: spec.cutout) { _, _ in
            Task { await refreshPreview() }
        }

        Divider().frame(height: 18).overlay(Color.white.opacity(0.12))
    }

    // MARK: - 画布

    private var canvas: some View {
        GeometryReader { geo in
            let fit = fittedRect(in: geo.size)
            ZStack {
                if let preview {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: fit.width, height: fit.height)
                        .position(x: fit.midX, y: fit.midY)
                } else {
                    ProgressView()
                }

                if mode == .mosaic, !activeStroke.isEmpty || !pendingStroke.isEmpty {
                    strokePreview(fit: fit)
                }
                if mode == .crop {
                    cropOverlay(fit: fit)
                }
                if wmOn, let wm = model.watermarkSpec() {
                    watermarkOverlay(wm, fit: fit)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(mode == .crop ? cropGesture(fit: fit) : nil)
            .gesture(mode == .mosaic ? mosaicGesture(fit: fit) : nil)
        }
        .padding(12)
    }

    /// 旋转后的像素尺寸(几何计算的画布基准)。从源尺寸+旋转次数推导而
    /// 不是取预览图尺寸——预览是异步渲染的,取它会让旋转后的窗口期用旧
    /// 朝向算比例和手势,错的裁剪框会写进 spec 持久污染。
    private var rotatedPixelSize: CGSize {
        guard sourcePixelSize.width > 0, sourcePixelSize.height > 0 else {
            guard let p = preview else { return CGSize(width: 1, height: 1) }
            return CGSize(width: p.width, height: p.height)
        }
        return EditGeometry.rotatedSize(sourcePixelSize, quarters: spec.rotationQuarters)
    }

    private func fittedRect(in avail: CGSize) -> CGRect {
        let ps = rotatedPixelSize
        guard ps.width > 0, ps.height > 0, avail.width > 0, avail.height > 0 else { return .zero }
        let scale = min(avail.width / ps.width, avail.height / ps.height)
        let w = ps.width * scale, h = ps.height * scale
        return CGRect(x: (avail.width - w) / 2, y: (avail.height - h) / 2, width: w, height: h)
    }

    private func normalize(_ p: CGPoint, in fit: CGRect) -> CGPoint {
        CGPoint(x: max(0, min(1, (p.x - fit.minX) / fit.width)),
                y: max(0, min(1, (p.y - fit.minY) / fit.height)))
    }

    // MARK: - 马赛克

    private func mosaicGesture(fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let p = normalize(v.location, in: fit)
                // 点距稀疏化:密集采样徒增路径长度不增覆盖。
                if let last = activeStroke.last {
                    let dx = p.x - last.x, dy = p.y - last.y
                    if (dx * dx + dy * dy).squareRoot() < brush / 3 { return }
                }
                activeStroke.append(p)
            }
            .onEnded { _ in
                guard !activeStroke.isEmpty else { return }
                spec.strokes.append(MosaicStroke(points: activeStroke, radius: brush))
                // 交给 pendingStroke 顶住渲染空窗:立即清叠加线会让刚遮住
                // 的内容在底图带上马赛克前裸露闪现。
                pendingStroke = activeStroke
                pendingBrush = brush
                activeStroke = []
                Task { await refreshPreview() }
            }
    }

    private func strokePath(_ points: [CGPoint], fit: CGRect) -> Path {
        Path { p in
            guard let first = points.first else { return }
            p.move(to: CGPoint(x: fit.minX + first.x * fit.width, y: fit.minY + first.y * fit.height))
            for pt in points.dropFirst() {
                p.addLine(to: CGPoint(x: fit.minX + pt.x * fit.width, y: fit.minY + pt.y * fit.height))
            }
        }
    }

    @ViewBuilder
    private func strokePreview(fit: CGRect) -> some View {
        let diag = (fit.width * fit.width + fit.height * fit.height).squareRoot()
        // 进行中笔迹:纯色模式直接给成品同款纯黑,像素化给覆盖性的灰——
        // 半透明品牌色会给"看起来没遮住"的错觉。
        let activeColor: Color = spec.mosaicStyle == .solid
            ? .black.opacity(0.9) : Color(white: 0.5, opacity: 0.9)
        let pendingColor: Color = spec.mosaicStyle == .solid
            ? .black : Color(white: 0.5, opacity: 0.95)
        if !pendingStroke.isEmpty {
            strokePath(pendingStroke, fit: fit)
                .stroke(pendingColor,
                        style: StrokeStyle(lineWidth: max(2, pendingBrush * 2 * diag),
                                           lineCap: .round, lineJoin: .round))
                .allowsHitTesting(false)
        }
        if !activeStroke.isEmpty {
            strokePath(activeStroke, fit: fit)
                .stroke(activeColor,
                        style: StrokeStyle(lineWidth: max(2, brush * 2 * diag),
                                           lineCap: .round, lineJoin: .round))
                .allowsHitTesting(false)
        }
    }

    // MARK: - 裁剪

    private func cropRect(in fit: CGRect) -> CGRect {
        let c = spec.crop ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        return CGRect(x: fit.minX + c.minX * fit.width, y: fit.minY + c.minY * fit.height,
                      width: c.width * fit.width, height: c.height * fit.height)
    }

    @ViewBuilder
    private func cropOverlay(fit: CGRect) -> some View {
        let r = cropRect(in: fit)
        // 框外压暗:even-odd 挖洞。
        Path { p in
            p.addRect(CGRect(origin: .zero, size: CGSize(width: 10_000, height: 10_000)))
            p.addRect(r)
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)

        Rectangle()
            .strokeBorder(Color.brand, lineWidth: 1.5)
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
            .allowsHitTesting(false)

        ForEach(0..<4, id: \.self) { i in
            let pt = cornerPoint(i, of: r)
            Circle()
                .fill(Color.brand)
                .frame(width: 11, height: 11)
                .position(pt)
                .allowsHitTesting(false)
        }
    }

    private func cornerPoint(_ i: Int, of r: CGRect) -> CGPoint {
        switch i {
        case 0: CGPoint(x: r.minX, y: r.minY)
        case 1: CGPoint(x: r.maxX, y: r.minY)
        case 2: CGPoint(x: r.minX, y: r.maxY)
        default: CGPoint(x: r.maxX, y: r.maxY)
        }
    }

    private func cropGesture(fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let p = normalize(v.location, in: fit)
                if cropDrag == nil {
                    cropDrag = beginCropDrag(at: v.startLocation, fit: fit)
                }
                guard let drag = cropDrag else { return }
                let ratio = Self.ratios.first(where: { $0.id == ratioID })?.ratio
                switch drag.kind {
                case .move:
                    // 移动只平移不改形状——重套比例会让框在拖动中变形。
                    var next = drag.startRect.offsetBy(dx: p.x - drag.startPoint.x,
                                                       dy: p.y - drag.startPoint.y)
                    next.origin.x = max(0, min(next.origin.x, 1 - next.width))
                    next.origin.y = max(0, min(next.origin.y, 1 - next.height))
                    spec.crop = next
                case .new:
                    spec.crop = constrained(anchor: drag.startPoint, cursor: p, ratio: ratio)
                case .corner(let idx):
                    // 对角固定,拖动角走:0↔3、1↔2 互为对角。
                    let anchor = cornerNorm(3 - idx, of: drag.startRect)
                    spec.crop = constrained(anchor: anchor, cursor: p, ratio: ratio)
                }
            }
            .onEnded { _ in cropDrag = nil }
    }

    /// 比例约束用锚点版:固定角钉死、框贴光标;中心重锚版只配比例下拉框。
    private func constrained(anchor: CGPoint, cursor: CGPoint, ratio: Double?) -> CGRect {
        if let ratio {
            return EditGeometry.applyRatio(anchor: anchor, cursor: cursor,
                                           pixelRatio: ratio, canvas: rotatedPixelSize)
        }
        return EditGeometry.clampCrop(rectFrom(anchor, cursor))
    }

    private func beginCropDrag(at viewPoint: CGPoint, fit: CGRect) -> CropDrag {
        let start = normalize(viewPoint, in: fit)
        let current = spec.crop ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let r = cropRect(in: fit)
        for i in 0..<4 where hypot(viewPoint.x - cornerPoint(i, of: r).x,
                                   viewPoint.y - cornerPoint(i, of: r).y) < 14 {
            return CropDrag(kind: .corner(i), startRect: current, startPoint: start)
        }
        // 框内(除四角)整体都是移动,不留边缘死区——底栏文案就是这么承诺的。
        if spec.crop != nil, r.contains(viewPoint) {
            return CropDrag(kind: .move, startRect: current, startPoint: start)
        }
        return CropDrag(kind: .new, startRect: current, startPoint: start)
    }

    private func rectFrom(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func cornerNorm(_ i: Int, of r: CGRect) -> CGPoint {
        switch i {
        case 0: CGPoint(x: r.minX, y: r.minY)
        case 1: CGPoint(x: r.maxX, y: r.minY)
        case 2: CGPoint(x: r.minX, y: r.maxY)
        default: CGPoint(x: r.maxX, y: r.maxY)
        }
    }

    // MARK: - 水印预览

    @ViewBuilder
    private func watermarkOverlay(_ wm: WatermarkSpec, fit: CGRect) -> some View {
        switch wm.kind {
        case .text: textWatermarkOverlay(wm, fit: fit)
        case .image: imageWatermarkOverlay(wm, fit: fit)
        }
    }

    /// 图片水印的叠加层。锚点几何与尺寸都取自 EditGeometry,与渲染同源——
    /// 理由与文字那边完全一样,见下。
    private func imageWatermarkOverlay(_ wm: WatermarkSpec, fit: CGRect) -> some View {
        let box = cropRect(in: fit)
        // 位图取自 model 而不是现解 wm.imagePNG:两者是同一份字节(这份配方
        // 正是从那里来的),而 body 一秒能跑几十次,每次解一张 1024px 的 PNG
        // 是白烧 CPU。
        let logo = model.wmImagePreview
        let size = EditGeometry.watermarkImageSize(
            logo: logo?.size ?? .zero, canvasWidth: box.width, scale: wm.scale)
        let o = EditGeometry.watermarkOrigin(
            anchor: wm.anchor, textSize: size, canvas: box.size,
            margin: EditGeometry.watermarkImageMargin(canvas: box.size))
        return Group {
            if let logo, size.width >= 1, size.height >= 1 {
                Image(nsImage: logo)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .opacity(wm.opacity)
                    .position(x: box.minX + o.x + size.width / 2,
                              y: box.minY + (box.height - o.y) - size.height / 2)
            }
        }
        .allowsHitTesting(false)
    }

    private func textWatermarkOverlay(_ wm: WatermarkSpec, fit: CGRect) -> some View {
        // 与渲染同一套几何:成品水印打在**裁剪后**的画布上,预览基准也必须
        // 是裁剪框(没有裁剪时即整幅)——否则裁剪+水印同开时位置和字号都
        // 是错的。字宽用与渲染同源的 CTLine 度量,不估算(0.62em/字对 CJK
        // 偏小近四成),字体也指定同款免得度量对不上。
        let box = cropRect(in: fit)
        let fontSize = max(6, wm.scale * box.width)
        let textSize = ImageEdit.watermarkTextSize(wm.text, fontSize: fontSize)
        let o = EditGeometry.watermarkOrigin(anchor: wm.anchor, textSize: textSize,
                                             canvas: box.size, margin: fontSize * 0.8)
        return Text(wm.text)
            .font(.custom("Helvetica-Bold", size: fontSize))
            .foregroundStyle(.white.opacity(wm.opacity))
            .shadow(color: .black.opacity(wm.opacity * 0.7), radius: 0, x: 1, y: 1)
            .position(x: box.minX + o.x + textSize.width / 2,
                      y: box.minY + (box.height - o.y) - textSize.height / 2)
            .allowsHitTesting(false)
    }

    // MARK: - 底栏

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button(L.s.editor.reset) {
                spec = EditSpec()
                ratioID = Self.freeRatioID
                wmOn = false
                pendingStroke = []
                activeStroke = []
                Task { await refreshPreview() }
            }
            .disabled(!spec.hasEdits && !wmOn)
            Spacer()
            if mode == .mosaic {
                Text(L.s.editor.mosaicHint).font(.caption).foregroundStyle(.tertiary)
            } else {
                Text(L.s.editor.cropHint).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            // macOS 惯例:取消紧贴默认按钮居右。有编辑时取消先确认——
            // Esc 一键蒸发掉涂了半天的马赛克太残忍。
            Button(L.s.editor.cancel) {
                if spec.hasEdits {
                    showCancelConfirm = true
                } else {
                    model.editTarget = nil
                }
            }
            .keyboardShortcut(.cancelAction)
            Button {
                var final = spec
                final.watermark = wmOn ? model.watermarkSpec() : nil
                model.confirmEdit(source: source, spec: final)
            } label: {
                if model.editSubmitting {
                    ProgressView().controlSize(.small)
                } else {
                    Text(L.s.editor.upload)
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(model.editSubmitting)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - 预览

    private func refreshPreview() async {
        // 代数守卫:连点旋转时两次渲染在 await 点交错,旧结果后到会把
        // preview 钉在错误朝向上。只认最新一代;旧代不清 rendering——
        // 最新一代还在渲染,由它收尾。
        previewGen += 1
        let gen = previewGen
        rendering = true
        var s = spec
        s.crop = nil
        s.watermark = nil
        let src = source
        // 底图与调色分两步:底图(解码+变换+增强+抠图)只在这几项真的变了才
        // 重算,滑块只付得起的那一半钱。键由 Kit 定义,漏比一个字段的表现是
        // "关掉抠图预览没变",在界面上几乎复现不了。
        let key = ImageEdit.PreviewBaseKey(source: src, spec: s)
        var base = key == previewBaseKey ? previewBase : nil
        if base == nil {
            let made = await Task.detached { ImageEdit.prepareBase(source: src, spec: s) }.value
            guard gen == previewGen else { return }
            previewBase = made
            previewBaseKey = made == nil ? nil : key
            base = made
        }
        var img: CGImage?
        if let base {
            img = await Task.detached { ImageEdit.applyAdjustments(base, spec: s) }.value
        }
        guard gen == previewGen else { return }
        preview = img
        pendingStroke = []
        rendering = false
    }
}
