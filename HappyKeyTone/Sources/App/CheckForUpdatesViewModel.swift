import Foundation
import Sparkle
import UserNotifications

/// Sparkle の SPUUpdater を SwiftUI から利用するためのビューモデル。
/// `canCheckForUpdates` を KVO で監視し、UI のボタン有効/無効を制御する。
/// LSUIElement=true のバックグラウンドアプリのため、gentle reminders として
/// UserNotifications を利用してアップデート通知を表示する。
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController
    private let gentleReminderDelegate = GentleReminderDelegate()

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: gentleReminderDelegate
        )

        // KVO で updater.canCheckForUpdates を監視
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

/// Sparkle の gentle reminders 対応。
/// バックグラウンドアプリ (LSUIElement=true) ではアップデートUIが見えにくいため、
/// UserNotifications でシステム通知を送ることで気づきやすくする。
final class GentleReminderDelegate: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if state.userInitiated { return }

        // ユーザー操作ではない自動チェック時のみ通知
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "HappyKeyTone アップデート"
            content.body = "バージョン \(update.displayVersionString) が利用可能です。"
            let request = UNNotificationRequest(
                identifier: "sparkle-update-\(update.versionString)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}
