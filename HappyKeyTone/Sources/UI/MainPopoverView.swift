import SwiftUI

/// メニューバーポップオーバーのメインビュー
struct MainPopoverView: View {
    @Environment(AppController.self) private var controller

    var body: some View {
        @Bindable var controller = controller

        VStack(spacing: 16) {
            // ヘッダー
            HStack {
                Text("HappyKeyTone")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $controller.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            // エラーバナー
            if let error = controller.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        controller.dismissError()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // 権限警告バナー（非ブロッキング）
            if controller.needsPermission {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Input Monitoring Required")
                            .font(.caption.bold())
                        Text("Grant Input Monitoring or Accessibility permission.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Input") {
                        controller.requestInputMonitoringPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("AX") {
                        controller.requestAccessibilityPermission()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(8)
                .background(.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Monitor: \(controller.monitorBackend.rawValue)")
                Text("Input: \(controller.inputMonitoringGranted ? "Granted" : "Missing")  |  Accessibility: \(controller.accessibilityGranted ? "Granted" : "Missing")")
                Text("Events: \(controller.keyEventsReceived)  |  Played: \(controller.soundsPlayed)  |  Preview: \(controller.previewPlays)")
                if let latest = controller.diagnosticLogs.first {
                    Text("[\(latest.level.rawValue)] \(latest.message)")
                        .lineLimit(2)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Divider()

            // 音量スライダー
            VStack(alignment: .leading, spacing: 8) {
                Text("Volume")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.secondary)
                    Slider(value: $controller.volume, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.secondary)
                }
            }

            // サウンドパック選択
            VStack(alignment: .leading, spacing: 8) {
                Text("Sound Pack")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("", selection: $controller.selectedSoundPackID) {
                    ForEach(controller.soundPackManager.availablePacks) { pack in
                        Text(pack.name).tag(pack.id)
                    }
                }
                .labelsHidden()
            }

            // ピッチ変動
            VStack(alignment: .leading, spacing: 8) {
                Text("Pitch Variation")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Slider(value: $controller.pitchVariation, in: 0...0.2)
            }

            Divider()

            // フッターアクション
            HStack {
                // ステータスインジケーター
                HStack(spacing: 4) {
                    Circle()
                        .fill(controller.isListening ? .green : .orange)
                        .frame(width: 6, height: 6)
                    Text(controller.isListening ? "Active" : "Inactive")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button("Test Sound") {
                    controller.playPreviewSound()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                Button("Refresh") {
                    controller.refreshDiagnostics()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                Spacer()

                if #available(macOS 13.0, *) {
                    SettingsLink {
                        Text("Settings...")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                } else {
                    Text("Settings...")
                        .foregroundStyle(.secondary)
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
    }
}
