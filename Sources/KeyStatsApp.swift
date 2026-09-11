import SwiftUI

// MARK: - 应用入口
//
// 同时提供：一个主窗口（WindowGroup）+ 一个菜单栏图标（MenuBarExtra）。
// 用 -parse-as-library 编译，因此这里可以安全使用 @main。

@main
struct KeyStatsApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(state: state)
        }
        .defaultSize(width: 1040, height: 520)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            Image(systemName: "keyboard")
        }
        .menuBarExtraStyle(.window)
    }
}
