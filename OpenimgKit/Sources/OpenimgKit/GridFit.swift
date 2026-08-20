import CoreGraphics
import Foundation

/// Works out the tile size that lays `count` items out to fill a given area.
///
/// 格子永远是正方形,边长按「恰好装下这一页」反解到最大。装不满的余量由视图
/// 层居中消化。
///
/// The usual `GridItem(.adaptive(minimum:))` solves the opposite problem: it
/// fixes the tile and lets the row count fall where it may, so a page of 50 is
/// whatever height it happens to be and the window is either half empty or
/// scrolls. Here the page size is the thing the user chose, so the tile is the
/// free variable — pick the size that makes exactly that many fit.
///
/// Pure geometry, no SwiftUI, so `KitCheck` can assert on it.
public struct GridFit: Equatable, Sendable {
    public let columns: Int
    public let rows: Int
    public let cellWidth: Double
    public let cellHeight: Double
    /// True when the area was too small to fit `count` at a usable tile size,
    /// so the layout fell back to `minCell` and the grid has to scroll.
    public let scrolls: Bool

    /// - Parameters:
    ///   - count: how many tiles have to fit.
    ///   - size: the area available to the grid, insets already removed.
    ///   - spacing: the gap between tiles, both axes.
    ///   - minCell: the smallest tile worth drawing. Below this the grid gives
    ///     up on fitting and scrolls instead — 50 pictures at 40pt is not a
    ///     denser gallery, it is an unusable one.
    public static func solve(count: Int, in size: CGSize,
                             spacing: Double = 12, minCell: Double = 72) -> GridFit {
        let w = Double(size.width), h = Double(size.height)
        guard count > 0, w.isFinite, h.isFinite, w > 1, h > 1 else {
            return GridFit(columns: 1, rows: max(1, count),
                           cellWidth: minCell, cellHeight: minCell, scrolls: true)
        }

        // 回到正方形:挑「格子边长最大」的列数。
        //
        // 中间试过一版两轴都铺满的非正方形格子——底下确实不空了,但格子会随
        // 窗口比例变成竖条或横条,一面本该整齐的图墙看着各行形状不一。正方形
        // 是硬要求,而正方形填不满两个方向是几何事实:余量交给视图层去**居中**,
        // 上下对称的留白读作页边距,不是空洞。
        var best: (c: Int, r: Int, tile: Double)?

        for c in 1...count {
            let r = Int(ceil(Double(count) / Double(c)))
            let cw = (w - spacing * Double(c - 1)) / Double(c)
            let ch = (h - spacing * Double(r - 1)) / Double(r)
            guard cw >= minCell, ch >= minCell else { continue }
            // 边长取两轴里小的那个——最大化它,就是在最大化正方形。
            let tile = min(cw, ch)
            if best == nil || tile > best!.tile { best = (c, r, tile) }
        }

        guard let b = best else {
            // 一个都放不下。按 minCell 铺满宽度,剩下的让它往下滚。
            let c = max(1, Int((w + spacing) / (minCell + spacing)))
            let cw = max(minCell, (w - spacing * Double(c - 1)) / Double(c))
            return GridFit(columns: c, rows: Int(ceil(Double(count) / Double(c))),
                           cellWidth: cw, cellHeight: cw, scrolls: true)
        }

        // 向下取整到整点:`.fixed` 列宽加起来只要比提议宽度多一丝,LazyVGrid 就
        // 会砍掉一列,整套计算前功尽弃。
        let side = floor(best!.tile)
        return GridFit(columns: best!.c, rows: best!.r,
                       cellWidth: side, cellHeight: side, scrolls: false)
    }
}
