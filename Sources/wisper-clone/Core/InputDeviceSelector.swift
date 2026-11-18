import Foundation

struct InputDeviceCandidate: Equatable, Sendable {
    let id: String
    /// Bluetooth headsets: usable, but not the automatic choice while a wired microphone
    /// is connected.
    let isWireless: Bool
    let isBuiltIn: Bool
    /// An iPhone used as a microphone: only when the user picked it, or nothing else exists.
    let isExplicitOnly: Bool
}

/// Decides which microphone a recording uses.
enum InputDeviceSelector {
    /// Order: the user's choice, then the first wired device, then the system default,
    /// then anything. With the lid closed the built-in microphone records only silence,
    /// so it is skipped whenever another microphone is connected, even when it is the
    /// user's choice or the system default.
    static func pick(
        from devices: [InputDeviceCandidate],
        selectedID: String?,
        defaultID: String?,
        isLidClosed: Bool
    ) -> String? {
        let automatic = devices.filter { !$0.isExplicitOnly }
        let external = automatic.filter { !$0.isBuiltIn }
        let skipsBuiltIn = isLidClosed && !external.isEmpty

        if let selected = devices.first(where: { $0.id == selectedID }),
           !(skipsBuiltIn && selected.isBuiltIn) {
            return selected.id
        }

        let usable = skipsBuiltIn ? external : automatic
        if let wired = usable.first(where: { !$0.isWireless }) {
            return wired.id
        }
        if let defaultID, usable.contains(where: { $0.id == defaultID }) {
            return defaultID
        }
        return usable.first?.id ?? devices.first?.id
    }
}
