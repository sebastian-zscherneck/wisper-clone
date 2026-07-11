import Carbon.HIToolbox
import Foundation

struct HotkeyModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int

    static let function = HotkeyModifiers(rawValue: 1 << 0)
    static let control = HotkeyModifiers(rawValue: 1 << 1)
    static let option = HotkeyModifiers(rawValue: 1 << 2)
    static let shift = HotkeyModifiers(rawValue: 1 << 3)
    static let command = HotkeyModifiers(rawValue: 1 << 4)

    var count: Int {
        [Self.function, .control, .option, .shift, .command].filter(contains).count
    }

    var displaySymbols: String {
        var parts: [String] = []
        if contains(.function) { parts.append("Fn") }
        if contains(.control) { parts.append("⌃") }
        if contains(.option) { parts.append("⌥") }
        if contains(.shift) { parts.append("⇧") }
        if contains(.command) { parts.append("⌘") }
        return parts.joined()
    }
}

/// A user-configurable hold-to-record gesture: a key, a mouse side button, or a
/// bare modifier chord, each with a required set of held modifiers.
struct HotkeyBinding: Codable, Hashable, Sendable, Identifiable {
    enum Trigger: Codable, Hashable, Sendable {
        case key(code: UInt16)
        case mouseButton(number: Int)
        case modifiersOnly
    }

    var id: HotkeyBinding { self }

    var displayName: String {
        switch trigger {
        case .key(let code):
            return modifiers.displaySymbols + Self.keyName(for: code)
        case .mouseButton(let number):
            let name = "Mouse \(number + 1)"
            return modifiers.displaySymbols.isEmpty ? name : modifiers.displaySymbols + " " + name
        case .modifiersOnly:
            return modifiers.displaySymbols
        }
    }

    var trigger: Trigger
    var modifiers: HotkeyModifiers

    init(trigger: Trigger, modifiers: HotkeyModifiers) {
        self.trigger = trigger
        self.modifiers = modifiers
    }

    // MARK: - Legacy migration

    /// Maps a stored raw value of the removed `Hotkey` enum onto the equivalent binding.
    init?(legacyHotkeyRawValue: String) {
        switch legacyHotkeyRawValue {
        case "fn":
            self = .fn
        case "mouse5":
            self = .mouse5
        case "shiftMouse5":
            self = .shiftMouse5
        case "optionSpace":
            self = .optionSpace
        case "controlSpace":
            self = .controlSpace
        case "fnControl":
            self = .fnControl
        default:
            return nil
        }
    }

    static let fn = HotkeyBinding(trigger: .modifiersOnly, modifiers: [.function])
    static let mouse5 = HotkeyBinding(trigger: .mouseButton(number: 4), modifiers: [])
    static let shiftMouse5 = HotkeyBinding(trigger: .mouseButton(number: 4), modifiers: [.shift])
    static let optionSpace = HotkeyBinding(trigger: .key(code: UInt16(kVK_Space)), modifiers: [.option])
    static let controlSpace = HotkeyBinding(trigger: .key(code: UInt16(kVK_Space)), modifiers: [.control])
    static let fnControl = HotkeyBinding(trigger: .modifiersOnly, modifiers: [.function, .control])

    // MARK: - Key names

    private static let specialKeyNames: [UInt16: String] = [
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Return): "Return",
        UInt16(kVK_Tab): "Tab",
        UInt16(kVK_Delete): "Delete",
        UInt16(kVK_ForwardDelete): "Fwd Delete",
        UInt16(kVK_Escape): "Esc",
        UInt16(kVK_Home): "Home",
        UInt16(kVK_End): "End",
        UInt16(kVK_PageUp): "Page Up",
        UInt16(kVK_PageDown): "Page Down",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15",
        UInt16(kVK_F16): "F16", UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18",
        UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20"
    ]

    private static let ansiKeyNames: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B", UInt16(kVK_ANSI_C): "C",
        UInt16(kVK_ANSI_D): "D", UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
        UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H", UInt16(kVK_ANSI_I): "I",
        UInt16(kVK_ANSI_J): "J", UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N", UInt16(kVK_ANSI_O): "O",
        UInt16(kVK_ANSI_P): "P", UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
        UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T", UInt16(kVK_ANSI_U): "U",
        UInt16(kVK_ANSI_V): "V", UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
        UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2",
        UInt16(kVK_ANSI_3): "3", UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
        UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8",
        UInt16(kVK_ANSI_9): "9"
    ]

    /// F1–F20 work as bare hotkeys; every other key needs at least one modifier
    /// so a binding can never hijack normal typing.
    static func isFunctionKey(_ code: UInt16) -> Bool {
        let functionKeys: Set<UInt16> = Set(
            [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
             kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
                .map(UInt16.init)
        )
        return functionKeys.contains(code)
    }

    static func keyName(for code: UInt16) -> String {
        specialKeyNames[code] ?? ansiKeyNames[code] ?? "Key \(code)"
    }
}
