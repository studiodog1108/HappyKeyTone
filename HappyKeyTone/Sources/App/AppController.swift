import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Observation
import os
import SwiftUI

private let logger = Logger(subsystem: "com.happykeytone.app", category: "AppController")

private final class KeyEventForwarder: @unchecked Sendable {
    var handler: ((KeyEvent) -> Void)?
}

enum DiagnosticLevel: String, Sendable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

struct DiagnosticLogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: DiagnosticLevel
    let message: String
}

@Observable
@MainActor
final class AppController {
    var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "isEnabled")
            if isEnabled {
                startEventTap()
            } else {
                eventTapService.stop()
                isListening = false
            }
        }
    }

    var volume: Float = 0.8 {
        didSet {
            UserDefaults.standard.set(volume, forKey: "volume")
            audioEngine.volume = volume
        }
    }

    var selectedSoundPackID: String = "Happy" {
        didSet {
            UserDefaults.standard.set(selectedSoundPackID, forKey: "selectedSoundPackID")
            loadSoundPack()
        }
    }

    var pitchVariation: Float = 0.05 {
        didSet {
            UserDefaults.standard.set(pitchVariation, forKey: "pitchVariation")
            audioEngine.pitchVariation = pitchVariation
        }
    }

    /// UIに表示するエラーメッセージ
    var errorMessage: String?

    /// EventTapが稼働中かどうか
    var isListening: Bool = false

    /// 権限不足で監視が開始できない状態かどうか
    var needsPermission: Bool = false
    var inputMonitoringGranted: Bool = false
    var accessibilityGranted: Bool = false
    var monitorBackend: KeyboardMonitorBackend = .none

    /// オンボーディング完了フラグ
    var hasCompletedOnboarding: Bool = false

    /// 実行時診断
    var keyEventsReceived: Int = 0
    var soundsPlayed: Int = 0
    var previewPlays: Int = 0
    var skippedRepeats: Int = 0
    var missingBufferEvents: Int = 0
    var lastKeyEventSummary: String = "-"
    var diagnosticLogs: [DiagnosticLogEntry] = []

    let soundPackManager = SoundPackManager()
    @ObservationIgnored private let audioEngine = TypingAudioEngine()
    @ObservationIgnored private let keyEventForwarder = KeyEventForwarder()
    @ObservationIgnored private let eventTapService: EventTapService

    /// オンボーディングウィンドウの参照
    @ObservationIgnored private var onboardingWindow: NSWindow?
    /// ウィンドウクローズ通知のオブザーバー
    @ObservationIgnored private var onboardingCloseObserver: Any?

    /// 権限チェック用の定期タイマー
    private var permissionRetryTask: Task<Void, Never>?
    /// Input Monitoring権限リクエストを同一セッションで連打しないためのフラグ
    private var hasRequestedInputMonitoringAccess = false
    /// Accessibility権限リクエストを同一セッションで連打しないためのフラグ
    private var hasRequestedAccessibilityAccess = false
    private let maxDiagnosticEntries = 200

    init() {
        eventTapService = EventTapService { [weak keyEventForwarder] event in
            Task { @MainActor in
                keyEventForwarder?.handler?(event)
            }
        }

        // UserDefaultsから復元（didSetはinitでは呼ばれない）
        isEnabled = UserDefaults.standard.object(forKey: "isEnabled") as? Bool ?? true
        volume = UserDefaults.standard.object(forKey: "volume") as? Float ?? 0.8
        selectedSoundPackID = UserDefaults.standard.string(forKey: "selectedSoundPackID") ?? "Happy"
        pitchVariation = UserDefaults.standard.object(forKey: "pitchVariation") as? Float ?? 0.05

        audioEngine.volume = volume
        audioEngine.pitchVariation = pitchVariation
        keyEventForwarder.handler = { [weak self] event in
            self?.handleKeyEvent(event)
        }

        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        refreshPermissionStatus(log: false)
        loadSoundPack()
        addDiagnostic(
            "App started. Input Monitoring: \(permissionText(inputMonitoringGranted)), Accessibility: \(permissionText(accessibilityGranted))."
        )

        if let audioError = audioEngine.lastError {
            errorMessage = audioError
            addDiagnostic(audioError, level: .error)
        }

        // 有効なら即座にイベントタップ開始を試行
        if isEnabled {
            startEventTap()
        }

        // 初回起動時はオンボーディングウィンドウを表示
        if !hasCompletedOnboarding {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.showOnboardingWindowIfNeeded()
            }
        }
    }

    /// EventTapの開始を試行し、結果をUIに反映
    func startEventTap() {
        guard isEnabled else {
            eventTapService.stop()
            isListening = false
            monitorBackend = .none
            updatePermissionRequirement()
            return
        }

        refreshPermissionStatus(log: false)
        if !inputMonitoringGranted {
            requestInputMonitoringPermissionIfNeeded()
            addDiagnostic(
                "Input Monitoring is not granted. Trying available monitor backends.",
                level: .warning
            )
        }

        eventTapService.start { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }

                isListening = result.isRunning
                monitorBackend = result.backend
                updatePermissionRequirement()

                if result.isRunning {
                    if errorMessage?.contains("permission") == true
                        || errorMessage?.contains("monitoring") == true
                    {
                        self.errorMessage = nil
                    }

                    permissionRetryTask?.cancel()
                    permissionRetryTask = nil
                    addDiagnostic("Keyboard monitor started via \(result.backend.rawValue).")

                    if result.backend == .globalMonitor && !inputMonitoringGranted {
                        addDiagnostic(
                            "Running on fallback monitor. Grant Input Monitoring for better compatibility.",
                            level: .warning
                        )
                    }
                    logger.info("Keyboard monitor is now active (\(result.backend.rawValue)).")
                } else {
                    let reason = result.failureReason ?? "Keyboard monitoring failed to start."
                    errorMessage = reason
                    addDiagnostic(reason, level: .error)
                    logger.warning("Event tap failed. Starting recovery polling.")
                    startPermissionRetryPolling()
                }
            }
        }
    }

    /// 権限が付与されるまで定期的にリトライ
    private func startPermissionRetryPolling() {
        permissionRetryTask?.cancel()
        permissionRetryTask = Task { [weak self] in
            // 最大5分間リトライ（2秒間隔）
            for index in 0..<150 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard self.isEnabled && !self.isListening else { return }

                self.refreshPermissionStatus(log: false)
                if self.inputMonitoringGranted || self.accessibilityGranted {
                    self.addDiagnostic("Retrying keyboard monitor start after permission change.")
                    self.startEventTap()
                } else if (index + 1).isMultiple(of: 10) {
                    self.addDiagnostic(
                        "Waiting for Input Monitoring / Accessibility permissions...",
                        level: .warning
                    )
                }
                // startEventTapのコールバックで isListening が更新される
                // 成功した場合、このタスクはキャンセルされる
                try? await Task.sleep(for: .seconds(1))
            }

            await MainActor.run { [weak self] in
                self?.addDiagnostic("Permission retry polling timed out.", level: .warning)
            }
        }
    }

    /// Input Monitoringの許可を明示的に要求（UIアクション用）
    func requestInputMonitoringPermission() {
        requestInputMonitoringPermissionIfNeeded(force: true)
        openInputMonitoringSettings()
    }

    /// Accessibilityの許可を明示的に要求（UIアクション用）
    func requestAccessibilityPermission() {
        requestAccessibilityPermissionIfNeeded(force: true)
        openAccessibilitySettings()
    }

    func refreshDiagnostics() {
        refreshPermissionStatus(log: true)
        addDiagnostic(
            "Runtime status: listening=\(isListening), backend=\(monitorBackend.rawValue), engine=\(audioEngine.isEngineRunning), buffers=\(audioEngine.loadedBufferCount)/\(audioEngine.expectedBufferCount), keyEvents=\(keyEventsReceived), played=\(soundsPlayed)"
        )
    }

    func clearDiagnostics() {
        diagnosticLogs.removeAll()
    }

    /// システム設定のInput Monitoring画面を開く
    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    /// システム設定のAccessibility画面を開く
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// キー監視とは独立したテスト再生（音声経路の疎通確認用）
    func playPreviewSound() {
        let result = audioEngine.playPreview()
        switch result {
        case .played:
            previewPlays += 1
            addDiagnostic("Preview sound played successfully.")
        case .skippedRepeat:
            break
        case .noBuffer:
            errorMessage = "No playable audio is loaded."
            addDiagnostic("Preview playback failed: no playable audio buffers.", level: .warning)
        case .engineError(let message):
            errorMessage = message
            addDiagnostic(message, level: .error)
        }
    }

    private func loadSoundPack() {
        if let pack = soundPackManager.soundPack(for: selectedSoundPackID) {
            audioEngine.loadSoundPack(pack)
            if let audioError = audioEngine.lastError {
                errorMessage = audioError
                addDiagnostic(audioError, level: .error)
            } else {
                // 権限系以外のエラーのみクリア
                if errorMessage != nil && errorMessage?.contains("Input Monitoring") == false {
                    errorMessage = nil
                }
            }
            addDiagnostic(
                "Loaded sound pack '\(pack.info.name)' (\(audioEngine.loadedBufferCount)/\(audioEngine.expectedBufferCount) buffers)."
            )
            logger.info("Loaded sound pack: \(pack.info.name)")
            return
        }

        // 選択パックが見つからない場合、最初の利用可能なパックにフォールバック
        logger.warning("Sound pack '\(self.selectedSoundPackID)' not found. Falling back to first available.")
        if let firstPack = soundPackManager.availablePacks.first {
            selectedSoundPackID = firstPack.id
        } else {
            errorMessage = "No sound packs available."
            addDiagnostic("No sound packs available.", level: .error)
            logger.error("No sound packs available at all.")
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    /// 権限状態を外部からチェック（オンボーディングビュー用）
    func checkPermissions() {
        refreshPermissionStatus(log: false)
    }

    /// オンボーディングを完了としてマーク
    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        dismissOnboardingWindow()
    }

    /// オンボーディングウィンドウを表示
    func showOnboardingWindowIfNeeded() {
        guard !hasCompletedOnboarding else { return }
        if let existingWindow = onboardingWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let onboardingView = OnboardingView()
            .environment(self)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "HappyKeyTone Setup"
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // ウィンドウが閉じられたときに参照をクリーンアップ
        onboardingCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onboardingWindow = nil
                self?.onboardingCloseObserver = nil
            }
        }

        onboardingWindow = window
    }

    /// オンボーディングウィンドウを閉じる
    private func dismissOnboardingWindow() {
        if let observer = onboardingCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            onboardingCloseObserver = nil
        }
        onboardingWindow?.close()
        onboardingWindow = nil
    }

    private func hasInputMonitoringPermission() -> Bool {
        CGPreflightListenEventAccess()
    }

    private func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    private func refreshPermissionStatus(log: Bool) {
        let previousInput = inputMonitoringGranted
        let previousAccessibility = accessibilityGranted

        inputMonitoringGranted = hasInputMonitoringPermission()
        accessibilityGranted = hasAccessibilityPermission()
        updatePermissionRequirement()

        if log || previousInput != inputMonitoringGranted || previousAccessibility != accessibilityGranted {
            addDiagnostic(
                "Permission status: Input Monitoring=\(permissionText(inputMonitoringGranted)), Accessibility=\(permissionText(accessibilityGranted))."
            )
        }
    }

    private func requestInputMonitoringPermissionIfNeeded(force: Bool = false) {
        if force {
            hasRequestedInputMonitoringAccess = false
        }
        guard !hasRequestedInputMonitoringAccess else { return }
        hasRequestedInputMonitoringAccess = true

        let granted = CGRequestListenEventAccess()
        refreshPermissionStatus(log: true)
        addDiagnostic(
            granted
                ? "Input Monitoring permission request was accepted."
                : "Input Monitoring permission request is still pending/denied.",
            level: granted ? .info : .warning
        )
        if granted && isEnabled && !isListening {
            startEventTap()
        }
    }

    private func requestAccessibilityPermissionIfNeeded(force: Bool = false) {
        if force {
            hasRequestedAccessibilityAccess = false
        }
        guard !hasRequestedAccessibilityAccess else { return }
        hasRequestedAccessibilityAccess = true

        let options: CFDictionary = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        refreshPermissionStatus(log: true)
        addDiagnostic(
            granted
                ? "Accessibility permission request was accepted."
                : "Accessibility permission request is still pending/denied.",
            level: granted ? .info : .warning
        )
        if granted && isEnabled && !isListening {
            startEventTap()
        }
    }

    private func updatePermissionRequirement() {
        needsPermission = isEnabled && !isListening && !inputMonitoringGranted && !accessibilityGranted
    }

    private func addDiagnostic(_ message: String, level: DiagnosticLevel = .info) {
        let entry = DiagnosticLogEntry(
            timestamp: Date(),
            level: level,
            message: message
        )
        diagnosticLogs.insert(entry, at: 0)
        if diagnosticLogs.count > maxDiagnosticEntries {
            diagnosticLogs.removeLast(diagnosticLogs.count - maxDiagnosticEntries)
        }
    }

    private func describe(event: KeyEvent) -> String {
        let type = event.type == .keyDown ? "down" : "up"
        return "\(type) code=\(event.keyCode) category=\(event.category.rawValue)"
    }

    private func permissionText(_ granted: Bool) -> String {
        granted ? "granted" : "missing"
    }

    private func handleKeyEvent(_ event: KeyEvent) {
        keyEventsReceived += 1
        lastKeyEventSummary = describe(event: event)

        let result = audioEngine.play(for: event)
        switch result {
        case .played:
            soundsPlayed += 1
            if keyEventsReceived == 1 || keyEventsReceived % 100 == 0 {
                addDiagnostic(
                    "Key events: \(keyEventsReceived), sounds played: \(soundsPlayed), backend: \(monitorBackend.rawValue)"
                )
            }
        case .skippedRepeat:
            skippedRepeats += 1
        case .noBuffer:
            missingBufferEvents += 1
            if missingBufferEvents == 1 || missingBufferEvents % 20 == 0 {
                addDiagnostic(
                    "No audio buffer for event \(describe(event: event)). Missing count: \(missingBufferEvents)",
                    level: .warning
                )
            }
        case .engineError(let message):
            errorMessage = message
            addDiagnostic(message, level: .error)
        }
    }
}
