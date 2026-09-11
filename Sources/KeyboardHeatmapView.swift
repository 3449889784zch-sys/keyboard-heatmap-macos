import SwiftUI

// MARK: - 键盘热力图
//
// 按 KeyboardLayout 逐行渲染。每个键是一个圆角矩形，底色 = 按该键次数映射的热力色，
// 键面显示「标签 + 次数」。方向键的 ↑/↓ 在同一格里上下堆叠（MacBook 倒 T）。

struct KeyboardHeatmapView: View {
    let counts: [Int: Int]
    let maxCount: Int

    // 与 KeyCapView 内部保持一致的排版常量
    private let keyHeightU = 0.92      // 标准键高 = 0.92 * unit
    private let gapU = 0.12            // 行间距 = 0.12 * unit

    private var boardAspect: Double {
        let vSum = KeyboardLayout.rows.reduce(0) { $0 + $1.heightFactor }
        let h = keyHeightU * vSum + gapU * Double(KeyboardLayout.rows.count - 1)
        return KeyboardLayout.totalUnits / h
    }

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.width / KeyboardLayout.totalUnits
            VStack(spacing: unit * gapU) {
                ForEach(KeyboardLayout.rows) { row in
                    HStack(spacing: 0) {
                        ForEach(row.keys) { key in
                            KeyCapView(key: key, unit: unit, counts: counts, maxCount: maxCount)
                                .frame(width: key.width * unit,
                                       height: unit * keyHeightU * row.heightFactor)
                        }
                    }
                }
            }
        }
        .aspectRatio(boardAspect, contentMode: .fit)
    }
}

// MARK: - 单个键帽

private struct KeyCapView: View {
    let key: KeyCap
    let unit: CGFloat
    let counts: [Int: Int]
    let maxCount: Int

    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }
    private var inset: CGFloat { unit * 0.06 }

    var body: some View {
        Group {
            if key.kind == .arrowUpDown {
                arrowUpDownCell
            } else {
                singleCell
            }
        }
        .padding(inset)
    }

    // 普通单键
    private var singleCell: some View {
        let count = key.keyCode.flatMap { counts[$0] } ?? 0
        let counts0 = key.keyCode == nil        // 不计数的装饰键（如 Touch ID）
        return cell(label: key.label, count: count, tracked: !counts0)
    }

    // ↑/↓ 上下堆叠
    private var arrowUpDownCell: some View {
        let up = key.keyCode.flatMap { counts[$0] } ?? 0
        let down = key.downKeyCode.flatMap { counts[$0] } ?? 0
        return VStack(spacing: unit * 0.04) {
            miniCell(label: "↑", count: up)
            miniCell(label: "↓", count: down)
        }
    }

    // 完整键帽（标签 + 次数）
    private func cell(label: String, count: Int, tracked: Bool) -> some View {
        let radius = unit * 0.16
        let bg = tracked ? HeatColor.keyColor(count: count, maxCount: maxCount, dark: dark)
                         : HeatColor.base(dark: dark).opacity(0.5)
        let fg = HeatColor.textColor(count: count, maxCount: maxCount, dark: dark)
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(bg)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(dark ? 0.16 : 0.08), lineWidth: 0.5)
            )
            .overlay(keyFace(label: label, count: count, fg: fg, tracked: tracked))
            .help(tracked ? "\(label)：\(count) 次" : "\(label)（不统计）")
    }

    private func keyFace(label: String, count: Int, fg: Color, tracked: Bool) -> some View {
        VStack(spacing: unit * 0.02) {
            Text(label)
                .font(.system(size: max(8, unit * labelScale(label)), weight: .semibold))
                .foregroundStyle(tracked ? fg : fg.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if tracked && count > 0 {
                Text(shortNumber(count))
                    .font(.system(size: max(7, unit * 0.19), weight: .medium))
                    .foregroundStyle(fg.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .padding(.horizontal, 2)
    }

    // 迷你半格（方向键 ↑/↓）
    private func miniCell(label: String, count: Int) -> some View {
        let radius = unit * 0.12
        let bg = HeatColor.keyColor(count: count, maxCount: maxCount, dark: dark)
        let fg = HeatColor.textColor(count: count, maxCount: maxCount, dark: dark)
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(bg)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(dark ? 0.16 : 0.08), lineWidth: 0.5)
            )
            .overlay(
                Text(count > 0 ? "\(label) \(shortNumber(count))" : label)
                    .font(.system(size: max(6, unit * 0.16), weight: .medium))
                    .foregroundStyle(fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            )
            .help("\(label)：\(count) 次")
    }

    // 长标签（esc/space/return…）字号小一点
    private func labelScale(_ label: String) -> CGFloat {
        label.count >= 4 ? 0.18 : (label.count >= 2 ? 0.22 : 0.30)
    }

    // 大数字缩写：1234 → 1.2k
    private func shortNumber(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 10_000...:    return String(format: "%.0fk", Double(n) / 1_000)
        case 1_000...:     return String(format: "%.1fk", Double(n) / 1_000)
        default:           return "\(n)"
        }
    }
}

// MARK: - 色阶图例

struct HeatLegend: View {
    let maxCount: Int
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        HStack(spacing: 8) {
            Text("少").font(.caption2).foregroundStyle(.secondary)
            LinearGradient(
                colors: stride(from: 0.0, through: 1.0, by: 0.1).map { HeatColor.color(for: $0, dark: dark) },
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 160, height: 10)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            Text("多").font(.caption2).foregroundStyle(.secondary)
            if maxCount > 0 {
                Text("· 峰值 \(maxCount) 次")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
