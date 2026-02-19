import Foundation
import Sparkle

/// Sparkle の SPUUpdater を SwiftUI から利用するためのビューモデル。
/// `canCheckForUpdates` を KVO で監視し、UI のボタン有効/無効を制御する。
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // KVO で updater.canCheckForUpdates を監視
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
