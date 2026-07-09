import Foundation

/// Disambiguates hold-to-talk, single-tap, and double-tap gestures for a single logical
/// hotkey trigger. Clock-independent (injectable tap window) so it can be unit tested
/// without waiting on real hardware timing.
@MainActor
final class HotkeyGestureClassifier {
    var onPress: (() -> Void)? // Recording should start IMMEDIATELY (no latency).
    var onRelease: (() -> Void)? // finish/transcribe
    var onDoubleTap: (() -> Void)? // Lock hands-free mode (recording keeps running).

    private let tapWindow: Duration
    private var pressBeganAt: ContinuousClock.Instant?
    private var pendingReleaseTask: Task<Void, Never>?
    private var swallowNextRelease = false

    init(tapWindow: Duration = .milliseconds(350)) {
        self.tapWindow = tapWindow
    }

    func keyPressed() {
        if pendingReleaseTask != nil { // Second press within the tap window.
            pendingReleaseTask?.cancel()
            pendingReleaseTask = nil
            swallowNextRelease = true // The second tap's release is ignored.
            onDoubleTap?()
            return
        }
        pressBeganAt = .now
        onPress?()
    }

    func keyReleased() {
        if swallowNextRelease {
            swallowNextRelease = false
            return
        }
        guard let began = pressBeganAt else { return }
        pressBeganAt = nil
        if ContinuousClock.now - began < tapWindow {
            pendingReleaseTask = Task { [weak self] in // Wait for a possible second tap.
                try? await Task.sleep(for: self?.tapWindow ?? .milliseconds(350))
                guard !Task.isCancelled else { return }
                self?.pendingReleaseTask = nil
                self?.onRelease?() // Single short tap -> normal finish.
            }
        } else {
            onRelease?() // Normal hold-to-talk release.
        }
    }
}
