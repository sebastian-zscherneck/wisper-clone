import SwiftUI

/// The floating pill shown at the bottom of the screen while dictating.
/// Purely informational — it never intercepts clicks to start/stop recording.
struct FlowBarView: View {
    @ObservedObject var coordinator: DictationCoordinator
    @State private var isHovering = false

    var body: some View {
        content
            .onHover { hovering in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isHovering = hovering
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: coordinator.phase)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.phase {
        case .idle:
            idlePill
        case .recording:
            recordingPill
        case .transcribing, .pasting:
            busyPill
        case .failed:
            failedPill
        }
    }

    private var idlePill: some View {
        Group {
            if isHovering {
                expandedPill {
                    Text("Hold \(firstHotkeyDisplayName) to dictate")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
            } else {
                Capsule()
                    .fill(Color.black.opacity(0.65))
                    .frame(width: 56, height: 8)
                    .shadow(radius: 3)
            }
        }
    }

    private var recordingPill: some View {
        expandedPill {
            HStack(spacing: 8) {
                waveform
                if coordinator.isCommandRecording {
                    Image(systemName: "wand.and.stars")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
                if coordinator.isHandsFreeActive {
                    Image(systemName: "infinity")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
            }
        }
        .overlay(
            Capsule()
                .strokeBorder(recordingAccentColor.opacity(0.8), lineWidth: 1.5)
        )
    }

    private var busyPill: some View {
        expandedPill {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
        }
        .overlay(
            Capsule()
                .strokeBorder(coordinator.isCommandRecording ? Color.indigo.opacity(0.8) : Color.clear, lineWidth: 1.5)
        )
    }

    private var recordingAccentColor: Color {
        coordinator.isCommandRecording ? .indigo : .red
    }

    private var failedPill: some View {
        expandedPill {
            Text(coordinator.statusText)
                .font(.caption)
                .foregroundStyle(.white)
        }
        .overlay(
            Capsule()
                .strokeBorder(Color.red, lineWidth: 2)
        )
    }

    private var waveform: some View {
        HStack(spacing: 3) {
            ForEach(Array(waveformSamples.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(recordingAccentColor)
                    .frame(width: 3, height: max(4, CGFloat(level) * 24))
            }
        }
        .frame(height: 24)
    }

    private var waveformSamples: [Float] {
        Array(coordinator.audioLevels.suffix(20))
    }

    @ViewBuilder
    private func expandedPill<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .background(Color.black.opacity(0.4), in: Capsule())
            .shadow(radius: 6)
    }

    private var firstHotkeyDisplayName: String {
        coordinator.preferences.hotkeys.sorted { $0.rawValue < $1.rawValue }.first?.displayName ?? "your shortcut"
    }
}
