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

    /// Captures the frontmost external application synchronously via NSWorkspace.
    /// Cheap in-process lookup only — does not touch the Accessibility API, so it never
    /// blocks on a cross-process round trip to a busy app.
    func captureTargetApplication() -> NSRunningApplication? {
        let current = NSWorkspace.shared.frontmostApplication
        let application = isExternalApplication(current) ? current : nil
        if let application {
            update(with: application)
            return application
        }
        return lastExternalApplication
    }

    /// Reads the focused window title for `application` via the Accessibility API.
    /// This performs up to two cross-process AXUIElementCopyAttributeValue round trips,
    /// so it runs detached off the main actor and only hops back to deliver the result —
    /// callers should await it from within their own async work, not on the synchronous
    /// recording-start path, since a busy target app can make it stall.
    nonisolated func windowTitle(for application: NSRunningApplication?) async -> String? {
        guard let application else { return nil }
        return await Task.detached {
            Self.focusedWindowTitle(for: application)
        }.value
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
    /// it never throws. Static and nonisolated: AXUIElementCopyAttributeValue is
    /// thread-safe, and this holds no reference to tracker state, so it is safe to
    /// invoke off the main actor from `windowTitle(for:)`.
    private nonisolated static func focusedWindowTitle(for application: NSRunningApplication) -> String? {
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
