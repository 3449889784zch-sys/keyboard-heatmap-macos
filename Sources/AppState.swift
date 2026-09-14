import Foundation
import SwiftUI
import AppKit
import Combine
import ServiceManagement

// MARK: - 应用状态 / 数据核心
//
// 只保存「每个物理键的累计次数」。不记录顺序、不记录输入内容、不记录所在 app。
// 为了界面流畅：真正的计数写进 liveCounts（每次敲键 O(1) 更新，不触发 SwiftUI 刷新），
// 再由一个 ~0.2s 的定时器把快照发布到 @Published，供界面按帧率友好地重绘。

final class AppState: ObservableObject {

    // 发布给界面的快照
    @Published private(set) var counts: [Int: Int] = [:]
    @Published private(set) var total: Int = 0
    @Published private(set) var maxCount: Int = 0

    // 状态
    @Published var permissionGranted: Bool = false
    @Published var monitorActive: Bool = false
    @Published var needsRestart: Bool = false     // 已授权但 tap 仍创建失败 → 提示重启
    @Published var confirmingReset: Bool = false  // 「重置」二次确认弹窗开关（纯界面状态，不持久化）
    @Published var showDockChoice: Bool
    @Published private(set) var launchAtLoginEnabled = false
    @Published var launchAtLoginError: String?
    @Published var isPaused: Bool = false {
        didSet { UserDefaults.standard.set(isPaused, forKey: "isPaused") }
    }
    @Published private(set) var countingSince: Date

    // 内部实时计数
    private var liveCounts: [Int: Int] = [:]
    private var liveTotal: Int = 0
    private var liveMax: Int = 0
    private var dirty = false
    private var lastSave = Date()

    private let monitor = KeyMonitor()
    private var uiTimer: Timer?
    private var permTimer: Timer?

    private let dockVisibilityKey = "showInDock"

    // MARK: 存储位置

    private static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("com.allen.keystats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("counts.json")
    }

    private struct PersistModel: Codable {
        var version: Int
        var counts: [String: Int]
        var countingSince: Date
        var lastUpdated: Date
    }

    // MARK: 初始化

    init() {
        self.countingSince = Date()
        self.isPaused = UserDefaults.standard.bool(forKey: "isPaused")
        self.showDockChoice = UserDefaults.standard.object(forKey: "showInDock") == nil
        load()
        refreshLaunchAtLoginStatus()

        // 默认只作为菜单栏应用运行；首次打开时由界面询问是否保留 Dock 图标。
        let showInDock = UserDefaults.standard.bool(forKey: dockVisibilityKey)
        DispatchQueue.main.async { [weak self] in
            self?.applyDockPolicy(showInDock: showInDock)
        }

        monitor.onKey = { [weak self] keyCode in
            self?.increment(keyCode)
        }

        permissionGranted = KeyMonitor.hasPermission()
        startUITimer()
        startPermissionWatch()
        if permissionGranted { activateMonitor() }

        // 退出前保存一次，避免丢掉最后几秒的计数。
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.save()
        }
    }

    // MARK: 计数

    private func increment(_ keyCode: Int) {
        guard !isPaused else { return }
        let n = (liveCounts[keyCode] ?? 0) + 1
        liveCounts[keyCode] = n
        liveTotal += 1
        if n > liveMax { liveMax = n }
        dirty = true
    }

    // MARK: 定时发布 + 自动保存

    private func startUITimer() {
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)   // .common：菜单/拖拽时也能刷新
        uiTimer = t
    }

    private func tick() {
        if dirty {
            counts = liveCounts
            total = liveTotal
            maxCount = liveMax
            dirty = false
        }
        if Date().timeIntervalSince(lastSave) > 5 {
            saveIfNeeded()
        }
    }

    // MARK: 权限

    private func startPermissionWatch() {
        guard !permissionGranted || !monitorActive else { return }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPermission()
        }
        RunLoop.main.add(t, forMode: .common)
        permTimer = t
    }

    private func checkPermission() {
        let granted = KeyMonitor.hasPermission()
        if granted != permissionGranted { permissionGranted = granted }
        if granted && !monitorActive { activateMonitor() }
        if monitorActive {                       // 已就绪，停止轮询
            permTimer?.invalidate(); permTimer = nil
        }
    }

    func requestPermission() {
        KeyMonitor.requestPermission()
        // 弹窗是异步的；继续用轮询感知授权结果。
        if permTimer == nil { startPermissionWatch() }
    }

    func recheckPermissionNow() { checkPermission() }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Dock 显示方式

    func setDockVisible(_ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: dockVisibilityKey)
        showDockChoice = false
        applyDockPolicy(showInDock: visible)
    }

    func toggleDockVisibility() {
        let currentlyVisible = NSApp.activationPolicy() == .regular
        setDockVisible(!currentlyVisible)
    }

    private func applyDockPolicy(showInDock: Bool) {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    // MARK: 开机自启动

    /// 使用 macOS 的登录项服务注册当前 app。系统也可在「通用 > 登录项」中管理它。
    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            refreshLaunchAtLoginStatus()
        } catch {
            refreshLaunchAtLoginStatus()
            launchAtLoginError = "无法更新开机自启动设置：\(error.localizedDescription)"
        }
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    private func activateMonitor() {
        let ok = monitor.start()
        monitorActive = ok
        needsRestart = !ok      // 已授权却启动失败 → 多半需要重启 app
    }

    // MARK: Top 键

    struct RankedKey: Identifiable {
        let id: Int
        let name: String
        let count: Int
    }

    func topKeys(_ n: Int) -> [RankedKey] {
        counts.filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(n)
            .map { RankedKey(id: $0.key, name: KeyboardLayout.name(for: $0.key), count: $0.value) }
    }

    // MARK: 重置

    func reset() {
        liveCounts.removeAll()
        liveTotal = 0
        liveMax = 0
        counts = [:]
        total = 0
        maxCount = 0
        countingSince = Date()
        dirty = false
        save()
    }

    // MARK: 持久化

    private func load() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let model = try? JSONDecoder.iso.decode(PersistModel.self, from: data) else {
            return
        }
        var restored: [Int: Int] = [:]
        var mx = 0, tot = 0
        for (k, v) in model.counts {
            if let code = Int(k) {
                restored[code] = v
                tot += v
                if v > mx { mx = v }
            }
        }
        liveCounts = restored
        liveTotal = tot
        liveMax = mx
        counts = restored
        total = tot
        maxCount = mx
        countingSince = model.countingSince
    }

    private func saveIfNeeded() {
        guard dirty || Date().timeIntervalSince(lastSave) > 5 else { return }
        save()
    }

    func save() {
        lastSave = Date()
        let snapshot = liveCounts
        let since = countingSince
        let url = Self.storeURL
        DispatchQueue.global(qos: .utility).async {
            var strCounts: [String: Int] = [:]
            strCounts.reserveCapacity(snapshot.count)
            for (k, v) in snapshot { strCounts[String(k)] = v }
            let model = PersistModel(version: 1, counts: strCounts,
                                     countingSince: since, lastUpdated: Date())
            if let data = try? JSONEncoder.iso.encode(model) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}

// MARK: - JSON 日期编解码（ISO8601）

private extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted]
        return e
    }()
}

private extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
