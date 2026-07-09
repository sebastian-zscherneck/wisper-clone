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

    func captureTargetApplication() -> NSRunningApplication? {
        let current = NSWorkspace.shared.frontmostApplication
        if isExternalApplication(current) {
            update(with: current)
            return current
        }
        return lastExternalApplication
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
}
