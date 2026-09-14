import SwiftUI

// MARK: - 统计面板（主窗口右侧）

struct StatsPanelView: View {
    @ObservedObject var state: AppState

    private var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f.string(from: state.countingSince)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 总敲击数（Hero 数字）
            VStack(alignment: .leading, spacing: 2) {
                Text("总敲击次数")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("\(state.total)")
                    .font(.system(size: 40, weight: .bold))
                    .contentTransition(.numericText())
                    .animation(.default, value: state.total)
                Text("自 \(dateText) 起")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("运行设置")
                    .font(.subheadline).foregroundStyle(.secondary)
                Toggle("开机时自动启动", isOn: Binding(
                    get: { state.launchAtLoginEnabled },
                    set: { state.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch)
                .font(.callout)
                Text("也可在系统设置 › 通用 › 登录项中管理。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            // Top 键排行
            VStack(alignment: .leading, spacing: 8) {
                Text("最常敲的键")
                    .font(.subheadline).foregroundStyle(.secondary)

                let top = state.topKeys(10)
                if top.isEmpty {
                    Text("还没有记录。开始打字试试吧 ⌨️")
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    let maxV = top.first?.count ?? 1
                    ForEach(Array(top.enumerated()), id: \.element.id) { idx, key in
                        RankRow(rank: idx + 1, name: key.name, count: key.count, fraction: Double(key.count) / Double(maxV))
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 240)
        .alert("无法设置开机自启动", isPresented: Binding(
            get: { state.launchAtLoginError != nil },
            set: { if !$0 { state.launchAtLoginError = nil } }
        )) {
            Button("好", role: .cancel) { state.launchAtLoginError = nil }
        } message: {
            Text(state.launchAtLoginError ?? "")
        }
    }
}

// MARK: - 排行单行（名称 + 迷你条 + 次数）

private struct RankRow: View {
    let rank: Int
    let name: String
    let count: Int
    let fraction: Double

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)

            Text(name)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .frame(width: 46, alignment: .leading)
                .lineLimit(1)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(HeatColor.color(for: max(0.15, fraction), dark: scheme == .dark))
                        .frame(width: max(6, geo.size.width * fraction))
                }
            }
            .frame(height: 8)

            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}
