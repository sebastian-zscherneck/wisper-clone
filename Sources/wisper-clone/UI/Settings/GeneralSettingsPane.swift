import SwiftUI

struct GeneralSettingsPane: View {
    @ObservedObject var coordinator: DictationCoordinator

    var body: some View {
        Form {
            shortcutsSection
            microphoneSection
        }
    }

    private var shortcutsSection: some View {
        Section {
            ForEach(Array(coordinator.preferences.hotkeys.enumerated()), id: \.element) { index, binding in
                LabeledContent(index == 0 ? "Dictation" : "Dictation (alternative)") {
                    HStack {
                        HotkeyRecorderField(
                            coordinator: coordinator,
                            display: binding.displayName,
                            target: .dictation(index: index)
                        )
                        Button {
                            coordinator.removeDictationHotkey(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove shortcut")
                        .disabled(coordinator.preferences.hotkeys.count <= 1)
                    }
                }
            }

            Button("Add Dictation Shortcut…") {
                coordinator.beginHotkeyCapture(for: .dictation(index: nil))
            }
            .disabled(coordinator.hotkeyCaptureTarget != nil)

            LabeledContent("Command Mode") {
                HStack {
                    HotkeyRecorderField(
                        coordinator: coordinator,
                        display: coordinator.preferences.commandHotkey?.displayName ?? "Off",
                        target: .command
                    )
                    Button {
                        coordinator.setCommandHotkey(nil)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Turn off Command Mode shortcut")
                    .disabled(coordinator.preferences.commandHotkey == nil)
                }
            }
        } header: {
            Text("Keyboard Shortcuts")
        } footer: {
            if coordinator.isGlobalShortcutReady {
                Text("Hold to dictate, release to paste. Double-tap for hands-free, Esc cancels.")
            } else {
                Label(
                    "Shortcuts need Input Monitoring. Allow it under Privacy & Permissions.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }
        }
    }

    private var microphoneSection: some View {
        Section {
            Picker(
                "Input device",
                selection: Binding(
                    get: { coordinator.preferences.selectedInputDeviceID ?? "" },
                    set: { coordinator.setSelectedInputDeviceID($0.isEmpty ? nil : $0) }
                )
            ) {
                Text("Automatic").tag("")
                ForEach(coordinator.inputDevices) { device in
                    Text(device.displayName).tag(device.id)
                }
            }
        } header: {
            Text("Microphone")
        } footer: {
            if selectedInputDevice?.isBluetoothLike == true {
                Label("Bluetooth microphones can reduce AirPods music quality.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var selectedInputDevice: AudioInputDevice? {
        guard let selectedInputDeviceID = coordinator.preferences.selectedInputDeviceID else {
            return nil
        }
        return coordinator.inputDevices.first { $0.id == selectedInputDeviceID }
    }
}
