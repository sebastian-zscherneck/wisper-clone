import SwiftUI

struct SignaturePage: View {
    @ObservedObject var coordinator: DictationCoordinator

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Append automatically in the apps below",
                    isOn: Binding(
                        get: { coordinator.preferences.signature.isAutoAppendEnabled },
                        set: { coordinator.setSignatureAutoAppendEnabled($0) }
                    )
                )
                TextField(
                    "Text",
                    text: Binding(
                        get: { coordinator.preferences.signature.text },
                        set: { coordinator.setSignatureText($0) }
                    ),
                    prompt: Text("Made with WisprFlow")
                )
                Picker(
                    "Placement",
                    selection: Binding(
                        get: { coordinator.preferences.signature.separator },
                        set: { coordinator.setSignatureSeparator($0) }
                    )
                ) {
                    ForEach(SignatureSeparator.allCases) { separator in
                        Text(separator.displayName).tag(separator)
                    }
                }
            }

            Section {
                LabeledContent("Toggle shortcut") {
                    HStack {
                        HotkeyRecorderField(
                            coordinator: coordinator,
                            display: coordinator.preferences.signatureHotkey?.displayName ?? "Off",
                            target: .signature
                        )
                        Button {
                            coordinator.setSignatureHotkey(nil)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Turn off signature shortcut")
                        .disabled(coordinator.preferences.signatureHotkey == nil)
                    }
                }
                if let signatureOverride = coordinator.signatureOverride {
                    LabeledContent(signatureOverride ? "Next dictation: signature on" : "Next dictation: signature off") {
                        Button("Reset") {
                            coordinator.toggleSignatureOverride()
                        }
                    }
                }
            } footer: {
                Text("The shortcut flips the decision for the next dictation only: on where it would be off, off where it would be on.")
            }

            Section {
                if coordinator.preferences.signature.apps.isEmpty {
                    Text("No apps selected. The signature is only added via the shortcut.")
                        .foregroundStyle(.secondary)
                }
                ForEach(coordinator.preferences.signature.apps) { app in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                            Text(app.bundleID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            coordinator.removeSignatureApp(app.bundleID)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(app.name)")
                    }
                }
                Menu("Add App…") {
                    ForEach(coordinator.availableSignatureApps()) { app in
                        Button(app.name) {
                            coordinator.addSignatureApp(app)
                        }
                    }
                }
                .fixedSize()
            } header: {
                Text("Apps")
            }
        }
    }
}
