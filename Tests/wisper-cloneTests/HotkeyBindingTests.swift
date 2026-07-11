import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing
@testable import wisper_clone

// MARK: - Helpers

/// Releases inside the classifier's 350 ms tap window are deferred to wait for a
/// possible double-tap; poll instead of asserting immediately.
@MainActor
private func expectEventually(
    timeout: Duration = .seconds(2),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool
) async throws {
    let start = ContinuousClock.now
    while !condition() {
        if ContinuousClock.now - start > timeout {
            Issue.record("Condition not met within \(timeout)", sourceLocation: sourceLocation)
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
}

@MainActor
private func send(
    _ manager: HotkeyManager,
    type: CGEventType,
    flags: CGEventFlags = [],
    keyCode: Int = 0,
    button: Int = 0
) {
    manager.handle(
        typeRawValue: type.rawValue,
        flagsRawValue: flags.rawValue,
        keyCode: Int64(keyCode),
        mouseButtonNumber: Int64(button)
    )
}

// MARK: - Display names & legacy mapping

@Test func hotkeyBinding_displayNamesUseModifierSymbols() {
    #expect(HotkeyBinding.fn.displayName == "Fn")
    #expect(HotkeyBinding.optionSpace.displayName == "⌥Space")
    #expect(HotkeyBinding.shiftMouse5.displayName == "⇧ Mouse 5")
    #expect(HotkeyBinding.mouse5.displayName == "Mouse 5")
    #expect(
        HotkeyBinding(trigger: .key(code: UInt16(kVK_ANSI_D)), modifiers: [.command, .shift]).displayName == "⇧⌘D"
    )
}

@Test func hotkeyBinding_mapsAllLegacyRawValues() {
    #expect(HotkeyBinding(legacyHotkeyRawValue: "fn") == .fn)
    #expect(HotkeyBinding(legacyHotkeyRawValue: "mouse5") == .mouse5)
    #expect(HotkeyBinding(legacyHotkeyRawValue: "shiftMouse5") == .shiftMouse5)
    #expect(HotkeyBinding(legacyHotkeyRawValue: "optionSpace") == .optionSpace)
    #expect(HotkeyBinding(legacyHotkeyRawValue: "controlSpace") == .controlSpace)
    #expect(HotkeyBinding(legacyHotkeyRawValue: "fnControl") == .fnControl)
    #expect(HotkeyBinding(legacyHotkeyRawValue: "unknown") == nil)
}

// MARK: - Custom binding matching

@MainActor
@Test func hotkeyManager_customKeyBindingPressesAndReleasesDictation() async throws {
    let binding = HotkeyBinding(trigger: .key(code: UInt16(kVK_ANSI_D)), modifiers: [.command, .shift])
    let manager = HotkeyManager(hotkeys: [binding])
    var pressCount = 0
    var releaseCount = 0
    manager.onPress = { pressCount += 1 }
    manager.onRelease = { releaseCount += 1 }

    send(manager, type: .keyDown, flags: [.maskCommand, .maskShift], keyCode: kVK_ANSI_D)
    #expect(pressCount == 1)

    // Modifiers already dropped before the key comes up — must still release.
    send(manager, type: .keyUp, flags: [], keyCode: kVK_ANSI_D)
    try await expectEventually { releaseCount == 1 }
}

@MainActor
@Test func hotkeyManager_keyBindingIgnoresKeyWithoutRequiredModifiers() {
    let binding = HotkeyBinding(trigger: .key(code: UInt16(kVK_ANSI_D)), modifiers: [.command, .shift])
    let manager = HotkeyManager(hotkeys: [binding])
    var pressCount = 0
    manager.onPress = { pressCount += 1 }

    send(manager, type: .keyDown, flags: [.maskCommand], keyCode: kVK_ANSI_D)
    send(manager, type: .keyDown, flags: [], keyCode: kVK_ANSI_D)
    #expect(pressCount == 0)
}

@MainActor
@Test func hotkeyManager_customModifierChordTriggersDictation() async throws {
    let chord = HotkeyBinding(trigger: .modifiersOnly, modifiers: [.option, .command])
    let manager = HotkeyManager(hotkeys: [chord])
    var pressCount = 0
    var releaseCount = 0
    manager.onPress = { pressCount += 1 }
    manager.onRelease = { releaseCount += 1 }

    send(manager, type: .flagsChanged, flags: [.maskAlternate])
    #expect(pressCount == 0)

    send(manager, type: .flagsChanged, flags: [.maskAlternate, .maskCommand])
    #expect(pressCount == 1)

    send(manager, type: .flagsChanged, flags: [.maskCommand])
    try await expectEventually { releaseCount == 1 }
}

@MainActor
@Test func hotkeyManager_customMouseButtonWithModifierRoutesBySpecificity() {
    // Mouse 4 plain -> dictation, Control+Mouse 4 -> command. The control-click
    // must fire only the more specific command binding.
    let plain = HotkeyBinding(trigger: .mouseButton(number: 3), modifiers: [])
    let withControl = HotkeyBinding(trigger: .mouseButton(number: 3), modifiers: [.control])
    let manager = HotkeyManager(hotkeys: [plain])
    manager.update(commandHotkey: withControl)
    var pressCount = 0
    var commandPressCount = 0
    manager.onPress = { pressCount += 1 }
    manager.onCommandPress = { commandPressCount += 1 }

    send(manager, type: .otherMouseDown, flags: [.maskControl], button: 3)
    #expect(commandPressCount == 1)
    #expect(pressCount == 0)

    send(manager, type: .otherMouseUp, flags: [], button: 3)

    send(manager, type: .otherMouseDown, flags: [], button: 3)
    #expect(pressCount == 1)
    #expect(commandPressCount == 1)
}

@MainActor
@Test func hotkeyManager_addingControlToHeldFnStartsCommandWithoutEndingDictation() async throws {
    // Preserves the old fn/fnControl interplay with the generic matcher: the held
    // Fn dictation stays pressed while Fn+Control starts the command role.
    let manager = HotkeyManager(hotkeys: [.fn])
    manager.update(commandHotkey: .fnControl)
    var pressCount = 0
    var releaseCount = 0
    var commandPressCount = 0
    manager.onPress = { pressCount += 1 }
    manager.onRelease = { releaseCount += 1 }
    manager.onCommandPress = { commandPressCount += 1 }

    send(manager, type: .flagsChanged, flags: [.maskSecondaryFn])
    #expect(pressCount == 1)

    send(manager, type: .flagsChanged, flags: [.maskSecondaryFn, .maskControl])
    #expect(commandPressCount == 1)
    #expect(releaseCount == 0)

    send(manager, type: .flagsChanged, flags: [])
    try await expectEventually { releaseCount == 1 }
}

// MARK: - Capture

@MainActor
@Test func hotkeyManager_captureCommitsKeyWithHeldModifiersImmediately() {
    let manager = HotkeyManager(hotkeys: [.fn])
    var events: [HotkeyCaptureEvent] = []
    manager.beginCapture { events.append($0) }

    send(manager, type: .keyDown, flags: [.maskAlternate], keyCode: kVK_ANSI_R)

    #expect(events == [.captured(HotkeyBinding(trigger: .key(code: UInt16(kVK_ANSI_R)), modifiers: [.option]))])
    #expect(!manager.isCapturing)
}

@MainActor
@Test func hotkeyManager_captureCommitsModifierChordOnRelease() {
    let manager = HotkeyManager(hotkeys: [.fn])
    var events: [HotkeyCaptureEvent] = []
    manager.beginCapture { events.append($0) }

    send(manager, type: .flagsChanged, flags: [.maskControl])
    send(manager, type: .flagsChanged, flags: [.maskControl, .maskAlternate])
    #expect(events.isEmpty)

    send(manager, type: .flagsChanged, flags: [])
    #expect(events == [.captured(HotkeyBinding(trigger: .modifiersOnly, modifiers: [.control, .option]))])
}

@MainActor
@Test func hotkeyManager_captureCommitsMouseButton() {
    let manager = HotkeyManager(hotkeys: [.fn])
    var events: [HotkeyCaptureEvent] = []
    manager.beginCapture { events.append($0) }

    send(manager, type: .otherMouseDown, flags: [.maskShift], button: 4)

    #expect(events == [.captured(HotkeyBinding(trigger: .mouseButton(number: 4), modifiers: [.shift]))])
}

@MainActor
@Test func hotkeyManager_captureRejectsPlainCharacterKeyAndStaysActive() {
    let manager = HotkeyManager(hotkeys: [.fn])
    var events: [HotkeyCaptureEvent] = []
    manager.beginCapture { events.append($0) }

    send(manager, type: .keyDown, flags: [], keyCode: kVK_ANSI_A)
    #expect(events == [.rejected])
    #expect(manager.isCapturing)

    // A bare function key is fine — it cannot hijack typing.
    send(manager, type: .keyDown, flags: [], keyCode: kVK_F6)
    #expect(events.last == .captured(HotkeyBinding(trigger: .key(code: UInt16(kVK_F6)), modifiers: [])))
}

@MainActor
@Test func hotkeyManager_captureEscapeCancelsAndSuppressesHotkeys() {
    let manager = HotkeyManager(hotkeys: [.fn])
    var events: [HotkeyCaptureEvent] = []
    var pressCount = 0
    manager.onPress = { pressCount += 1 }
    manager.beginCapture { events.append($0) }

    // While capturing, the configured hotkey must not trigger recording.
    send(manager, type: .flagsChanged, flags: [.maskSecondaryFn])
    send(manager, type: .flagsChanged, flags: [.maskSecondaryFn, .maskControl])
    #expect(pressCount == 0)

    send(manager, type: .flagsChanged, flags: [])
    // Releasing the modifiers committed a chord; restart capture and cancel via Esc.
    manager.beginCapture { events.append($0) }
    send(manager, type: .keyDown, flags: [], keyCode: kVK_Escape)

    #expect(events.last == .cancelled)
    #expect(!manager.isCapturing)
}

// MARK: - Coordinator capture flow

@MainActor
@Test func coordinator_capturedBindingReplacesDictationHotkey() async throws {
    let recorder = SpyRecorder(recordedFileURL: URL(filePath: "/tmp/not-used.m4a"))
    let manager = HotkeyManager(hotkeys: [.fn])
    let coordinator = makeCoordinator(
        recorder: recorder,
        transcriber: SpyTranscriptionClient(result: ""),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        hotkeyManager: manager
    )

    var remaining = coordinator.preferences.hotkeys
    remaining.removeFirst()

    coordinator.beginHotkeyCapture(for: .dictation(index: 0))
    #expect(coordinator.hotkeyCaptureTarget == .dictation(index: 0))

    send(manager, type: .keyDown, flags: [.maskCommand, .maskShift], keyCode: kVK_ANSI_D)

    let expected = HotkeyBinding(trigger: .key(code: UInt16(kVK_ANSI_D)), modifiers: [.shift, .command])
    #expect(coordinator.preferences.hotkeys == [expected] + remaining)
    #expect(coordinator.hotkeyCaptureTarget == nil)
}

@MainActor
@Test func coordinator_capturedBindingAppendsNewDictationHotkey() async throws {
    let manager = HotkeyManager(hotkeys: [.fn])
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: URL(filePath: "/tmp/not-used.m4a")),
        transcriber: SpyTranscriptionClient(result: ""),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        hotkeyManager: manager
    )
    let initial = coordinator.preferences.hotkeys

    coordinator.beginHotkeyCapture(for: .dictation(index: nil))
    send(manager, type: .otherMouseDown, flags: [], button: 3)

    #expect(coordinator.preferences.hotkeys == initial + [HotkeyBinding(trigger: .mouseButton(number: 3), modifiers: [])])
}

@MainActor
@Test func coordinator_capturedBindingAlreadyInUseIsRejected() async throws {
    let manager = HotkeyManager(hotkeys: [.fn, .mouse5])
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: URL(filePath: "/tmp/not-used.m4a")),
        transcriber: SpyTranscriptionClient(result: ""),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        hotkeyManager: manager
    )
    let initial = coordinator.preferences

    // Try to give the command role the dictation Mouse 5 binding via capture.
    coordinator.beginHotkeyCapture(for: .command)
    send(manager, type: .otherMouseDown, flags: [], button: 4)

    #expect(coordinator.preferences == initial)
    #expect(coordinator.statusText == "Mouse 5 is already in use")
}

@MainActor
@Test func coordinator_lastDictationHotkeyCannotBeRemoved() async throws {
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: URL(filePath: "/tmp/not-used.m4a")),
        transcriber: SpyTranscriptionClient(result: ""),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        hotkeyManager: HotkeyManager(hotkeys: [.fn])
    )
    var preferences = coordinator.preferences
    preferences.hotkeys = [.fn]
    coordinator.preferences = preferences

    coordinator.removeDictationHotkey(at: 0)

    #expect(coordinator.preferences.hotkeys == [.fn])
}
