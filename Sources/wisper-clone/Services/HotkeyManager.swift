import AppKit
import Carbon.HIToolbox
import Foundation

@MainActor
final class HotkeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onEventTapStatusChanged: ((Bool) -> Void)?

    private var hotkeys: Set<Hotkey>
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitors: [Any] = []
    private var localMonitors: [Any] = []
    private var activeTriggers: Set<Hotkey> = []

    init(hotkeys: Set<Hotkey>) {
        self.hotkeys = hotkeys
    }

    func update(hotkeys: Set<Hotkey>) {
        self.hotkeys = hotkeys
        activeTriggers = []
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
            onEventTapStatusChanged?(false)
            addGlobalMonitor(mask: [.flagsChanged, .keyDown, .keyUp, .otherMouseDown, .otherMouseUp])
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
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
        if hotkeys.contains(.fn), event.type == .flagsChanged {
            update(trigger: .fn, pressed: event.modifierFlags.contains(.function))
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

    fileprivate func handle(typeRawValue: UInt32, flagsRawValue: UInt64, keyCode: Int64, mouseButtonNumber: Int64) {
        guard let type = CGEventType(rawValue: typeRawValue) else { return }
        let flags = CGEventFlags(rawValue: flagsRawValue)

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                onEventTapStatusChanged?(true)
            }
        case .flagsChanged:
            if hotkeys.contains(.fn) {
                update(trigger: .fn, pressed: flags.contains(.maskSecondaryFn))
            }
        case .keyDown, .keyUp:
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
        let wasPressed = !activeTriggers.isEmpty

        if pressed {
            activeTriggers.insert(trigger)
        } else {
            activeTriggers.remove(trigger)
        }

        let isPressed = !activeTriggers.isEmpty
        guard wasPressed != isPressed else { return }

        if isPressed {
            onPress?()
        } else {
            onRelease?()
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
