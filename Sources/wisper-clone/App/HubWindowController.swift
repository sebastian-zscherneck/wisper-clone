import AppKit
import SwiftUI

/// Hosts the main window. It opens from the menu bar, the Dock icon and ⌘,.
@MainActor
final class HubWindowController: NSWindowController {
    let navigation = HubNavigation()

    init(coordinator: DictationCoordinator) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Wisper Clone"
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: HubView(coordinator: coordinator, navigation: navigation)
        )
        window.setContentSize(NSSize(width: 960, height: 640))
        window.center()
        window.setFrameAutosaveName("HubWindow")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(section: HubSection? = nil, settings: Bool = false) {
        if let section {
            navigation.section = section
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        if settings {
            navigation.isSettingsPresented = true
        }
    }
}
