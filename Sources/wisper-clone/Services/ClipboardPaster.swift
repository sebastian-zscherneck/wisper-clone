import AppKit
import Foundation

@MainActor
protocol TextPasting {
    func paste(_ text: String) async throws
    func copy(_ text: String)
}

@MainActor
struct ClipboardPaster: TextPasting {
    func paste(_ text: String) async throws {
        let promptOptions = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(promptOptions) else {
            copy(text)
            throw DictationError.accessibilityDenied
        }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        copy(text)

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            throw DictationError.pasteFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        try? await Task.sleep(for: .milliseconds(250))

        if let previous {
            pasteboard.clearContents()
            pasteboard.setString(previous, forType: .string)
        }
    }

    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
