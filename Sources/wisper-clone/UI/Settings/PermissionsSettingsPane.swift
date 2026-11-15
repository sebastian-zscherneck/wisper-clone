import SwiftUI

struct PermissionsSettingsPane: View {
    @ObservedObject var coordinator: DictationCoordinator

    var body: some View {
        Form {
            Section {
                permissionRow(
                    title: "Microphone",
                    detail: "Records your voice while you hold the shortcut.",
                    action: coordinator.openMicrophoneSettings
                )
                permissionRow(
                    title: "Input Monitoring",
                    detail: "Lets the global shortcut work in every app.",
                    action: coordinator.openInputMonitoringSettings
                )
                permissionRow(
                    title: "Accessibility",
                    detail: "Pastes the text into the app you are working in.",
                    action: coordinator.openAccessibilitySettings
                )
            } footer: {
                Text("macOS manages these permissions. The buttons open the matching page in System Settings.")
            }
        }
    }

    private func permissionRow(title: String, detail: String, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings…", action: action)
        }
    }
}
