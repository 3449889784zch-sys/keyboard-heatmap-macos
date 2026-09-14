import SwiftUI

// MARK: - 菜单栏弹出面板（.window 样式）

struct MenuBarView: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "keyboard").foregroundStyle(.tint)
                Text("键盘热力图").font(.headline)
                Spacer()
                if !state.permissionGranted {
                    Text("未授权").font(.caption).foregroundStyle(.orange)
                } else if state.isPaused {
                    Text("已暂停").font(.caption).foregroundStyle(.orange)
                }
            }

            if state.permissionGranted {
                VStack(alignment: .leading, spacing: 2) {
                    Text("总敲击").font(.caption).foregroundStyle(.secondary)
                    Text("\(state.total)")
                        .font(.system(size: 26, weight: .bold))
                        .contentTransition(.numericText())
                        .animation(.default, value: state.total)
                }

                let top = state.topKeys(5)
                if !top.isEmpty {
                    Divider()
                    Text("最常用").font(.caption).foregroundStyle(.secondary)
                    ForEach(top) { key in
                        HStack {
                            Text(key.name)
                                .font(.system(.callout, design: .rounded).weight(.semibold))
                            Spacer()
                            Text("\(key.count)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("尚未获得「输入监控」权限。打开主窗口按提示授权即可。")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            if state.permissionGranted {
                Button {
                    state.isPaused.toggle()
                } label: {
                    Label(state.isPaused ? "继续统计" : "暂停统计",
                          systemImage: state.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.plain)
            }

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("打开主窗口", systemImage: "macwindow")
            }
            .buttonStyle(.plain)

            Toggle("开机时自动启动", isOn: Binding(
                get: { state.launchAtLoginEnabled },
                set: { state.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.checkbox)

            Button {
                state.toggleDockVisibility()
            } label: {
                Label(NSApp.activationPolicy() == .regular ? "隐藏 Dock 图标" : "显示在 Dock",
                      systemImage: NSApp.activationPolicy() == .regular ? "menubar.dock.rectangle" : "dock.rectangle")
            }
            .buttonStyle(.plain)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 240)
    }
}
