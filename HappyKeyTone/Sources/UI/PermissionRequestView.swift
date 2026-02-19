import SwiftUI

/// Input Monitoring権限リクエストビュー（Settings画面用）
struct PermissionRequestView: View {
    @Environment(AppController.self) private var controller

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text("Permission Required")
                .font(.headline)

            Text("HappyKeyTone needs Input Monitoring or Accessibility permission to detect your keystrokes and play typing sounds.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Button("Request Input Monitoring") {
                    controller.requestInputMonitoringPermission()
                }
                .buttonStyle(.borderedProminent)

                Button("Request Accessibility") {
                    controller.requestAccessibilityPermission()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
    }
}
