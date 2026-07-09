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
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = DictationCoordinator()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var phaseObserver: AnyCancellable?
    private var recordingAnimationTimer: Timer?
    private var recordingAnimationFrame = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard claimSingleRunningInstance() else { return }

        configureMainMenu()
        configureStatusItem()
        configurePopover()
        observeDictationPhase()
        coordinator.onRecordingStarted = { [weak self] in
            self?.popover.performClose(nil)
        }
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopRecordingStatusAnimation()
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
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
        self.statusItem = statusItem
        updateStatusItem(for: coordinator.phase)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 740)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(coordinator: coordinator)
        )
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
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

        NSApp.mainMenu = mainMenu
    }

    private func observeDictationPhase() {
        phaseObserver = coordinator.$phase
            .sink { [weak self] phase in
                self?.updateStatusItem(for: phase)
            }
    }

    private func updateStatusItem(for phase: DictationPhase) {
        switch phase {
        case .recording:
            startRecordingStatusAnimation()
        default:
            stopRecordingStatusAnimation()
            setStatusItem(symbolName: statusItemSymbolName(for: phase), title: "")
        }
    }

    private func startRecordingStatusAnimation() {
        guard recordingAnimationTimer == nil else { return }

        recordingAnimationFrame = 0
        updateRecordingStatusAnimationFrame()
        recordingAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateRecordingStatusAnimationFrame()
            }
        }
    }

    private func stopRecordingStatusAnimation() {
        recordingAnimationTimer?.invalidate()
        recordingAnimationTimer = nil
        recordingAnimationFrame = 0
    }

    private func updateRecordingStatusAnimationFrame() {
        let frames: [(symbolName: String, title: String)] = [
            ("mic.circle.fill", " REC"),
            ("record.circle.fill", " REC."),
            ("mic.circle.fill", " REC.."),
            ("waveform.circle.fill", " REC...")
        ]
        let frame = frames[recordingAnimationFrame % frames.count]
        recordingAnimationFrame += 1
        setStatusItem(symbolName: frame.symbolName, title: frame.title)
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

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
