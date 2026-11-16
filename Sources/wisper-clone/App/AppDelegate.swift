import AppKit
import Combine
import SwiftUI

@main
struct WisperCloneMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let coordinator = DictationCoordinator()
    private var statusItem: NSStatusItem?
    private lazy var hubWindowController = HubWindowController(coordinator: coordinator)
    private var dockPreferenceObserver: AnyCancellable?
    private var phaseObserver: AnyCancellable?
    private var menuBarIconObserver: AnyCancellable?
    private lazy var flowBarController = FlowBarController(coordinator: coordinator)
    private var flowBarPreferencesObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard claimSingleRunningInstance() else { return }

        configureMainMenu()
        configureStatusItem()
        observeDictationPhase()
        observeFlowBarPreference()
        observeDockPreference()
        observeMenuBarIconPreference()
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
        coordinator.cancelRecording()
    }

    private func claimSingleRunningInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return true
        }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let existingInstance = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { runningApplication in
                runningApplication.processIdentifier != currentProcessIdentifier
                    && !runningApplication.isTerminated
            }

        guard let existingInstance else {
            return true
        }

        existingInstance.activate(from: .current, options: [])
        NSApp.terminate(nil)
        return false
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        self.statusItem = statusItem
        updateStatusItem(for: coordinator.phase)
    }

    // MARK: - Dock

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showHub(nil)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func observeDockPreference() {
        dockPreferenceObserver = coordinator.$preferences
            .map(\.showInDock)
            .removeDuplicates()
            .sink { [weak self] showInDock in
                self?.applyDockVisibility(showInDock)
            }
    }

    private func applyDockVisibility(_ showInDock: Bool) {
        let hubWasVisible = hubWindowController.window?.isVisible == true
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        // Switching to an accessory app sends its windows behind the others.
        if hubWasVisible {
            hubWindowController.show()
        }
    }

    @objc private func showHub(_ sender: Any?) {
        hubWindowController.show(section: .home)
    }

    @objc private func showSettings(_ sender: Any?) {
        hubWindowController.show(settings: true)
    }

    // MARK: - Status menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        coordinator.refreshInputDevices()
        menu.removeAllItems()

        let status = NSMenuItem(title: coordinator.statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if coordinator.phase == .recording {
            menu.addItem(item("Stop Dictation", #selector(stopDictation(_:))))
            menu.addItem(item("Cancel Dictation", #selector(cancelDictation(_:))))
        } else {
            let start = item("Start Dictation", #selector(startDictation(_:)))
            start.isEnabled = coordinator.phase == .idle || coordinator.phase == .failed
            menu.addItem(start)
        }
        let paste = item("Paste Last Transcript", #selector(pasteLastTranscript(_:)))
        let copy = item("Copy Last Transcript", #selector(copyLastTranscript(_:)))
        paste.isEnabled = !coordinator.lastTranscript.isEmpty
        copy.isEnabled = !coordinator.lastTranscript.isEmpty
        menu.addItem(paste)
        menu.addItem(copy)
        menu.addItem(.separator())

        menu.addItem(submenuItem("Microphone", items: microphoneMenuItems()))
        menu.addItem(submenuItem("AI Cleanup", items: cleanupMenuItems()))
        menu.addItem(.separator())

        menu.addItem(item("Open Wisper Clone", #selector(showHub(_:))))
        let settings = item("Settings…", #selector(showSettings(_:)))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit Wisper Clone", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func submenuItem(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false
        items.forEach(submenu.addItem)
        parent.submenu = submenu
        return parent
    }

    private func microphoneMenuItems() -> [NSMenuItem] {
        let selectedID = coordinator.preferences.selectedInputDeviceID
        let automatic = item("Automatic", #selector(selectMicrophone(_:)))
        automatic.state = selectedID == nil ? .on : .off
        let devices = coordinator.inputDevices.map { device in
            let deviceItem = item(device.displayName, #selector(selectMicrophone(_:)))
            deviceItem.representedObject = device.id
            deviceItem.state = selectedID == device.id ? .on : .off
            return deviceItem
        }
        return [automatic, .separator()] + devices
    }

    private func cleanupMenuItems() -> [NSMenuItem] {
        CleanupLevel.allCases.map { level in
            let levelItem = item(level.displayName, #selector(selectCleanupLevel(_:)))
            levelItem.representedObject = level.rawValue
            levelItem.state = coordinator.preferences.cleanupLevel == level ? .on : .off
            return levelItem
        }
    }

    @objc private func startDictation(_ sender: Any?) {
        coordinator.beginRecording()
    }

    @objc private func stopDictation(_ sender: Any?) {
        coordinator.finishRecording()
    }

    @objc private func cancelDictation(_ sender: Any?) {
        coordinator.cancelRecording()
    }

    @objc private func pasteLastTranscript(_ sender: Any?) {
        coordinator.retryLastPaste()
    }

    @objc private func copyLastTranscript(_ sender: Any?) {
        coordinator.copyLastTranscript()
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        coordinator.setSelectedInputDeviceID(sender.representedObject as? String)
    }

    @objc private func selectCleanupLevel(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let level = CleanupLevel(rawValue: rawValue) else { return }
        coordinator.setCleanupLevel(level)
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(title: "Hide Wisper Clone", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(
                title: "Quit Wisper Clone",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func observeDictationPhase() {
        phaseObserver = coordinator.$phase
            .sink { [weak self] phase in
                self?.updateStatusItem(for: phase)
            }
    }

    private func observeFlowBarPreference() {
        flowBarPreferencesObserver = coordinator.$preferences
            .map(\.flowBarVisibility)
            .combineLatest(coordinator.$phase)
            .map { visibility, phase in visibility.showsPanel(during: phase) }
            .removeDuplicates()
            .sink { [weak self] isVisible in
                if isVisible {
                    self?.flowBarController.show()
                } else {
                    self?.flowBarController.hide()
                }
            }
    }

    private func observeMenuBarIconPreference() {
        menuBarIconObserver = coordinator.$preferences
            .map(\.isMenuBarIconVisible)
            .removeDuplicates()
            .sink { [weak self] isVisible in
                self?.statusItem?.isVisible = isVisible
            }
    }

    /// The icon changes with the phase but stays a quiet, fixed-width symbol: no text and
    /// no animation in the menu bar. The Flow Bar is the place that shows a recording.
    private func updateStatusItem(for phase: DictationPhase) {
        setStatusItem(symbolName: statusItemSymbolName(for: phase), title: "")
    }

    private func setStatusItem(symbolName: String, title: String) {
        guard let button = statusItem?.button else { return }

        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: statusItemAccessibilityDescription
        ) ?? NSImage(
            systemSymbolName: "waveform.circle",
            accessibilityDescription: statusItemAccessibilityDescription
        )
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeft
        button.title = title
    }

    private func statusItemSymbolName(for phase: DictationPhase) -> String {
        switch phase {
        case .idle:
            return "waveform.circle"
        case .recording:
            return "mic.circle.fill"
        case .transcribing:
            return "arrow.triangle.2.circlepath.circle"
        case .pasting:
            return "arrow.down.doc"
        case .failed:
            return "exclamationmark.circle.fill"
        }
    }

    private var statusItemAccessibilityDescription: String {
        switch coordinator.phase {
        case .idle:
            return "Wisper Clone ready"
        case .recording:
            return "Wisper Clone recording"
        case .transcribing:
            return "Wisper Clone transcribing"
        case .pasting:
            return "Wisper Clone pasting"
        case .failed:
            return "Wisper Clone failed"
        }
    }


}
