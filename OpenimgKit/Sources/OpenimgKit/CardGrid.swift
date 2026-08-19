import Foundation

/// 概览页与设置页那种「一排卡片」的布局求解。
///
/// 两页原来都是写死的:`HStack` 套两个 `VStack`,卡片按数量手分成 3 张 / 4 张,
/// 没有断点。后果有两个——窗口拉宽之后左右各空一大片(16 吋满屏两侧各 236pt),
/// 以及两列高度对不上,概览页左下曾经空出整整 523pt。
///
/// 这里把「几列、每列多宽」变成一个可断言的纯函数,和 `GridFit` 同一个用意:
/// 几何算在 Kit 里,`KitCheck` 才盯得住。
public struct BoardFit: Equatable, Sendable {
    public let columns: Int
    public let columnWidth: Double
    /// 列宽封顶之后剩下的宽度不该被拉伸吃掉,内容整体居中,用这个值定宽。
    public let contentWidth: Double

    public static let gap: Double = 16

    /// 列数下限恒为 2。
    ///
    /// 不是随手定的:窗口下限 900 对应可用宽 624,在这里掉到单列 624pt,
    /// 恰好制造出用户抱怨的那种空地,而今天同一个窗口是 2 列 × 304、满宽。
    ///
    /// 锁死下限还顺带消掉一个隐患:开了「始终显示滚动条」的机器上 NSScrollView
    /// 会吃掉约 15pt,断点若落在 620 附近,同一个窗口尺寸在两台 Mac 上会排出
    /// 不同的列数。
    public static let minColumns = 2
    public static let maxColumns = 3

    /// 只用于 2→3 的门槛,不参与 2 列的判定(2 列是地板,没有判定)。
    ///
    /// 400 是格式分布卡在 3 列下还活得下去的下限:卡内容宽 400−32=368,
    /// 减去左侧格式名约 40,绘图区 328,而尾注要占掉其中约两成。
    public static let minColumn: Double = 400
    /// 再宽也不该更宽。一张卡里的「标签………值」被拉成横跨半屏的虚线,
    /// 眼睛从左边走到右边会接不上。
    public static let maxColumn: Double = 560

    public static func solve(width: Double, cap: Int = maxColumns) -> BoardFit {
        guard width.isFinite, width > 1 else {
            return BoardFit(columns: minColumns, columnWidth: 1, contentWidth: 1)
        }
        let top = max(minColumns, min(cap, maxColumns))
        var n = minColumns
        // 只在「再加一列之后每列仍不窄于 minColumn」时才加。
        while n < top, (width - gap * Double(n)) / Double(n + 1) >= minColumn { n += 1 }
        let col = min(maxColumn, (width - gap * Double(n - 1)) / Double(n))
        let w = max(1, col)
        return BoardFit(columns: n, columnWidth: w,
                        contentWidth: w * Double(n) + gap * Double(n - 1))
    }
}

/// 一张卡在装箱里的声明:身份,以及各档列数下想占几格。
///
/// 跨度做成查表而不是闭包:闭包既不能 `Equatable`、也没法在 `KitCheck` 里
/// 断言。而「宽到一定程度才分栏」本来就是断点行为,查表正是它的形状。
public struct BoardCard<ID: Hashable & Sendable>: Sendable, Equatable {
    public let id: ID
    public let spans: [Int: Int]

    public init(_ id: ID, spans: [Int: Int] = [:]) {
        self.id = id
        self.spans = spans
    }

    /// 想要的跨度,夹在 1…columns 之间。没声明就是 1。
    public func ideal(_ columns: Int) -> Int {
        max(1, min(max(1, columns), spans[columns] ?? 1))
    }
}

/// 行里的一格。
///
/// 用 struct 而不是元组:元组不 conform `Identifiable`/`Equatable`,既写不出
/// `ForEach(row)`,也写不出 `==` 断言。
public struct BoardCell<ID: Hashable & Sendable>: Identifiable, Equatable, Sendable {
    public let id: ID
    public let span: Int

    public init(id: ID, span: Int) {
        self.id = id
        self.span = span
    }
}

public enum CardGrid {
    /// 把一条卡片序列切成若干行。
    ///
    /// 为什么是「一维序列 + 跨度」而不是瀑布流:瀑布流没有「行」这个概念,
    /// 一张想占两列的卡插进第 1 列会把第 2 列的堆栈基线撕开。所有做过跨列的
    /// 瀑布流最后都退化成「跨列的卡单独占一行」,也就是偷偷变回了网格。
    ///
    /// 这么做换来三个瀑布流给不了的性质:
    ///
    /// - 视觉顺序 == 声明顺序 == VoiceOver 朗读顺序 == Tab 焦点顺序,
    ///   在 1/2/3 列下都守恒。原来的双列已经有「焦点从左上跳右上再跳回左中」
    ///   的毛病,只是没人用键盘走过一遍。
    /// - 卡片条件隐藏(AI 关掉、图库空、统计还没回来)只是从序列里少一项,
    ///   行重新切分,版面不留洞。
    /// - 纯函数,测得到。
    ///
    /// 三条规则,没有第四条:
    ///
    /// 1. 跨度 = min(想要的, 本行剩余),装不下就降级,绝不打乱顺序;
    /// 2. 剩余为 0 就开新行;
    /// 3. 行尾还有余量时(下一张塞不下,或卡片用完了)并给本行最后一张——
    ///    这一条把「永不出洞」变成了可以断言的不变量。
    public static func rows<ID>(_ cards: [BoardCard<ID>], columns: Int) -> [[BoardCell<ID>]] {
        let n = max(1, columns)
        var out: [[BoardCell<ID>]] = []
        var row: [BoardCell<ID>] = []
        var left = n

        for card in cards {
            let want = card.ideal(n)
            if want > left {
                out.append(pad(row, n))
                row = []
                left = n
            }
            let span = min(want, left)
            row.append(BoardCell(id: card.id, span: span))
            left -= span
            if left == 0 {
                out.append(row)
                row = []
                left = n
            }
        }
        if !row.isEmpty { out.append(pad(row, n)) }
        return out
    }

    private static func pad<ID>(_ row: [BoardCell<ID>], _ n: Int) -> [BoardCell<ID>] {
        guard let last = row.last else { return row }
        let used = row.reduce(0) { $0 + $1.span }
        guard used < n else { return row }
        return row.dropLast() + [BoardCell(id: last.id, span: last.span + (n - used))]
    }
}
