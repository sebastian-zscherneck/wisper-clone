import AppKit
import SwiftUI

/// Controls the floating "Flow Bar" panel shown at the bottom-center of the screen.
/// The panel never becomes key or steals focus from the frontmost application.
@MainActor
final class FlowBarController: NSObject {
    private static let panelSize = NSSize(width: 320, height: 64)

    private static let fadeOutDuration: TimeInterval = 0.15

    private let panel: NSPanel
    private var visibilityGeneration = 0

    init(coordinator: DictationCoordinator) {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView = NSHostingView(rootView: FlowBarView(coordinator: coordinator))
        self.panel = panel
        super.init()

        reposition()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Appears at once: the hotkey press must be visible in the same frame. Only leaving
    /// is animated, so a finished dictation does not vanish abruptly.
    func show() {
        visibilityGeneration += 1
        reposition()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
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
