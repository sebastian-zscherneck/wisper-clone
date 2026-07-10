import AppKit
import Foundation

@MainActor
protocol SelectedTextCapturing {
    func captureSelectedText() async throws -> String?
}

@MainActor
struct SelectedTextCapturer: SelectedTextCapturing {
    func captureSelectedText() async throws -> String? {
        let promptOptions = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(promptOptions) else {
            throw DictationError.accessibilityDenied
        }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        let baselineChangeCount = pasteboard.changeCount

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) else {
            restore(previous, pasteboard: pasteboard)
            throw DictationError.pasteFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        var captured: String?
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(50))
            if pasteboard.changeCount != baselineChangeCount {
                captured = pasteboard.string(forType: .string)
                break
            }
        }

        restore(previous, pasteboard: pasteboard)

        guard let trimmed = captured?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func restore(_ previous: String?, pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if let previous {
            pasteboard.setString(previous, forType: .string)
        }
    }
}
