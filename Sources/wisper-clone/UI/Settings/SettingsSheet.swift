import SwiftUI

/// The sections of the settings, in sidebar order.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case system
    case models
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .system: return "System"
        case .models: return "Transcription & AI"
        case .permissions: return "Privacy & Permissions"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .system: return "macwindow"
        case .models: return "waveform"
        case .permissions: return "hand.raised"
        }
    }
}

/// Settings, shown as a sheet over the main window.
struct SettingsSheet: View {
    @ObservedObject var coordinator: DictationCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var selection: SettingsPane = .general

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.headline)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                ForEach(SettingsPane.allCases) { pane in
                    Button {
                        selection = pane
                    } label: {
                        Label(pane.title, systemImage: pane.symbolName)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                selection == pane ? Color.accentColor.opacity(0.16) : .clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(14)
            .frame(width: 210)
            .background(.background.secondary)

            Divider()

            VStack(spacing: 0) {
                HStack {
                    Text(selection.title)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 4)

                pane
                    .formStyle(.grouped)
            }
        }
        .frame(width: 760, height: 520)
        .onDisappear {
            coordinator.cancelHotkeyCapture()
        }
    }

    @ViewBuilder
    private var pane: some View {
        switch selection {
        case .general:
            GeneralSettingsPane(coordinator: coordinator)
        case .system:
            SystemSettingsPane(coordinator: coordinator)
        case .models:
            ModelsSettingsPane(coordinator: coordinator)
        case .permissions:
            PermissionsSettingsPane(coordinator: coordinator)
        }
    }
}
