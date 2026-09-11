import SwiftUI

// MARK: - 主窗口

struct ContentView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Group {
            if state.permissionGranted {
                mainUI
            } else {
                PermissionGate(state: state)
            }
        }
        .frame(minWidth: 820, minHeight: 460)
        .alert("是否保留在 Dock 栏？", isPresented: $state.showDockChoice) {
            Button("仅显示在菜单栏") { state.setDockVisible(false) }
            Button("保留在 Dock") { state.setDockVisible(true) }
        } message: {
            Text("选择应用运行时的显示方式。之后可以在菜单栏图标的菜单中修改。")
        }
    }

    private var mainUI: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if state.needsRestart { restartBanner }
                KeyboardHeatmapView(counts: state.counts, maxCount: state.maxCount)
                    .frame(maxWidth: .infinity)
                HStack {
                    HeatLegend(maxCount: state.maxCount)
                    Spacer()
                    if state.isPaused {
                        Label("已暂停", systemImage: "pause.circle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .padding(20)

            Divider()

            StatsPanelView(state: state)
                .frame(width: 280)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("键盘热力图").font(.title2.bold())
                Text("只统计每个键的敲击次数 · 不记录输入内容")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()

            Button {
                state.isPaused.toggle()
            } label: {
                Label(state.isPaused ? "继续" : "暂停",
                      systemImage: state.isPaused ? "play.fill" : "pause.fill")
            }

            Button(role: .destructive) {
                state.confirmingReset = true
            } label: {
                Label("重置", systemImage: "arrow.counterclockwise")
            }
            .confirmationDialog("确定要清空所有统计数据吗？此操作无法撤销。",
                                isPresented: $state.confirmingReset, titleVisibility: .visible) {
                Button("清空数据", role: .destructive) { state.reset() }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private var restartBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("已获授权，但监听尚未生效 —— 请退出后重新打开本 app。")
                .font(.callout)
            Spacer()
            Button("退出") { NSApp.terminate(nil) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }
}

// MARK: - 未授权引导页

struct PermissionGate: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("需要「输入监控」权限")
                .font(.title.bold())

            VStack(spacing: 6) {
                Text("要统计键盘敲击次数，macOS 需要你授予本 app「输入监控」权限。")
                Text("本 app 只累计每个物理键被按的次数，绝不记录你输入的文字、顺序或所在应用。")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 460)

            VStack(alignment: .leading, spacing: 10) {
                stepRow(1, "点击下方「申请授权」，在弹窗中允许；或直接打开系统设置。")
                stepRow(2, "在「系统设置 › 隐私与安全性 › 输入监控」里勾选「键盘热力图」。")
                stepRow(3, "若授权后仍未开始统计，请退出并重新打开本 app。")
            }
            .frame(maxWidth: 460, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))

            HStack(spacing: 12) {
                Button {
                    state.requestPermission()
                } label: {
                    Text("申请授权").frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)

                Button("打开系统设置") { state.openInputMonitoringSettings() }
                Button("我已授权，重新检测") { state.recheckPermissionNow() }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stepRow(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            Text(text).font(.callout)
            Spacer(minLength: 0)
        }
    }
}
