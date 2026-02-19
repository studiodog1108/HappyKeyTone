import SwiftUI
import ServiceManagement

/// 設定ウィンドウ
struct SettingsView: View {
    @Environment(AppController.self) private var controller
    @EnvironmentObject private var updaterViewModel: CheckForUpdatesViewModel
    @State private var launchAtLogin = false
    @State private var showImporter = false
    @State private var importError: String?

    var body: some View {
        @Bindable var controller = controller

        TabView {
            // General タブ
            Form {
                if controller.needsPermission {
                    Section("Permissions") {
                        Text("Grant Input Monitoring permission to enable global typing sounds.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button("Grant Permission") {
                                controller.requestInputMonitoringPermission()
                            }
                            Button("Open System Settings") {
                                controller.openInputMonitoringSettings()
                            }
                        }
                    }
                }

                Section("Audio") {
                    HStack {
                        Text("Volume")
                        Slider(value: $controller.volume, in: 0...1)
                        Text("\(Int(controller.volume * 100))%")
                            .monospacedDigit()
                            .frame(width: 40)
                    }

                    HStack {
                        Text("Pitch Variation")
                        Slider(value: $controller.pitchVariation, in: 0...0.2)
                        Text("\(Int(controller.pitchVariation * 100))%")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                }

                Section("Behavior") {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            setLaunchAtLogin(newValue)
                        }

                    Toggle("Play sounds on key repeat", isOn: .constant(true))
                }

                Section("Updates") {
                    Button("Check for Updates…") {
                        updaterViewModel.checkForUpdates()
                    }
                    .disabled(!updaterViewModel.canCheckForUpdates)
                }
            }
            .tabItem { Label("General", systemImage: "gear") }
            .tag(0)

            // Sound Packs タブ
            VStack(spacing: 0) {
                List {
                    ForEach(controller.soundPackManager.availablePacks) { pack in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(pack.name)
                                    .font(.headline)
                                Text(pack.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("by \(pack.author)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            if pack.id == controller.selectedSoundPackID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            controller.selectedSoundPackID = pack.id
                        }
                    }
                }

                Divider()

                HStack {
                    Button("Import Sound Pack...") {
                        showImporter = true
                    }

                    if let error = importError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Spacer()
                }
                .padding(12)
            }
            .tabItem { Label("Sound Packs", systemImage: "waveform") }
            .tag(1)

            VStack(alignment: .leading, spacing: 12) {
                GroupBox("Permissions") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Input Monitoring")
                            Spacer()
                            Text(controller.inputMonitoringGranted ? "Granted" : "Missing")
                                .foregroundStyle(controller.inputMonitoringGranted ? .green : .orange)
                        }
                        HStack {
                            Text("Accessibility")
                            Spacer()
                            Text(controller.accessibilityGranted ? "Granted" : "Missing")
                                .foregroundStyle(controller.accessibilityGranted ? .green : .orange)
                        }
                        HStack {
                            Button("Request Input Monitoring") {
                                controller.requestInputMonitoringPermission()
                            }
                            Button("Request Accessibility") {
                                controller.requestAccessibilityPermission()
                            }
                        }
                        HStack {
                            Button("Open Input Settings") {
                                controller.openInputMonitoringSettings()
                            }
                            Button("Open Accessibility Settings") {
                                controller.openAccessibilitySettings()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Runtime") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Listening: \(controller.isListening ? "Yes" : "No")")
                        Text("Backend: \(controller.monitorBackend.rawValue)")
                        Text("Last Key: \(controller.lastKeyEventSummary)")
                        Text("Events: \(controller.keyEventsReceived)  /  Played: \(controller.soundsPlayed)")
                        Text("Preview Plays: \(controller.previewPlays)  /  Repeat Skips: \(controller.skippedRepeats)")
                        Text("Missing Buffers: \(controller.missingBufferEvents)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Button("Refresh Diagnostics") {
                        controller.refreshDiagnostics()
                    }
                    Button("Clear Logs") {
                        controller.clearDiagnostics()
                    }
                    Spacer()
                }

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if controller.diagnosticLogs.isEmpty {
                            Text("No logs yet.")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            ForEach(controller.diagnosticLogs) { entry in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Text(entry.level.rawValue)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(levelColor(entry.level))
                                        .frame(width: 36, alignment: .leading)
                                    Text(entry.message)
                                        .font(.caption)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .tabItem { Label("Diagnostics", systemImage: "ladybug") }
            .tag(2)
        }
        .frame(width: 480, height: 360)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.zip, .folder],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 失敗時はUI状態を元に戻す
            launchAtLogin = !enabled
            importError = "Failed to change launch at login: \(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                _ = try controller.soundPackManager.importPack(from: url)
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func levelColor(_ level: DiagnosticLevel) -> Color {
        switch level {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
