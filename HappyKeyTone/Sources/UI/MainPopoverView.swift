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

            // 権限ガイドバナー
            if controller.needsPermission {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "keyboard.badge.eye")
                            .font(.title3)
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Permission Required")
                                .font(.caption.bold())
                            Text("Enable keyboard monitoring to hear typing sounds.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Button {
                            controller.showOnboardingWindowIfNeeded()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "questionmark.circle")
                                Text("Setup Guide")
                            }
                        }
                        .controlSize(.small)

                        Button {
                            controller.requestInputMonitoringPermission()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "gear")
                                Text("Open Settings")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

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
