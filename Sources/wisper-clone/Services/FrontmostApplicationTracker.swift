import AppKit
import Foundation

@MainActor
final class FrontmostApplicationTracker {
    private var lastExternalApplication: NSRunningApplication?
    private let ownProcessIdentifier = NSRunningApplication.current.processIdentifier

    init() {
        update(with: NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostApplicationDidChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func captureTargetApplication() -> (application: NSRunningApplication?, windowTitle: String?) {
        let current = NSWorkspace.shared.frontmostApplication
        let application = isExternalApplication(current) ? current : nil
        if let application {
            update(with: application)
            return (application, focusedWindowTitle(for: application))
        }
        return (lastExternalApplication, focusedWindowTitle(for: lastExternalApplication))
    }

    func activate(_ application: NSRunningApplication?) async {
        guard let application else { return }
        if #available(macOS 14.0, *) {
            application.activate()
        } else {
            application.activate(options: [.activateIgnoringOtherApps])
        }
        try? await Task.sleep(for: .milliseconds(180))
    }

    @objc private func frontmostApplicationDidChange(_ notification: Notification) {
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        update(with: application)
    }

    private func update(with application: NSRunningApplication?) {
        guard isExternalApplication(application) else { return }
        lastExternalApplication = application
    }

    private func isExternalApplication(_ application: NSRunningApplication?) -> Bool {
        guard let application else { return false }
        guard application.processIdentifier != ownProcessIdentifier else { return false }
        return !application.isTerminated
    }

    /// Reads the title of the target app's focused window via the Accessibility API.
    /// Best-effort only: missing Accessibility permission or any AX failure yields nil,
    /// it never throws.
    private func focusedWindowTitle(for application: NSRunningApplication?) -> String? {
        guard let application else { return nil }

        let axApplication = AXUIElementCreateApplication(application.processIdentifier)
        var focusedWindow: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(
            axApplication,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        guard windowResult == .success, let focusedWindow else { return nil }
        guard CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() else { return nil }
        let axWindow = focusedWindow as! AXUIElement // swiftlint:disable:this force_cast

        var titleValue: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleValue)
        guard titleResult == .success, let title = titleValue as? String, !title.isEmpty else { return nil }
        return title
    }
}
