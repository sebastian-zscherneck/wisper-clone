import SwiftUI

/// The floating pill shown at the bottom of the screen. One capsule morphs between states:
/// - Idle: a small outlined capsule.
/// - Hold to dictate: a compact capsule with the live waveform.
/// - Hands-free (double-tap): the waveform sits between a cancel and a confirm button,
///   because there is no key release that would end the dictation.
/// - Transcribing: a slightly wider capsule with resting dots and a spinner.
struct FlowBarView: View {
    @ObservedObject var coordinator: DictationCoordinator
    @State private var isHovering = false

    private enum Mode: Equatable {
        case idle
        case hint
        case hold
        case handsFree
        case busy
        case failed
    }

    private static let barCount = 10
    private static let pillHeight: CGFloat = 28
    private static let morph = Animation.spring(response: 0.32, dampingFraction: 0.82)
    private static let confirmColor = Color(red: 0.2, green: 0.78, blue: 0.45)

    var body: some View {
        pill
            .onHover { isHovering = $0 }
            .animation(Self.morph, value: mode)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var mode: Mode {
        switch coordinator.phase {
        case .idle:
            return isHovering ? .hint : .idle
        case .recording:
            return coordinator.isHandsFreeActive ? .handsFree : .hold
        case .transcribing, .pasting:
            return .busy
        case .failed:
            return .failed
        }
    }

    private var pill: some View {
        content
            .frame(width: fixedWidth, height: mode == .idle ? 8 : Self.pillHeight)
            .padding(.horizontal, fixedWidth == nil ? 12 : 0)
            .background(Color.black.opacity(mode == .idle ? 0.55 : 0.92), in: Capsule())
            .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: mode == .idle ? 2 : 5, y: 1)
    }

    /// Text states size themselves; every other state has a fixed width so the capsule
    /// can animate between them.
    private var fixedWidth: CGFloat? {
        switch mode {
        case .idle: return 40
        case .hold: return 72
        case .handsFree: return 124
        case .busy: return 96
        case .hint, .failed: return nil
        }
    }

    private var borderColor: Color {
        switch mode {
        case .idle:
            return .white.opacity(0.65)
        case .failed:
            return .red
        default:
            return coordinator.isCommandRecording ? Color.indigo : .white.opacity(0.18)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .idle:
            Color.clear
        case .hint:
            label("Hold \(firstHotkeyDisplayName) to dictate")
        case .hold:
            waveform
                .transition(.opacity)
        case .handsFree:
            HStack(spacing: 0) {
                roundButton(symbol: "xmark", foreground: .black, background: .white, help: "Cancel dictation") {
                    coordinator.cancelRecording()
                }
                Spacer(minLength: 0)
                waveform
                Spacer(minLength: 0)
                roundButton(symbol: "checkmark", foreground: .white, background: Self.confirmColor, help: "Finish and paste") {
                    coordinator.finishRecording()
                }
            }
            .padding(.horizontal, 4)
            .transition(.opacity)
        case .busy:
            HStack(spacing: 8) {
                restingDots
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .colorScheme(.dark)
            }
            .transition(.opacity)
        case .failed:
            label(coordinator.statusText)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .transition(.opacity)
    }

    private func roundButton(
        symbol: String,
        foreground: Color,
        background: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: 20, height: 20)
                .background(background, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Waveform

    /// Ten bars that ripple outward from the centre and sway while there is sound.
    private var waveform: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let levels = WaveformLevels.barLevels(
                samples: coordinator.audioLevels,
                barCount: Self.barCount,
                time: timeline.date.timeIntervalSinceReferenceDate
            )
            HStack(spacing: 2.5) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 2, height: 2 + levels[index] * 14)
                }
            }
            .frame(height: 16)
            .animation(.easeOut(duration: 0.1), value: levels)
        }
    }

    private var restingDots: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<Self.barCount, id: \.self) { _ in
                Capsule()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 2, height: 2)
            }
        }
    }

    private var firstHotkeyDisplayName: String {
        coordinator.preferences.hotkeys.first?.displayName ?? "your shortcut"
    }
}
