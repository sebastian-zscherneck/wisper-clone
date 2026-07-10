import AppKit
import SwiftUI

/// Controls the floating "Flow Bar" panel shown at the bottom-center of the screen.
/// The panel never becomes key or steals focus from the frontmost application.
@MainActor
final class FlowBarController: NSObject {
    private static let panelSize = NSSize(width: 320, height: 64)

    private let panel: NSPanel

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

    func show() {
        reposition()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
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
