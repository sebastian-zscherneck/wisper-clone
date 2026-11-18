import Testing
@testable import wisper_clone

private let builtIn = InputDeviceCandidate(id: "builtin", isWireless: false, isBuiltIn: true, isExplicitOnly: false)
private let usb = InputDeviceCandidate(id: "usb", isWireless: false, isBuiltIn: false, isExplicitOnly: false)
private let airPods = InputDeviceCandidate(id: "airpods", isWireless: true, isBuiltIn: false, isExplicitOnly: false)

@Test func inputDeviceSelector_lidOpen_keepsTheBuiltInMicrophone() {
    let picked = InputDeviceSelector.pick(
        from: [builtIn, usb], selectedID: nil, defaultID: "builtin", isLidClosed: false
    )
    #expect(picked == "builtin")
}

@Test func inputDeviceSelector_lidClosed_skipsTheBuiltInMicrophone() {
    let picked = InputDeviceSelector.pick(
        from: [builtIn, usb], selectedID: nil, defaultID: "builtin", isLidClosed: true
    )
    #expect(picked == "usb")
}

@Test func inputDeviceSelector_lidClosed_overridesAnExplicitBuiltInSelection() {
    let picked = InputDeviceSelector.pick(
        from: [builtIn, usb], selectedID: "builtin", defaultID: "builtin", isLidClosed: true
    )
    #expect(picked == "usb")
}

@Test func inputDeviceSelector_lidClosed_withOnlyTheBuiltInMicrophone_stillReturnsIt() {
    let picked = InputDeviceSelector.pick(
        from: [builtIn], selectedID: nil, defaultID: "builtin", isLidClosed: true
    )
    #expect(picked == "builtin")
}

@Test func inputDeviceSelector_lidClosed_prefersBluetoothOverTheDeadBuiltInMicrophone() {
    let picked = InputDeviceSelector.pick(
        from: [builtIn, airPods], selectedID: nil, defaultID: "builtin", isLidClosed: true
    )
    #expect(picked == "airpods")
}

@Test func inputDeviceSelector_explicitSelectionWins() {
    let picked = InputDeviceSelector.pick(
        from: [builtIn, usb, airPods], selectedID: "airpods", defaultID: "builtin", isLidClosed: false
    )
    #expect(picked == "airpods")
}

@Test func inputDeviceSelector_automatic_avoidsBluetooth() {
    let picked = InputDeviceSelector.pick(
        from: [airPods, usb], selectedID: nil, defaultID: "airpods", isLidClosed: false
    )
    #expect(picked == "usb")
}

private let iPhone = InputDeviceCandidate(id: "iphone", isWireless: true, isBuiltIn: false, isExplicitOnly: true)

@Test func inputDeviceSelector_iPhone_isNeverTheAutomaticChoice() {
    #expect(InputDeviceSelector.pick(
        from: [iPhone, usb, builtIn], selectedID: nil, defaultID: "iphone", isLidClosed: true
    ) == "usb")
    #expect(InputDeviceSelector.pick(
        from: [iPhone, airPods], selectedID: nil, defaultID: "iphone", isLidClosed: false
    ) == "airpods")
    // Even with the lid closed the iPhone does not replace the built-in microphone.
    #expect(InputDeviceSelector.pick(
        from: [iPhone, builtIn], selectedID: nil, defaultID: "iphone", isLidClosed: true
    ) == "builtin")
}

@Test func inputDeviceSelector_iPhone_isUsedWhenChosenOrWhenNothingElseExists() {
    #expect(InputDeviceSelector.pick(
        from: [iPhone, usb], selectedID: "iphone", defaultID: nil, isLidClosed: false
    ) == "iphone")
    #expect(InputDeviceSelector.pick(
        from: [iPhone], selectedID: nil, defaultID: nil, isLidClosed: false
    ) == "iphone")
}

@Test func inputDeviceSelector_onlyBluetooth_fallsBackToTheSystemDefault() {
    let other = InputDeviceCandidate(id: "beats", isWireless: true, isBuiltIn: false, isExplicitOnly: false)
    let picked = InputDeviceSelector.pick(
        from: [airPods, other], selectedID: "gone", defaultID: "beats", isLidClosed: false
    )
    #expect(picked == "beats")
}

@Test func inputDeviceSelector_noDevices_returnsNil() {
    #expect(InputDeviceSelector.pick(from: [], selectedID: nil, defaultID: nil, isLidClosed: true) == nil)
}
