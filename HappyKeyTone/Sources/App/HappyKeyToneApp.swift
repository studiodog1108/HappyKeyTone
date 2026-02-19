import SwiftUI

@main
struct HappyKeyToneApp: App {
    @State private var appController = AppController()
    @StateObject private var updaterViewModel = CheckForUpdatesViewModel()

    var body: some Scene {
        MenuBarExtra {
            MainPopoverView()
                .environment(appController)
                .environmentObject(updaterViewModel)
        } label: {
            Image(systemName: appController.isEnabled ? "keyboard.fill" : "keyboard")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appController)
                .environmentObject(updaterViewModel)
        }
    }
}
