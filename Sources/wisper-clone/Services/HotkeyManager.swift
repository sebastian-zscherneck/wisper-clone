import AppKit
import Carbon.HIToolbox
import Foundation

@MainActor
final class HotkeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onDoubleTap: (() -> Void)?
    var onEscape: (() -> Void)?
    var onPasteLastShortcut: (() -> Void)?
    var onEventTapStatusChanged: ((Bool) -> Void)?
    var onCommandPress: (() -> Void)?
    var onCommandRelease: (() -> Void)?

    private var hotkeys: Set<Hotkey>
    private var commandHotkey: Hotkey?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitors: [Any] = []
    private var localMonitors: [Any] = []
    private var activeTriggers: Set<Hotkey> = []
    private var commandIsPressed = false
    private var isEventTapActive = false
    private let gestureClassifier = HotkeyGestureClassifier()

    init(hotkeys: Set<Hotkey>) {
        self.hotkeys = hotkeys
        gestureClassifier.onPress = { [weak self] in self?.onPress?() }
        gestureClassifier.onRelease = { [weak self] in self?.onRelease?() }
        gestureClassifier.onDoubleTap = { [weak self] in self?.onDoubleTap?() }
    }

    func update(hotkeys: Set<Hotkey>) {
        self.hotkeys = hotkeys
        activeTriggers = []
    }

    func update(commandHotkey: Hotkey?) {
        self.commandHotkey = commandHotkey
        commandIsPressed = false
    }

    func start() {
        stop()
        startEventTap()
        addLocalMonitor(mask: [.flagsChanged, .keyDown, .keyUp, .otherMouseDown, .otherMouseUp])
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        for monitor in globalMonitors {
            NSEvent.removeMonitor(monitor)
        }
        for monitor in localMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventTap = nil
        runLoopSource = nil
        globalMonitors = []
        localMonitors = []
        activeTriggers = []
        commandIsPressed = false
        isEventTapActive = false
        onEventTapStatusChanged?(false)
    }

    private func startEventTap() {
        let mask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: hotkeyEventTapCallback,
            userInfo: refcon
        ) else {
            _ = CGRequestListenEventAccess()
            isEventTapActive = false
            onEventTapStatusChanged?(false)
            addGlobalMonitor(mask: [.flagsChanged, .keyDown, .keyUp, .otherMouseDown, .otherMouseUp])
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        isEventTapActive = true
        onEventTapStatusChanged?(true)
    }

    private func addGlobalMonitor(mask: NSEvent.EventTypeMask) {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }) {
            globalMonitors.append(monitor)
        }
    }

    private func addLocalMonitor(mask: NSEvent.EventTypeMask) {
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            localMonitors.append(monitor)
        }
    }

    private func handle(_ event: NSEvent) {
        // Escape/paste-last are handled as plain keyDown, independent of the configured
        // hotkeys. The event tap is `.listenOnly`, so the event also still reaches the
        // frontmost app — an accepted limitation. When the tap is active it already
        // delivers these one-shot shortcuts; handling them here too would fire them twice
        // whenever this app is frontmost, so the NSEvent path only acts as the fallback.
        if event.type == .keyDown, !isEventTapActive {
            if event.keyCode == UInt16(kVK_Escape), event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                onEscape?()
                return
            }
            if event.keyCode == UInt16(kVK_ANSI_V), event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .control] {
                onPasteLastShortcut?()
                return
            }
        }

        if event.type == .flagsChanged {
            let flags = event.modifierFlags
            // .fnControl is evaluated before .fn: if both the command hotkey and a plain
            // Fn dictation hotkey are configured, the command role wins on this combined
            // gesture. The coordinator's busy guard then prevents dictation from also
            // starting once command recording has begun.
            update(trigger: .fnControl, pressed: flags.contains(.function) && flags.contains(.control))
            if hotkeys.contains(.fn) {
                update(trigger: .fn, pressed: flags.contains(.function))
            }
            return
        }

        if hotkeys.contains(.mouse5), event.type == .otherMouseDown || event.type == .otherMouseUp {
            handleMouse5(type: event.type, buttonNumber: event.buttonNumber)
            return
        }

        if hotkeys.contains(.optionSpace) {
            handleSpace(event, trigger: .optionSpace, requiredFlag: .option)
        }
        if hotkeys.contains(.controlSpace) {
            handleSpace(event, trigger: .controlSpace, requiredFlag: .control)
        }
    }

    // Internal (not fileprivate) so tests can drive this exact code path — the one the
    // real CGEventTap callback uses — via @testable import, without exposing it publicly.
    func handle(typeRawValue: UInt32, flagsRawValue: UInt64, keyCode: Int64, mouseButtonNumber: Int64) {
        guard let type = CGEventType(rawValue: typeRawValue) else { return }
        let flags = CGEventFlags(rawValue: flagsRawValue)

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                onEventTapStatusChanged?(true)
            }
        case .flagsChanged:
            // See the NSEvent path above for why .fnControl is checked before .fn.
            update(trigger: .fnControl, pressed: flags.contains(.maskSecondaryFn) && flags.contains(.maskControl))
            if hotkeys.contains(.fn) {
                update(trigger: .fn, pressed: flags.contains(.maskSecondaryFn))
            }
        case .keyDown, .keyUp:
            // Escape/paste-last are handled as plain keyDown only (no release tracking needed).
            if type == .keyDown {
                // Mirror the NSEvent path's .deviceIndependentFlagsMask semantics.
                let deviceIndependentFlags = flags.intersection(
                    [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn, .maskAlphaShift]
                )
                if keyCode == Int64(kVK_Escape), deviceIndependentFlags.isEmpty {
                    onEscape?()
                    return
                }
                if keyCode == Int64(kVK_ANSI_V), deviceIndependentFlags == [.maskCommand, .maskControl] {
                    onPasteLastShortcut?()
                    return
                }
            }
            if hotkeys.contains(.optionSpace) {
                handleSpace(type: type, flags: flags, keyCode: keyCode, trigger: .optionSpace, requiredFlag: .maskAlternate)
            }
            if hotkeys.contains(.controlSpace) {
                handleSpace(type: type, flags: flags, keyCode: keyCode, trigger: .controlSpace, requiredFlag: .maskControl)
            }
        case .otherMouseDown, .otherMouseUp:
            if hotkeys.contains(.mouse5) {
                handleMouse5(type: type, buttonNumber: mouseButtonNumber)
            }
        default:
            break
        }
    }

    private func handleSpace(_ event: NSEvent, trigger: Hotkey, requiredFlag: NSEvent.ModifierFlags) {
        guard event.keyCode == UInt16(kVK_Space) else { return }

        switch event.type {
        case .keyDown where event.modifierFlags.contains(requiredFlag):
            update(trigger: trigger, pressed: true)
        case .keyUp:
            update(trigger: trigger, pressed: false)
        default:
            break
        }
    }

    private func handleSpace(type: CGEventType, flags: CGEventFlags, keyCode: Int64, trigger: Hotkey, requiredFlag: CGEventFlags) {
        guard keyCode == Int64(kVK_Space) else { return }

        switch type {
        case .keyDown where flags.contains(requiredFlag):
            update(trigger: trigger, pressed: true)
        case .keyUp:
            update(trigger: trigger, pressed: false)
        default:
            break
        }
    }

    private func handleMouse5(type: NSEvent.EventType, buttonNumber: Int) {
        guard buttonNumber == 4 else { return }

        switch type {
        case .otherMouseDown:
            update(trigger: .mouse5, pressed: true)
        case .otherMouseUp:
            update(trigger: .mouse5, pressed: false)
        default:
            break
        }
    }

    private func handleMouse5(type: CGEventType, buttonNumber: Int64) {
        guard buttonNumber == 4 else { return }

        switch type {
        case .otherMouseDown:
            update(trigger: .mouse5, pressed: true)
        case .otherMouseUp:
            update(trigger: .mouse5, pressed: false)
        default:
            break
        }
    }

    private func update(trigger: Hotkey, pressed: Bool) {
        guard trigger == commandHotkey || hotkeys.contains(trigger) else { return }

        if trigger == commandHotkey {
            updateCommandTrigger(pressed: pressed)
            return
        }

        let wasPressed = !activeTriggers.isEmpty

        if pressed {
            activeTriggers.insert(trigger)
        } else {
            activeTriggers.remove(trigger)
        }

        let isPressed = !activeTriggers.isEmpty
        guard wasPressed != isPressed else { return }

        if isPressed {
            gestureClassifier.keyPressed()
        } else {
            gestureClassifier.keyReleased()
        }
    }

    // Command mode is a direct press/release role — it does not go through the gesture
    // classifier, since there is no need to distinguish a double-tap for hands-free here.
    private func updateCommandTrigger(pressed: Bool) {
        guard commandIsPressed != pressed else { return }
        commandIsPressed = pressed

        if pressed {
            onCommandPress?()
        } else {
            onCommandRelease?()
        }
    }
}

private let hotkeyEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    let typeRawValue = type.rawValue
    let flagsRawValue = event.flags.rawValue
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let mouseButtonNumber = event.getIntegerValueField(.mouseEventButtonNumber)

    Task { @MainActor in
        manager.handle(
            typeRawValue: typeRawValue,
            flagsRawValue: flagsRawValue,
            keyCode: keyCode,
            mouseButtonNumber: mouseButtonNumber
        )
    }

    return Unmanaged.passUnretained(event)
}
