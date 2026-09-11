import Foundation

// MARK: - 键位定义
//
// 说明：这里用的是 macOS/Carbon 的「硬件虚拟键码」(kVK_*)。这些码只跟物理按键
// 位置相关，与当前输入法/键盘布局无关 —— 所以我们统计的是「物理键被按了几次」，
// 而不是「输入了什么字符」。这也是本 app 的隐私底线：只数按键，不记录内容与顺序。

/// 一个键帽的静态描述（画在热力图上用）。
struct KeyCap: Identifiable {
    enum Kind {
        case normal        // 普通单键
        case arrowUpDown   // 特殊：上/下方向键在同一个 1u 槽里上下堆叠（MacBook 倒 T 布局）
    }

    let id: Int            // 唯一 id（用 keyCode；不计数的装饰键用负数）
    let kind: Kind
    let keyCode: Int?      // 参与统计的键码；nil 表示不计数（如 Touch ID/电源键）
    let downKeyCode: Int?  // 仅 arrowUpDown 用：下方向键的键码
    let label: String      // 主标签
    let width: Double      // 宽度单位（1.0 = 标准键宽）
    let isModifier: Bool   // 是否修饰键（⌘⌥⌃⇧⇪fn，走 flagsChanged 统计）

    init(_ label: String,
         keyCode: Int?,
         width: Double = 1.0,
         isModifier: Bool = false,
         kind: Kind = .normal,
         downKeyCode: Int? = nil,
         id: Int? = nil) {
        self.label = label
        self.keyCode = keyCode
        self.width = width
        self.isModifier = isModifier
        self.kind = kind
        self.downKeyCode = downKeyCode
        self.id = id ?? keyCode ?? -abs(label.hashValue % 100000) - 1
    }
}

/// 一行键 + 该行相对高度（功能行做矮一点，更像 MacBook）。
struct KeyRow: Identifiable {
    let id = UUID()
    let heightFactor: Double
    let keys: [KeyCap]
}

enum KeyboardLayout {
    /// 每行的总宽度单位（标准主键区为 15u）。
    static let totalUnits: Double = 15.0

