import SwiftUI

// MARK: - 热力配色
//
// 遵循数据可视化的「顺序色阶」规则：单一色系、由浅到深表示大小，不用彩虹。
// 这里选用暖色系（浅奶油 → 橙 → 深红），贴合「热力图/越热越红」的直觉；
// 明、暗模式各一套（暗色下低值贴近深色背景、高值发亮，符合暗色热图惯例）。
// 每个键的文字颜色按其背景亮度自动取深/浅，保证计数始终清晰可读。

enum HeatColor {

    /// 亮色模式色标锚点（t: 0→1）。
    private static let lightStops: [(t: Double, r: Double, g: Double, b: Double)] = [
        (0.00, 0xFF/255, 0xEC/255, 0xD6/255),  // 极浅暖
        (0.28, 0xFF/255, 0xC5/255, 0x8A/255),  // 浅橙
        (0.55, 0xFF/255, 0x8C/255, 0x42/255),  // 橙
        (0.80, 0xF0/255, 0x56/255, 0x2B/255),  // 橙红
        (1.00, 0xC4/255, 0x21/255, 0x1B/255),  // 深红
    ]

    /// 暗色模式色标锚点（低值贴近深背景、高值发亮）。
    private static let darkStops: [(t: Double, r: Double, g: Double, b: Double)] = [
        (0.00, 0x3A/255, 0x2A/255, 0x1E/255),  // 深暖棕（略高于暗背景）
        (0.28, 0x7A/255, 0x3D/255, 0x1E/255),
        (0.55, 0xC2/255, 0x5A/255, 0x22/255),
        (0.80, 0xE8/255, 0x79/255, 0x2E/255),
        (1.00, 0xFF/255, 0xB4/255, 0x54/255),  // 亮暖橙
    ]

    /// 未被按过（count == 0）的键的中性底色。
    static func base(dark: Bool) -> Color {
        dark ? Color(red: 0x25/255, green: 0x25/255, blue: 0x23/255)
             : Color(red: 0xEF/255, green: 0xEE/255, blue: 0xEA/255)
    }

    /// 计数 → 归一化强度 t∈[0,1]。按键分布极偏（空格/E 远超其它），
    /// 用平方根压一压顶端、抬一抬中低段，让更多键显出颜色层次。
    static func intensity(count: Int, maxCount: Int) -> Double {
        guard count > 0, maxCount > 0 else { return 0 }
        let frac = Double(count) / Double(maxCount)
        return pow(min(1, max(0, frac)), 0.55)
    }

    /// 强度 t → 热力色。
    static func color(for t: Double, dark: Bool) -> Color {
        let (r, g, b) = rgb(for: t, dark: dark)
        return Color(red: r, green: g, blue: b)
    }

    /// 某个键的最终背景色（count==0 用中性底色）。
    static func keyColor(count: Int, maxCount: Int, dark: Bool) -> Color {
        guard count > 0 else { return base(dark: dark) }
        return color(for: intensity(count: count, maxCount: maxCount), dark: dark)
    }

    /// 根据键背景亮度返回合适的文字色（深底配浅字、浅底配深字）。
    static func textColor(count: Int, maxCount: Int, dark: Bool) -> Color {
        let lum: Double
        if count > 0 {
            let (r, g, b) = rgb(for: intensity(count: count, maxCount: maxCount), dark: dark)
            lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        } else {
            lum = dark ? 0.14 : 0.93
        }
        return lum > 0.58 ? Color(red: 0x0b/255, green: 0x0b/255, blue: 0x0b/255)
                          : Color.white
    }

    // MARK: 线性插值

    private static func rgb(for tIn: Double, dark: Bool) -> (Double, Double, Double) {
        let stops = dark ? darkStops : lightStops
        let t = min(1, max(0, tIn))
        var lo = stops[0], hi = stops[stops.count - 1]
        for i in 0..<(stops.count - 1) where t >= stops[i].t && t <= stops[i + 1].t {
            lo = stops[i]; hi = stops[i + 1]; break
        }
        let span = hi.t - lo.t
        let f = span > 0 ? (t - lo.t) / span : 0
        return (lo.r + (hi.r - lo.r) * f,
                lo.g + (hi.g - lo.g) * f,
                lo.b + (hi.b - lo.b) * f)
    }
}
