import AppKit
import CoreGraphics
import Foundation
import os

private let logger = Logger(subsystem: "com.happykeytone.app", category: "EventTap")

enum KeyboardMonitorBackend: String, Sendable {
    case eventTap = "CGEventTap"
    case globalMonitor = "NSEvent Global Monitor"
    case none = "Not Running"
}

struct KeyboardMonitorStartResult: Sendable {
    let isRunning: Bool
    let backend: KeyboardMonitorBackend
    let failureReason: String?
}

/// CGEventTapを使ったグローバルキーボードイベント監視
final class EventTapService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.happykeytone.eventtap")
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var targetRunLoop: CFRunLoop?
    private var globalMonitor: Any?
    private var backend: KeyboardMonitorBackend = .none
    private var isRunning = false
    private var pressedKeys: Set<Int64> = []
    private var repeatedKeys: Set<Int64> = []
    private var lastKeyDownAt: [Int64: CFAbsoluteTime] = [:]
    private let repeatIntervalThreshold: CFTimeInterval = 0.05

    /// コールバックはinitで設定し、以降変更不可
    private let keyEventHandler: @Sendable (KeyEvent) -> Void

    init(onKeyEvent: @escaping @Sendable (KeyEvent) -> Void) {
        self.keyEventHandler = onKeyEvent
    }

    deinit {
        stopOnQueue()
    }

    /// イベントタップを開始し、結果をコールバックで通知
    func start(completion: (@Sendable (KeyboardMonitorStartResult) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else {
                completion?(
                    KeyboardMonitorStartResult(
                        isRunning: false,
                        backend: .none,
                        failureReason: "Keyboard monitor service is unavailable."
                    )
                )
                return
            }
            let result = self.startOnQueue()
            completion?(result)
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    private func startOnQueue() -> KeyboardMonitorStartResult {
        guard !isRunning else {
            return KeyboardMonitorStartResult(isRunning: true, backend: backend, failureReason: nil)
        }

        if startEventTapBackend() {
            return KeyboardMonitorStartResult(isRunning: true, backend: .eventTap, failureReason: nil)
        }

        let fallback = startGlobalMonitorBackend()
        if fallback.success {
            isRunning = true
            backend = .globalMonitor
            logger.warning("Falling back to NSEvent global monitor.")
            return KeyboardMonitorStartResult(isRunning: true, backend: .globalMonitor, failureReason: nil)
        }

        let reason = fallback.reason ?? "Failed to start keyboard monitoring."
        logger.error("\(reason)")
        return KeyboardMonitorStartResult(isRunning: false, backend: .none, failureReason: reason)
    }

    private func startEventTapBackend() -> Bool {
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let pointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: pointer
        ) else {
            logger.warning("Failed to create event tap.")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        guard let source else {
            CFMachPortInvalidate(tap)
            logger.error("Failed to create RunLoopSource for event tap.")
            return false
        }

        eventTap = tap
        runLoopSource = source
        backend = .eventTap
        // メインRunLoopに追加（GCDキューのRunLoopは回らないため）
        let mainLoop = CFRunLoopGetMain()
        targetRunLoop = mainLoop
        CFRunLoopAddSource(mainLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        logger.info("Event tap started successfully.")
        return true
    }

    private func startGlobalMonitorBackend() -> (success: Bool, reason: String?) {
        guard AXIsProcessTrusted() else {
            logger.warning("Accessibility permission is not granted for fallback monitor.")
            return (false, "Input Monitoring and Accessibility permissions are both unavailable.")
        }

        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        let monitor = syncOnMain {
            NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                self?.handleFallbackEvent(event)
            }
        }

        guard let monitor else {
            return (false, "Failed to create NSEvent global monitor.")
        }
        globalMonitor = monitor
        return (true, nil)
    }

    private func stopOnQueue() {
        guard isRunning else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }

        if let source = runLoopSource, let runLoop = targetRunLoop {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }

        if let monitor = globalMonitor {
            syncOnMain {
                NSEvent.removeMonitor(monitor)
            }
        }

        eventTap = nil
        runLoopSource = nil
        targetRunLoop = nil
        globalMonitor = nil
        backend = .none
        isRunning = false
        pressedKeys.removeAll()
        repeatedKeys.removeAll()
        lastKeyDownAt.removeAll()
        logger.info("Event tap stopped.")
    }

    fileprivate func handleEvent(_ proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            logger.warning("Event tap was disabled by system (type: \(String(describing: type))). Re-enabling.")
            if backend == .eventTap, let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let autoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let isRepeat = classifyKeyDown(keyCode: keyCode, osRepeat: autoRepeat)
            let keyEvent = KeyEvent(type: .keyDown, keyCode: keyCode, isRepeat: isRepeat)
            keyEventHandler(keyEvent)

        case .keyUp:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let keyEvent = classifyKeyUp(keyCode: keyCode)
            keyEventHandler(keyEvent)

        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            let isDown = isModifierDown(keyCode: keyCode, flags: flags)
            if isDown {
                pressedKeys.insert(keyCode)
            } else {
                pressedKeys.remove(keyCode)
                repeatedKeys.remove(keyCode)
            }
            let keyEvent = KeyEvent(
                type: isDown ? .keyDown : .keyUp,
                keyCode: keyCode
            )
            keyEventHandler(keyEvent)

        default:
            break
        }
    }

    private func handleFallbackEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            let keyCode = Int64(event.keyCode)
            let isRepeat = classifyKeyDown(keyCode: keyCode, osRepeat: event.isARepeat)
            let keyEvent = KeyEvent(type: .keyDown, keyCode: keyCode, isRepeat: isRepeat)
            keyEventHandler(keyEvent)

        case .keyUp:
            let keyCode = Int64(event.keyCode)
            let keyEvent = classifyKeyUp(keyCode: keyCode)
            keyEventHandler(keyEvent)

        case .flagsChanged:
            let keyCode = Int64(event.keyCode)
            let isDown = isModifierDown(keyCode: keyCode, flags: event.modifierFlags)
            if isDown {
                pressedKeys.insert(keyCode)
            } else {
                pressedKeys.remove(keyCode)
                repeatedKeys.remove(keyCode)
            }
            let keyEvent = KeyEvent(
                type: isDown ? .keyDown : .keyUp,
                keyCode: keyCode
            )
            keyEventHandler(keyEvent)

        default:
            return
        }
    }

    private func classifyKeyDown(keyCode: Int64, osRepeat: Bool) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        let recentDown = lastKeyDownAt[keyCode] ?? 0
        let timingRepeat = recentDown > 0 && (now - recentDown) < repeatIntervalThreshold

        let isRepeat =
            osRepeat ||
            pressedKeys.contains(keyCode) ||
            repeatedKeys.contains(keyCode) ||
            timingRepeat

        pressedKeys.insert(keyCode)
        lastKeyDownAt[keyCode] = now
        if isRepeat {
            repeatedKeys.insert(keyCode)
        }
        return isRepeat
    }

    private func classifyKeyUp(keyCode: Int64) -> KeyEvent {
        let wasRepeating = repeatedKeys.contains(keyCode)
        pressedKeys.remove(keyCode)
        repeatedKeys.remove(keyCode)
        return KeyEvent(type: .keyUp, keyCode: keyCode, isRepeat: wasRepeating)
    }

    private func isModifierDown(keyCode: Int64, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case 56, 60: return flags.contains(.maskShift)
        case 59, 62: return flags.contains(.maskControl)
        case 58, 61: return flags.contains(.maskAlternate)
        case 54, 55: return flags.contains(.maskCommand)
        case 57:     return flags.contains(.maskAlphaShift)
        case 63:     return flags.contains(.maskSecondaryFn)
        default:     return false
        }
    }

    private func isModifierDown(keyCode: Int64, flags: NSEvent.ModifierFlags) -> Bool {
        switch keyCode {
        case 56, 60: return flags.contains(.shift)
        case 59, 62: return flags.contains(.control)
        case 58, 61: return flags.contains(.option)
        case 54, 55: return flags.contains(.command)
        case 57:     return flags.contains(.capsLock)
        case 63:     return flags.contains(.function)
        default:     return false
        }
    }

    private func syncOnMain<T>(_ block: () -> T) -> T {
        if Thread.isMainThread {
            return block()
        }
        return DispatchQueue.main.sync(execute: block)
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<EventTapService>.fromOpaque(userInfo).takeUnretainedValue()
    service.handleEvent(proxy, type: type, event: event)
    return Unmanaged.passUnretained(event)
}
