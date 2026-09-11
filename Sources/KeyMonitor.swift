import Foundation
import CoreGraphics
import ApplicationServices
import AppKit

// MARK: - 全局按键监听
//
// 用 CGEvent 事件监听（listenOnly：纯观察，绝不拦截/修改/吞掉任何按键）。
// 监听 keyDown（普通键）与 flagsChanged（修饰键）。每次事件只把「键码」交给回调，
// 从不保存按键顺序或输入内容。需要系统「输入监控 (Input Monitoring)」权限。

final class KeyMonitor {

    // CGEventType 在部分 macOS SDK 中没有公开 systemDefined 枚举值，
    // 但事件类型值 14 仍用于 NX_SYSDEFINED（音量/亮度/媒体键）。
    private static let systemDefinedEventType = CGEventType(rawValue: 14)!

    /// 每次有效按键回调（keyCode）。回调在主线程触发。
    var onKey: ((Int) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// 当前按下的修饰键集合（用于把 flagsChanged 的按下/抬起区分开，只在「按下」时计数）。
    private var pressedModifiers: Set<Int> = []

    /// 是否跳过长按自动重复（默认跳过，一次长按只计一次）。
    var ignoreAutorepeat = true

    // MARK: 权限

    /// 是否已获得「输入监控」权限。
    static func hasPermission() -> Bool {
        CGPreflightListenEventAccess()
    }

    /// 触发系统的「输入监控」授权弹窗（首次会弹，之后引导用户去系统设置）。
    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    // MARK: 生命周期

    var isRunning: Bool { tap != nil }

    /// 尝试启动监听。返回是否成功（未授权或系统拒绝时返回 false）。
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard KeyMonitor.hasPermission() else { return false }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << Self.systemDefinedEventType.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<KeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            // listenOnly：把事件原样放行，绝不改动。
            return Unmanaged.passUnretained(event)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                           place: .headInsertEventTap,
                                           options: .listenOnly,
                                           eventsOfInterest: mask,
                                           callback: callback,
                                           userInfo: selfPtr) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        tap = port
        runLoopSource = source
        return true
    }

    func stop() {
        if let port = tap {
            CGEvent.tapEnable(tap: port, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CFMachPortInvalidate(port)
        }
        tap = nil
        runLoopSource = nil
        pressedModifiers.removeAll()
    }

    // MARK: 事件处理

    private func handle(type: CGEventType, event: CGEvent) {
        // 事件 tap 被系统临时禁用（超时或用户输入过快）时，重新启用。
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = tap { CGEvent.tapEnable(tap: port, enable: true) }
            return
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        if type == Self.systemDefinedEventType {
            // 音量、静音、亮度、媒体控制等功能键不会发送普通 keyDown，
            // 而是以 NX_SYSDEFINED 事件发送。
            handleSystemDefined(event)
            return
        }

        switch type {
        case .keyDown:
            if ignoreAutorepeat && event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                return  // 长按重复，不计
            }
            deliver(keyCode)

        case .flagsChanged:
            // 修饰键：flagsChanged 在按下和抬起时各触发一次。
            // 用 pressedModifiers 记录状态，只在「按下」这一下计数。
            if pressedModifiers.contains(keyCode) {
                pressedModifiers.remove(keyCode)      // 抬起
            } else {
                pressedModifiers.insert(keyCode)      // 按下
                deliver(keyCode)
            }

        default:
            break
        }
    }

    private func handleSystemDefined(_ event: CGEvent) {
        guard let nsEvent = NSEvent(cgEvent: event) else { return }

        // data1 的高 16 位是 NX_KEYTYPE，中间字节为 0x0A 表示按下；
        // 这里只统计按下，避免松开重复计数。
        let data1 = Int64(nsEvent.data1)
        let systemKey = Int((data1 >> 16) & 0xFFFF)
        let keyState = Int((data1 >> 8) & 0xFF)
        guard keyState == 0x0A else { return }

        // NX_KEYTYPE → MacBook 功能行的物理键码。
        // 这些是硬件键码，因此最终仍会显示并累计到对应的 F 键。
        let physicalKeyCode: [Int: Int] = [
            0: 111,  // 音量加 → F12
            1: 103,  // 音量减 → F11
            2: 120,  // 亮度加 → F2
            3: 122,  // 亮度减 → F1
            7: 109,  // 静音 → F10
            16: 100, // 播放/暂停 → F8
            17: 101, // 下一曲 → F9
            18: 98,  // 上一曲 → F7
            22: 97,  // 键盘背光加 → F6
            23: 96   // 键盘背光减 → F5
        ]

        if let keyCode = physicalKeyCode[systemKey] {
            deliver(keyCode)
        }
    }

    private func deliver(_ keyCode: Int) {
        // 回调可能已在主线程（tap 挂在主 runloop），保险起见统一切到主线程。
        if Thread.isMainThread {
            onKey?(keyCode)
        } else {
            DispatchQueue.main.async { [weak self] in self?.onKey?(keyCode) }
        }
    }

    deinit { stop() }
}
