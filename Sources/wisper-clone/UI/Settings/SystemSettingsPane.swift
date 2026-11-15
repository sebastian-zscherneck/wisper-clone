import SwiftUI

struct SystemSettingsPane: View {
    @ObservedObject var coordinator: DictationCoordinator

    var body: some View {
        Form {
            Section {
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { coordinator.preferences.launchAtLogin },
                    set: { coordinator.setLaunchAtLogin($0) }
                )
            )
            Toggle(
                "Show Flow Bar at all times",
                isOn: Binding(
                    get: { coordinator.preferences.showFlowBar },
                    set: { coordinator.preferences.showFlowBar = $0 }
                )
            )
            Toggle(
                "Show app in Dock",
                isOn: Binding(
                    get: { coordinator.preferences.showInDock },
                    set: { coordinator.preferences.showInDock = $0 }
                )
            )
            Toggle(
                "Show icon in menu bar",
                isOn: Binding(
                    get: { coordinator.preferences.isMenuBarIconVisible },
                    set: { coordinator.preferences.showMenuBarIcon = $0 }
                )
            )
            .disabled(!coordinator.preferences.showInDock)
            Toggle(
                "Dictation sound effects",
                isOn: Binding(
                    get: { coordinator.preferences.enableSounds },
                    set: { coordinator.preferences.enableSounds = $0 }
                )
            )
            Toggle(
                "Haptic feedback on the trackpad",
                isOn: Binding(
                    get: { coordinator.preferences.enableHaptics },
                    set: { coordinator.preferences.enableHaptics = $0 }
                )
            )
            } footer: {
                Text("Without a Dock icon the menu bar icon stays visible, so the app remains reachable.")
            }
        }
    }
}
