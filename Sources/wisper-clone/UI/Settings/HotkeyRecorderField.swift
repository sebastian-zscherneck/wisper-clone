import SwiftUI

/// Click-to-record shortcut field. Shows the current binding and, while recording,
/// waits for the next key combination or mouse button.
struct HotkeyRecorderField: View {
    @ObservedObject var coordinator: DictationCoordinator
    let display: String
    let target: DictationCoordinator.HotkeyCaptureTarget

    var body: some View {
        let isRecording = coordinator.hotkeyCaptureTarget == target
        Button {
            if isRecording {
                coordinator.cancelHotkeyCapture()
            } else {
                coordinator.beginHotkeyCapture(for: target)
            }
        } label: {
            Text(isRecording ? "Press shortcut…" : display)
                .font(.callout.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(minWidth: 120)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isRecording ? Color.accentColor : Color.secondary.opacity(0.3))
                )
        }
        .buttonStyle(.plain)
        .help(isRecording ? "Press the keys or mouse button to assign (Esc cancels)" : "Click, then press your shortcut")
    }
}
