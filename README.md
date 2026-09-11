# 键盘热力图 · Keyboard Heatmap (KeyStats)

一个 macOS 小工具：统计键盘上**每个物理键被敲了多少次**，用**热力图**直观展示。
灵感来自 B 站上的同类作品，做成了 MacBook 布局的原生 SwiftUI 应用。

形态：**独立主窗口 + 菜单栏图标**。

## 🔒 隐私（重要）

本 app 只记录「**每个物理键的累计次数**」这一个聚合数字。

它**不会**：

- 记录你按键的**顺序**
- 记录你**输入的任何文字 / 密码 / 内容**
- 记录你当前所在的 **app 或窗口**

它统计的是硬件键码（第几个物理键），跟你打了什么字无关——是个**频次计数器，不是键盘记录器**。
数据只存在你本机：`~/Library/Application Support/com.allen.keystats/counts.json`。

## 构建

本项目**不需要完整 Xcode**，只用 Command Line Tools 即可（`xcode-select --install`）。

```bash
./build.sh
```

构建产物是同目录下的 `键盘热力图.app`。构建并直接启动：

```bash
./build.sh --run
```

> 实现说明：`build.sh` 直接调用 CommandLineTools 里的 `swiftc` 编译 `Sources/*.swift`，
> 手动组装 `.app` 包，并使用免费的稳定本机签名，避免每次重新编译都改变权限身份。
> ⚠️ 两个已踩过的坑（已在脚本里处理）：
> 1. 编译器的 **module-cache 路径必须是纯 ASCII**，否则 `swiftc` 会直接崩溃（本项目目录名是中文，
>    所以缓存放在系统临时目录里）。
> 2. macOS 新 SDK 里 `@State` 变成了需要 `SwiftUIMacros` 插件的宏，而该插件只随完整 Xcode 提供——
>    所以代码里**不使用 `@State`**，视图级开关都放在 `AppState`（`ObservableObject`）里。

## 首次使用：授予「输入监控」权限

要统计全局按键，macOS 需要「输入监控 (Input Monitoring)」权限：

1. 打开 app，在未授权引导页点「**申请授权**」，在系统弹窗里允许；
   或点「打开系统设置」，到 **系统设置 › 隐私与安全性 › 输入监控** 手动勾选「键盘热力图」。
2. 勾选后，**退出并重新打开** app 一次（授权后监听通常要重启才挂得上）。
3. 之后敲键盘，热力图与计数就会实时更新。

> ⚠️ 第一次构建时，脚本会在登录钥匙串中创建名为 `KeyStats Local Dev` 的本机签名证书。
> 请不要删除项目里的 `.build/local-signing`，否则签名身份会变化，系统可能要求重新授权。

## 功能

- MacBook 布局热力图（功能行 + 主键区 + 倒 T 方向键，无独立小键盘），含色阶图例。
- 修饰键 ⌘⌥⌃⇧⇪fn 也计数（通过 `flagsChanged`，长按只计一次）。
- 音量、静音、亮度和媒体控制功能键也会映射到对应的 F 键进行统计。
- 右侧统计面板：总敲击数、起始日期、Top 10 常用键。
- 菜单栏图标：总数 + 最常用 5 键 + 暂停/继续 + 打开主窗口 + 退出。
- 顶栏「暂停」「重置」（重置带二次确认）。
- 首次启动可选择是否保留 Dock 图标；之后可从菜单栏菜单中切换。
- 计数为累计值，自动持久化到本机，退出重开数据仍在。

## 项目结构

```
build.sh                     # 编译 + 打包 .app + ad-hoc 签名
Sources/
  KeyStatsApp.swift          # @main：WindowGroup 主窗口 + MenuBarExtra 菜单栏图标
  AppState.swift             # ObservableObject 数据核心：计数、节流发布、持久化、重置
  KeyMonitor.swift           # CGEventTap 全局监听 + 权限检查/申请（.listenOnly，纯观察）
  KeyCodeMap.swift           # Carbon 硬件键码 → 键帽 + 完整 MacBook 布局
  HeatColor.swift            # 计数归一化 + 顺序色阶（明/暗自适应）
  ContentView.swift          # 主窗口：顶栏 + 热力图 + 图例 + 统计 + 未授权引导页
  KeyboardHeatmapView.swift  # 逐行渲染键帽（热力色 + 次数）+ 色阶图例
  StatsPanelView.swift       # 总数 / 起始日期 / Top 10
  MenuBarView.swift          # 菜单栏弹出面板
  Resources/
    Info.plist                 # bundleID、名称、最低系统版本等
```

---

## English

### Keyboard Heatmap (KeyStats)

A small native macOS utility that counts how many times each physical keyboard key is pressed and visualizes the result as a heatmap.

It includes a standalone main window and a menu bar panel, built with SwiftUI for MacBook-style keyboard layouts.

### Privacy

This app stores only one kind of aggregated data: the total count for each physical key.

It does **not** record:

- The order of key presses
- Typed text, passwords, or any input content
- The active app or window

The data is stored locally at `~/Library/Application Support/com.allen.keystats/counts.json` and is never uploaded.

### Build

The project can be built without the full Xcode application. Install Apple Command Line Tools first:

```bash
xcode-select --install
```

Then build and run:

```bash
./build.sh
./build.sh --run
```

The generated app is `键盘热力图.app` in the project directory.

The first build creates a free, stable local signing certificate named `KeyStats Local Dev` in the login keychain. This keeps macOS Input Monitoring permission stable across normal rebuilds. Keep `.build/local-signing` intact; removing it creates a new signing identity and may require authorization again.

### Input Monitoring Permission

macOS requires **Input Monitoring** permission to observe global keyboard events. On first launch, click **申请授权** or open:

`System Settings → Privacy & Security → Input Monitoring`

Enable **键盘热力图**, then quit and relaunch the app once.

### Features

- MacBook keyboard heatmap with color legend
- Modifier-key tracking for ⌘ ⌥ ⌃ ⇧ ⇪ fn
- Media keys such as volume, mute, brightness, and playback mapped to their physical F keys
- Autorepeat filtering so a long press counts once
- Total count, start date, and Top 10 keys
- Menu bar panel with the total and Top 5 keys
- Pause, resume, reset, and local persistence
- First-launch choice for showing the app in the Dock, with a menu bar toggle afterward

### License

This project is provided for personal learning and experimentation. Add a license before redistributing it publicly.
