import SwiftUI

/// 初回起動時のセットアップガイドウィンドウ
struct OnboardingView: View {
    @Environment(AppController.self) private var controller

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    explanationSection
                    permissionStatusSection
                    if !hasAnyPermission {
                        stepsSection
                    }
                    if hasAnyPermission {
                        successSection
                    }
                }
                .padding(32)
            }

            Divider()

            footerSection
        }
        .frame(width: 480, height: 560)
        .task {
            while !Task.isCancelled {
                controller.checkPermissions()
                if hasAnyPermission && controller.isEnabled && !controller.isListening {
                    controller.startEventTap()
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Welcome to HappyKeyTone")
                .font(.title2.bold())

            Text("Add delightful sounds to your typing experience")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - Explanation

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Keyboard Permission", systemImage: "keyboard.badge.eye")
                .font(.headline)

            Text(
                "HappyKeyTone needs permission to detect your keystrokes so it can play sounds as you type. Your keystrokes are never recorded or transmitted."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Permission Status

    private var permissionStatusSection: some View {
        VStack(spacing: 1) {
            OnboardingPermissionRow(
                title: "Input Monitoring",
                description: "Recommended — reliably detects all keystrokes",
                isGranted: controller.inputMonitoringGranted,
                isRecommended: true,
                onRequestPermission: {
                    controller.requestInputMonitoringPermission()
                }
            )

            OnboardingPermissionRow(
                title: "Accessibility",
                description: "Alternative — use if Input Monitoring is unavailable",
                isGranted: controller.accessibilityGranted,
                isRecommended: false,
                onRequestPermission: {
                    controller.requestAccessibilityPermission()
                }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to grant permission:")
                .font(.subheadline.bold())

            OnboardingStepRow(number: 1, text: "Click \"Open Settings\" next to Input Monitoring above")
            OnboardingStepRow(number: 2, text: "Find HappyKeyTone in the app list")
            OnboardingStepRow(number: 3, text: "Toggle the switch ON")
            OnboardingStepRow(
                number: 4, text: "If prompted to quit, click \"Later\" — it will take effect shortly"
            )

            Text("Only one permission is needed. Input Monitoring is recommended.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(16)
        .background(.blue.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Success

    private var successSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("You're all set!")
                    .font(.headline)
                Text("HappyKeyTone is ready to add sounds to your typing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            if !hasAnyPermission {
                Button("Skip for now") {
                    controller.completeOnboarding()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(hasAnyPermission ? "Get Started" : "Continue without sound") {
                controller.completeOnboarding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(20)
    }

    private var hasAnyPermission: Bool {
        controller.inputMonitoringGranted || controller.accessibilityGranted
    }
}

// MARK: - Sub Views

private struct OnboardingPermissionRow: View {
    let title: String
    let description: String
    let isGranted: Bool
    let isRecommended: Bool
    let onRequestPermission: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isGranted ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.body.weight(.medium))

                    if isRecommended && !isGranted {
                        Text("Recommended")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Text("Enabled")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button("Open Settings") {
                    onRequestPermission()
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(isGranted ? Color.green.opacity(0.04) : Color(.controlBackgroundColor))
    }
}

private struct OnboardingStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 20, height: 20)
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(Circle())

            Text(text)
                .font(.callout)
        }
    }
}
