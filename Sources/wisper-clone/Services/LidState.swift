import Foundation
import IOKit

/// Reads whether the MacBook lid is closed (clamshell mode on an external display).
enum LidState {
    /// False on Macs without a lid and whenever the state cannot be read.
    static var isClosed: Bool {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else { return false }
        defer { IOObjectRelease(rootDomain) }
        let state = IORegistryEntryCreateCFProperty(
            rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue()
        return (state as? Bool) ?? false
    }
}