    static let rows: [KeyRow] = [
        // 功能行（矮）：esc F1–F12 + Touch ID(不计数)
        KeyRow(heightFactor: 0.62, keys: [
            KeyCap("esc", keyCode: 53, width: 1.5),
            KeyCap("F1", keyCode: 122), KeyCap("F2", keyCode: 120),
            KeyCap("F3", keyCode: 99),  KeyCap("F4", keyCode: 118),
            KeyCap("F5", keyCode: 96),  KeyCap("F6", keyCode: 97),
            KeyCap("F7", keyCode: 98),  KeyCap("F8", keyCode: 100),
            KeyCap("F9", keyCode: 101), KeyCap("F10", keyCode: 109),
            KeyCap("F11", keyCode: 103), KeyCap("F12", keyCode: 111),
            KeyCap("⏻", keyCode: nil, width: 1.5, id: -900),   // Touch ID/电源：系统不通过普通事件派发，不计数
        ]),
        // 数字行
        KeyRow(heightFactor: 1.0, keys: [
            KeyCap("`", keyCode: 50), KeyCap("1", keyCode: 18), KeyCap("2", keyCode: 19),
            KeyCap("3", keyCode: 20), KeyCap("4", keyCode: 21), KeyCap("5", keyCode: 23),
            KeyCap("6", keyCode: 22), KeyCap("7", keyCode: 26), KeyCap("8", keyCode: 28),
            KeyCap("9", keyCode: 25), KeyCap("0", keyCode: 29), KeyCap("-", keyCode: 27),
            KeyCap("=", keyCode: 24), KeyCap("⌫", keyCode: 51, width: 2.0),
        ]),
        // Tab 行
        KeyRow(heightFactor: 1.0, keys: [
            KeyCap("⇥", keyCode: 48, width: 1.5),
            KeyCap("Q", keyCode: 12), KeyCap("W", keyCode: 13), KeyCap("E", keyCode: 14),
            KeyCap("R", keyCode: 15), KeyCap("T", keyCode: 17), KeyCap("Y", keyCode: 16),
            KeyCap("U", keyCode: 32), KeyCap("I", keyCode: 34), KeyCap("O", keyCode: 31),
            KeyCap("P", keyCode: 35), KeyCap("[", keyCode: 33), KeyCap("]", keyCode: 30),
            KeyCap("\\", keyCode: 42, width: 1.5),
        ]),
        // Caps 行
        KeyRow(heightFactor: 1.0, keys: [
            KeyCap("⇪", keyCode: 57, width: 1.75, isModifier: true),
            KeyCap("A", keyCode: 0), KeyCap("S", keyCode: 1), KeyCap("D", keyCode: 2),
            KeyCap("F", keyCode: 3), KeyCap("G", keyCode: 5), KeyCap("H", keyCode: 4),
            KeyCap("J", keyCode: 38), KeyCap("K", keyCode: 40), KeyCap("L", keyCode: 37),
            KeyCap(";", keyCode: 41), KeyCap("'", keyCode: 39),
            KeyCap("return", keyCode: 36, width: 2.25),
        ]),
        // Shift 行
        KeyRow(heightFactor: 1.0, keys: [
            KeyCap("⇧", keyCode: 56, width: 2.25, isModifier: true),
            KeyCap("Z", keyCode: 6), KeyCap("X", keyCode: 7), KeyCap("C", keyCode: 8),
            KeyCap("V", keyCode: 9), KeyCap("B", keyCode: 11), KeyCap("N", keyCode: 45),
            KeyCap("M", keyCode: 46), KeyCap(",", keyCode: 43), KeyCap(".", keyCode: 47),
            KeyCap("/", keyCode: 44),
            KeyCap("⇧", keyCode: 60, width: 2.75, isModifier: true, id: 60),
        ]),
        // 底部行：fn ⌃ ⌥ ⌘ space ⌘ ⌥ + 方向键（倒 T）
        KeyRow(heightFactor: 1.0, keys: [
            KeyCap("fn", keyCode: 63, isModifier: true),
            KeyCap("⌃", keyCode: 59, isModifier: true),
            KeyCap("⌥", keyCode: 58, isModifier: true),
            KeyCap("⌘", keyCode: 55, width: 1.25, isModifier: true),
            KeyCap("space", keyCode: 49, width: 5.5),
            KeyCap("⌘", keyCode: 54, width: 1.25, isModifier: true, id: 54),
            KeyCap("⌥", keyCode: 61, isModifier: true, id: 61),
            KeyCap("←", keyCode: 123),
            KeyCap("↑", keyCode: 126, kind: .arrowUpDown, downKeyCode: 125, id: 126),
            KeyCap("→", keyCode: 124),
        ]),
    ]

    /// keyCode → 在统计列表里显示的可读名字（覆盖布局上所有可计数键 + 少量布局外键）。
    static let displayNames: [Int: String] = {
        var m: [Int: String] = [:]
        for row in rows {
            for k in row.keys {
                if let c = k.keyCode { m[c] = k.label }
                if k.kind == .arrowUpDown, let d = k.downKeyCode { m[d] = "↓" }
            }
        }
        // 布局上没画、但可能被按到的键，补充可读名。
        m[62] = "⌃(右)"      // 右 Control（外接键盘）
        m[117] = "⌦"         // Forward Delete
        m[115] = "Home"; m[119] = "End"; m[116] = "PgUp"; m[121] = "PgDn"
        m[71] = "Clear"; m[76] = "⌤"; m[105] = "F13"; m[107] = "F14"; m[113] = "F15"
        return m
    }()

    /// 给定键码返回可读名（找不到就用「#键码」）。
    static func name(for keyCode: Int) -> String {
        displayNames[keyCode] ?? "#\(keyCode)"
    }
}

/// 会通过 flagsChanged 上报的修饰键键码集合（用于区分普通键 keyDown）。
enum ModifierKeys {
    static let all: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
}
