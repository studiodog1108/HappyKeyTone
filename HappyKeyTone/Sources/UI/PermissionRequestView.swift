import SwiftUI

/// 設定ウィンドウ用の権限リクエストセクション
struct PermissionRequestView: View {
    @Environment(AppController.self) private var controller

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard.badge.eye")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Permission Required")
                        .font(.headline)
                    Text("Grant one of the following to enable typing sounds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                SettingsPermissionRow(
                    title: "Input Monitoring",
                    isGranted: controller.inputMonitoringGranted,
                    isRecommended: true,
                    onOpen: { controller.requestInputMonitoringPermission() }
                )

                SettingsPermissionRow(
                    title: "Accessibility",
                    isGranted: controller.accessibilityGranted,
                    isRecommended: false,
                    onOpen: { controller.requestAccessibilityPermission() }
                )
            }
        }
        .padding(.vertical, 8)
    }
}

/// 設定画面用の権限行
private struct SettingsPermissionRow: View {
    let title: String
    let isGranted: Bool
    let isRecommended: Bool
    let onOpen: () -> Void

    var body: some View {
        HStack {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isGranted ? .green : .secondary)

            Text(title)
                .font(.callout)

            if isRecommended && !isGranted {
                Text("Recommended")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            Spacer()

            if isGranted {
                Text("Enabled")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Open Settings") {
                    onOpen()
                }
                .controlSize(.small)
            }
        }
    }
}
