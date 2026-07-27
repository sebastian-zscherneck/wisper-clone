import AppKit
import Carbon.HIToolbox
import Foundation

/// Outcome of a "click the field, press your keys" recording session.
enum HotkeyCaptureEvent: Equatable {
    case captured(HotkeyBinding)
    case cancelled
    /// A plain character key without modifiers was pressed — not allowed because
    /// the binding would hijack normal typing. Capture stays active.
    case rejected
}

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
    var onSignaturePress: (() -> Void)?

    private var hotkeys: [HotkeyBinding]
    private var commandHotkey: HotkeyBinding?
    private var signatureHotkey: HotkeyBinding?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitors: [Any] = []
    private var localMonitors: [Any] = []
    private var activeTriggers: Set<HotkeyBinding> = []
    private var commandIsPressed = false
    private var signatureIsPressed = false
    private var isEventTapActive = false
    private var captureHandler: ((HotkeyCaptureEvent) -> Void)?
    private var captureHeldModifiers: HotkeyModifiers = []
    private let gestureClassifier = HotkeyGestureClassifier()

    init(hotkeys: [HotkeyBinding]) {
        self.hotkeys = hotkeys
        gestureClassifier.onPress = { [weak self] in self?.onPress?() }
        gestureClassifier.onRelease = { [weak self] in self?.onRelease?() }
        gestureClassifier.onDoubleTap = { [weak self] in self?.onDoubleTap?() }
    }

    func update(hotkeys: [HotkeyBinding]) {
        self.hotkeys = hotkeys
        activeTriggers = []
    }

    func update(commandHotkey: HotkeyBinding?) {
        self.commandHotkey = commandHotkey
        commandIsPressed = false
    }

    func update(signatureHotkey: HotkeyBinding?) {
        self.signatureHotkey = signatureHotkey
        signatureIsPressed = false
    }

    /// Routes the next key/mouse gesture into `handler` instead of triggering
    /// recording. Character keys without modifiers are rejected (capture stays
    /// active); Esc cancels.
    func beginCapture(_ handler: @escaping (HotkeyCaptureEvent) -> Void) {
        captureHandler = handler
        captureHeldModifiers = []
    }

    func cancelCapture() {
        guard let handler = captureHandler else { return }
        captureHandler = nil
        captureHeldModifiers = []
        handler(.cancelled)
    }

    var isCapturing: Bool { captureHandler != nil }

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
        signatureIsPressed = false
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

    // MARK: - Event normalization

    private enum EventKind {
        case flagsChanged
        case keyDown
        case keyUp
        case mouseDown
        case mouseUp
    }

    private func handle(_ event: NSEvent) {
        let kind: EventKind
        switch event.type {
        case .flagsChanged: kind = .flagsChanged
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .otherMouseDown: kind = .mouseDown
        case .otherMouseUp: kind = .mouseUp
        default: return
        }

        var modifiers: HotkeyModifiers = []
        let flags = event.modifierFlags
        if flags.contains(.function) { modifiers.insert(.function) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }

        // When the event tap is active it already delivers every event, including
        // the one-shot Esc / paste-last shortcuts; this NSEvent path only acts as
        // the fallback. Handling one-shots on both paths would fire them twice
        // whenever this app is frontmost.
        process(
            kind: kind,
            keyCode: kind == .keyDown || kind == .keyUp ? event.keyCode : 0,
            mouseButton: kind == .mouseDown || kind == .mouseUp ? event.buttonNumber : 0,
            modifiers: modifiers,
            handleOneShots: !isEventTapActive
        )
    }

    // Internal (not fileprivate) so tests can drive this exact code path — the one the
    // real CGEventTap callback uses — via @testable import, without exposing it publicly.
    func handle(typeRawValue: UInt32, flagsRawValue: UInt64, keyCode: Int64, mouseButtonNumber: Int64) {
        guard let type = CGEventType(rawValue: typeRawValue) else { return }
        let flags = CGEventFlags(rawValue: flagsRawValue)

        let kind: EventKind
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                onEventTapStatusChanged?(true)
            }
            return
        case .flagsChanged: kind = .flagsChanged
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .otherMouseDown: kind = .mouseDown
        case .otherMouseUp: kind = .mouseUp
        default: return
        }

        var modifiers: HotkeyModifiers = []
        if flags.contains(.maskSecondaryFn) { modifiers.insert(.function) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }

        process(
            kind: kind,
            keyCode: UInt16(truncatingIfNeeded: keyCode),
            mouseButton: Int(mouseButtonNumber),
            modifiers: modifiers,
            handleOneShots: true
        )
    }

    // MARK: - Matching

    private func process(
        kind: EventKind,
        keyCode: UInt16,
        mouseButton: Int,
        modifiers: HotkeyModifiers,
        handleOneShots: Bool
    ) {
        if captureHandler != nil {
            processCapture(kind: kind, keyCode: keyCode, mouseButton: mouseButton, modifiers: modifiers)
            return
        }

        switch kind {
        case .keyDown:
            if handleOneShots {
                if keyCode == UInt16(kVK_Escape), modifiers.isEmpty {
                    onEscape?()
                    return
                }
                if keyCode == UInt16(kVK_ANSI_V), modifiers == [.command, .control] {
                    onPasteLastShortcut?()
                    return
                }
            }
            press(matching: .key(code: keyCode), heldModifiers: modifiers)
        case .keyUp:
            release(matching: .key(code: keyCode))
        case .mouseDown:
            press(matching: .mouseButton(number: mouseButton), heldModifiers: modifiers)
        case .mouseUp:
            release(matching: .mouseButton(number: mouseButton))
        case .flagsChanged:
            handleFlagsChanged(heldModifiers: modifiers)
        }
    }

    private var allBindings: [HotkeyBinding] {
        // Command and signature first: when a gesture matches several roles, the
        // single-purpose ones win over plain dictation.
        (commandHotkey.map { [$0] } ?? []) + (signatureHotkey.map { [$0] } ?? []) + hotkeys
    }

    private func isPressed(_ binding: HotkeyBinding) -> Bool {
        if binding == commandHotkey { return commandIsPressed }
        if binding == signatureHotkey { return signatureIsPressed }
        return activeTriggers.contains(binding)
    }

    /// Presses the bindings for `trigger` whose modifiers are all held. When several
    /// match (e.g. Mouse 5 and Shift+Mouse 5 on a shift-click), only the most
    /// specific ones fire.
    private func press(matching trigger: HotkeyBinding.Trigger, heldModifiers: HotkeyModifiers) {
        let candidates = allBindings.filter {
            $0.trigger == trigger && heldModifiers.isSuperset(of: $0.modifiers)
        }
        guard let maxCount = candidates.map(\.modifiers.count).max() else { return }
        for binding in candidates where binding.modifiers.count == maxCount {
            update(trigger: binding, pressed: true)
        }
    }

    /// Releases every binding for `trigger` regardless of the current modifiers, so
    /// dropping a modifier before the key/button never leaves a stuck pressed-state.
    private func release(matching trigger: HotkeyBinding.Trigger) {
        for binding in allBindings where binding.trigger == trigger {
            update(trigger: binding, pressed: false)
        }
    }

    private func handleFlagsChanged(heldModifiers: HotkeyModifiers) {
        let modifierBindings = allBindings.filter { $0.trigger == .modifiersOnly }

        // Release pressed bindings whose chord is no longer fully held.
        for binding in modifierBindings where isPressed(binding) && !heldModifiers.isSuperset(of: binding.modifiers) {
            update(trigger: binding, pressed: false)
        }

        // Press new matches, most specific first. A less specific binding that is
        // already pressed stays pressed (adding Control to a held Fn dictation key
        // starts the Fn+Control command role without ending the Fn dictation).
        let candidates = modifierBindings.filter {
            !isPressed($0) && !$0.modifiers.isEmpty && heldModifiers.isSuperset(of: $0.modifiers)
        }
        guard let maxCount = candidates.map(\.modifiers.count).max() else { return }
        for binding in candidates where binding.modifiers.count == maxCount {
            update(trigger: binding, pressed: true)
        }
    }

    private func processCapture(kind: EventKind, keyCode: UInt16, mouseButton: Int, modifiers: HotkeyModifiers) {
        switch kind {
        case .keyDown:
            if keyCode == UInt16(kVK_Escape), modifiers.isEmpty {
                finishCapture(with: .cancelled)
                return
            }
            if modifiers.isEmpty, !HotkeyBinding.isFunctionKey(keyCode) {
                captureHandler?(.rejected)
                return
            }
            finishCapture(with: .captured(HotkeyBinding(trigger: .key(code: keyCode), modifiers: modifiers)))
        case .mouseDown:
            guard mouseButton >= 2 else { return }
            finishCapture(with: .captured(HotkeyBinding(trigger: .mouseButton(number: mouseButton), modifiers: modifiers)))
        case .flagsChanged:
            if modifiers.isEmpty {
                if !captureHeldModifiers.isEmpty {
                    finishCapture(with: .captured(HotkeyBinding(trigger: .modifiersOnly, modifiers: captureHeldModifiers)))
                }
            } else {
                captureHeldModifiers.formUnion(modifiers)
            }
        case .keyUp, .mouseUp:
            break
        }
    }

    private func finishCapture(with event: HotkeyCaptureEvent) {
        let handler = captureHandler
        captureHandler = nil
        captureHeldModifiers = []
        handler?(event)
    }

    private func update(trigger: HotkeyBinding, pressed: Bool) {
        guard trigger == commandHotkey || trigger == signatureHotkey || hotkeys.contains(trigger) else { return }

        if trigger == commandHotkey {
            updateCommandTrigger(pressed: pressed)
            return
        }

        if trigger == signatureHotkey {
            updateSignatureTrigger(pressed: pressed)
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

    // The signature hotkey is a one-shot toggle, so only the press edge matters — but the
    // pressed-state is still tracked so a held key can't retrigger it.
    private func updateSignatureTrigger(pressed: Bool) {
        guard signatureIsPressed != pressed else { return }
        signatureIsPressed = pressed
        if pressed {
            onSignaturePress?()
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
