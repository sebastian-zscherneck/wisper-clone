import AppKit
import SwiftUI

/// Controls the floating "Flow Bar" panel shown at the bottom-center of the screen.
/// The panel never becomes key or steals focus from the frontmost application.
@MainActor
final class FlowBarController: NSObject {
    private static let panelSize = NSSize(width: 320, height: 64)

    private static let fadeOutDuration: TimeInterval = 0.15

    /// How long the window server may take to put a freshly ordered panel on screen.
    private static let onscreenCheckDelay: TimeInterval = 0.5

    private let coordinator: DictationCoordinator
    private var panel: NSPanel
    private var visibilityGeneration = 0

    init(coordinator: DictationCoordinator) {
        self.coordinator = coordinator
        self.panel = Self.makePanel(coordinator: coordinator)
        super.init()

        reposition()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleActiveSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    private static func makePanel(coordinator: DictationCoordinator) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Before `level`: becoming a floating panel resets the level to `.floating`.
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView = NSHostingView(rootView: FlowBarView(coordinator: coordinator))
        return panel
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Appears at once: the hotkey press must be visible in the same frame. Only leaving
    /// is animated, so a finished dictation does not vanish abruptly.
    func show() {
        visibilityGeneration += 1
        reposition()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        verifyOnscreen(generation: visibilityGeneration)
    }

    /// Safety net for a panel pinned to another Space (see `handleActiveSpaceChanged`):
    /// a panel still off screen shortly after show() is replaced.
    private func verifyOnscreen(generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.onscreenCheckDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.visibilityGeneration == generation,
                      !self.isPanelOnscreen() else { return }
                self.replacePanel()
                self.panel.orderFrontRegardless()
            }
        }
    }

    private func replacePanel() {
        panel.orderOut(nil)
        panel = Self.makePanel(coordinator: coordinator)
        reposition()
    }

    private func isPanelOnscreen() -> Bool {
        let windowID = CGWindowID(panel.windowNumber)
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID)
            as? [[String: Any]] else { return false }
        return info.first?[kCGWindowIsOnscreen as String] as? Bool ?? false
    }

    func hide() {
        guard panel.isVisible else { return }
        visibilityGeneration += 1
        let generation = visibilityGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOutDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A new show() during the fade wins.
                guard let self, self.visibilityGeneration == generation else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    @objc private func handleScreenParametersChanged() {
        reposition()
    }

    /// When a full-screen Space closes, macOS pins a `canJoinAllSpaces` panel to the one
    /// Space it falls back to, and the panel stays invisible on every other Space. A new
    /// window joins all Spaces again; a visible panel is left to `verifyOnscreen`.
    @objc private func handleActiveSpaceChanged() {
        guard !panel.isVisible else { return }
        replacePanel()
    }

    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 16
        )
        panel.setFrameOrigin(origin)
    }
}
