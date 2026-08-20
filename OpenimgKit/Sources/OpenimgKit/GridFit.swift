import CoreGraphics
import Foundation

/// Works out the tile size that lays `count` items out to fill a given area.
///
/// 「铺满」是两个方向都铺满:格子是一个统一的非正方形,由列数反解出来。只按
/// 正方形算的话,先用完的那一轴会锁死尺寸,另一轴多出来的整片空着——窗口越宽,
/// 底下那片空白越大。
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

        // 挑「最接近正方」的那个列数,而不是「格子最大」的那个。
        //
        // 两者的区别就是底下那片空白:老做法取 min(宽,高) 当边长做成正方形,于
        // 是先用完的那一轴锁死尺寸,另一轴多出来的全空着。窗口越宽越明显——
        // 1900×1110 放 50 张时,10 列 × 179pt 只占 943,底下整整空出 167pt。
        //
        // 现在两轴都铺满,格子成为一个统一的非正方形。**所有格子形状一致**,所
        // 以它仍然扫得出是一面网格;放弃的只是"每一格恰好是正方"这一点,换来
        // 的是不再有那片空白。
        var best: (c: Int, r: Int, w: Double, h: Double, score: Double, aspect: Double)?

        for c in 1...count {
            let r = Int(ceil(Double(count) / Double(c)))
            let cw = (w - spacing * Double(c - 1)) / Double(c)
            let ch = (h - spacing * Double(r - 1)) / Double(r)
            guard cw >= minCell, ch >= minCell else { continue }

            let aspect = max(cw / ch, ch / cw)
            // 末行空格数也要计入。只看形状的话会挑出「8 列 4 行放 25 张」这种
            // ——格子确实接近正方,但最后一行只有 1 张、右边空着 7 格,那同样是
            // 一片空白,只是从下面挪到了右下角。
            let slots = c * r
            let emptyRatio = Double(slots - count) / Double(slots)
            let score = aspect * (1 + 0.5 * emptyRatio)
            if best == nil || score < best!.score {
                best = (c, r, cw, ch, score, aspect)
            }
        }

        guard let b = best else {
            // 一个都放不下。按 minCell 铺满宽度,剩下的让它往下滚。
            let c = max(1, Int((w + spacing) / (minCell + spacing)))
            let cw = max(minCell, (w - spacing * Double(c - 1)) / Double(c))
            return GridFit(columns: c, rows: Int(ceil(Double(count) / Double(c))),
                           cellWidth: cw, cellHeight: cw, scrolls: true)
        }

        // 形状实在太扁就退回正方,宁可空一片也不要把图裁成条。
        //
        // 阈值 1.8:到这个比例,一张竖构图的照片会被切掉一半以上。铺满是为了好
        // 看,把图裁毁了就本末倒置了。
        guard b.aspect <= 1.8 else {
            let side = floor(min(b.w, b.h))
            return GridFit(columns: b.c, rows: b.r,
                           cellWidth: side, cellHeight: side, scrolls: false)
        }

        // 向下取整到整点:`.fixed` 列宽加起来只要比提议宽度多一丝,LazyVGrid 就
        // 会砍掉一列,整套计算前功尽弃。高度同理取整,代价是底部最多差几点,
        // 那是看不出来的。
        return GridFit(columns: b.c, rows: b.r,
                       cellWidth: floor(b.w), cellHeight: floor(b.h), scrolls: false)
    }
}
