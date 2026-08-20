import Foundation

/// 用量方块图:把"占了多少"铺成一格一格,而不是一根横条。
///
/// 横条只能读出比例,读不出量级——同样是半满,10 GB 的一半和 100 MB 的一半在条
/// 上长得一模一样。方块图印着"每格多少",于是比例和量级能同时读出来。
///
/// 这里只算"填几格、每格多大",不碰任何绘制。这么切是因为它有三处一错就会骗人
/// 的地方,而那三处全都是纯算术、测得到:
///
///   1. **非零必须至少亮一格。** 871 MB 占 10 GB 的 8.5%,四舍五入到 100 格是
///      8 格没问题;但 3 MB 占 0.03%,round 完是 0 格——界面上"有 3 MB"和"一个
///      字节都没有"长得完全一样。
///   2. **超额要能看出来。** 填满 100 格既可能是刚好用完、也可能是超了,这两件
///      事用户要做的处置不同。
///   3. **没有上限时格子代表什么。** 自有桶没有配额,硬凑一个分母出来会让格子
///      变成"永远七成满"的装饰品。改成每格固定大小、按量点亮,格子表达的是量
///      不是比例,再把单位印出来。
public struct UsageGrid: Sendable, Equatable {
    public let columns: Int
    public let rows: Int
    /// 点亮的格数。
    public let filled: Int
    /// 一格代表多少字节。界面上要把它印出来,否则方块图什么也没说。
    public let unit: Int64
    /// 用量超过了上限。只有在有上限时才可能为真。
    public let overflowed: Bool
    /// 这张图有没有分母。没有分母时格子读作"量",有分母时读作"比例"。
    public let hasCeiling: Bool

    public var cells: Int { columns * rows }

    /// 每格的候选大小。**1024 进制**,与界面上格式化字节的口径一致
    /// (`AppModel.bytes` 用的是 `ByteCountFormatter.countStyle = .binary`)。
    ///
    /// 两边进制必须一样。用 1000 进制挑单位、再用 1024 进制显示的话,印出来的
    /// 不是"每格 ≈ 10 MB"而是"每格 ≈ 9.5 MB"——数字本身没错,但一个刻意挑成
    /// 整数的单位显示成小数,读者只会觉得这里算错了。
    static let ladder: [Int64] = {
        let mb: Int64 = 1 << 20, gb: Int64 = 1 << 30, tb: Int64 = 1 << 40
        return [mb, 5*mb, 10*mb, 25*mb, 50*mb, 100*mb, 250*mb, 500*mb,
                gb, 2*gb, 5*gb, 10*gb, 25*gb, 50*gb, 100*gb, 250*gb, 500*gb,
                tb, 2*tb, 5*tb, 10*tb, 50*tb]
    }()

    public static func of(bytes: Int64, capacity: Int64?,
                          columns: Int = 20, rows: Int = 5) -> UsageGrid {
        let cols = max(1, columns), rws = max(1, rows)
        let cells = cols * rws
        let used = max(0, bytes)

        if let cap = capacity, cap > 0 {
            // 有上限:格子是比例。分母固定,单位由分母算出来。
            let unit = max(1, cap / Int64(cells))
            let share = Double(used) / Double(cap)
            var lit = Int((share * Double(cells)).rounded())
            if used > 0 { lit = max(1, lit) }   // 见上面第 1 条
            lit = min(cells, lit)
            return UsageGrid(columns: cols, rows: rws, filled: lit, unit: unit,
                             overflowed: used > cap, hasCeiling: true)
        }

        // 没上限:格子是量。挑最小的、能把当前用量装得下的单位。
        let unit = ladder.first { ceilDiv(used, $0) <= Int64(cells) } ?? ladder[ladder.count - 1]
        var lit = Int(min(Int64(cells), ceilDiv(used, unit)))
        if used > 0 { lit = max(1, lit) }
        return UsageGrid(columns: cols, rows: rws, filled: lit, unit: unit,
                         overflowed: false, hasCeiling: false)
    }

    /// 格子之间的缝。
    public static let gap: Double = 3

    /// 一格的边长。**正方形**——按内容宽度反算,而不是写死高度。
    ///
    /// 写死高度会在卡片变宽时把格子拉成横条:列宽上限是 560,减去卡片内边距
    /// 之后一格能有 23pt 宽,配 12pt 的死高度就是 2:1 的扁块。那看着不像"格
    /// 子",像一排短横线,而方块图的全部意义就在于它是方的。
    public static func cellSide(contentWidth: Double, columns: Int, gap: Double = gap) -> Double {
        let n = max(1, columns)
        return max(2, (contentWidth - gap * Double(n - 1)) / Double(n))
    }

    /// 整张图的高度。由边长决定,所以宽度一变高度就跟着变。
    public func height(contentWidth: Double, gap: Double = gap) -> Double {
        let side = Self.cellSide(contentWidth: contentWidth, columns: columns, gap: gap)
        return side * Double(rows) + gap * Double(rows - 1)
    }

    /// 阶梯里每一档都必须是 2 的整数次幂的整数倍——它是"印出来好看"这件事的
    /// 全部依据,而那正是最容易在后来加一档时被破坏的性质。
    public static var ladderIsBinary: Bool {
        ladder.allSatisfy { $0 % (1 << 20) == 0 }
    }

    private static func ceilDiv(_ a: Int64, _ b: Int64) -> Int64 {
        guard b > 0 else { return 0 }
        return (a + b - 1) / b
    }
}
