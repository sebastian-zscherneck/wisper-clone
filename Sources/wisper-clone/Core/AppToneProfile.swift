import Foundation

struct AppToneProfile: Equatable, Sendable {
    let name: String
    let bundleIDPrefixes: [String]
    let toneInstructions: String

    static let email = AppToneProfile(
        name: "Email",
        bundleIDPrefixes: ["com.apple.mail", "com.microsoft.outlook", "com.readdle.smartemail"],
        toneInstructions: """
        The result will be inserted into an email, so the context is comparatively formal. Prefer complete sentences and paragraph breaks between topics. Keep any dictated greeting ("Hallo Frau Müller", "Hi team") and sign-off ("Viele Grüße", "Best") in place and correctly punctuated. Do not invent a greeting or sign-off that was not dictated.
        """
    )

    static let chat = AppToneProfile(
        name: "Chat",
        bundleIDPrefixes: [
            "com.tinyspeck.slackmacgap",
            "com.hnc.discord",
            "com.apple.mobilesms",
            "ru.keepcoder.telegram",
            "net.whatsapp"
        ],
        toneInstructions: """
        The result will be inserted into a chat message (Slack, Discord, iMessage), so the context is casual. Keep it short and conversational; lowercase sentence starts and a missing final period are fine if that matches the dictation. No greetings or sign-offs unless dictated.
        """
    )

    static let code = AppToneProfile(
        name: "Code",
        bundleIDPrefixes: [
            "com.apple.terminal",
            "com.googlecode.iterm2",
            "com.microsoft.vscode",
            "com.jetbrains.",
            "dev.zed.zed",
            "com.apple.dt.xcode",
            "io.alacritty",
            "com.github.wez.wezterm"
        ],
        toneInstructions: """
        The result will be inserted into a code editor or terminal. Stay very close to the literal transcript: preserve identifiers, file paths, commands, flags, and technical terms exactly. Do not reformat into prose, do not add punctuation inside technical tokens, and do not "correct" code-like fragments.
        """
    )

    static let neutral = AppToneProfile(
        name: "Neutral",
        bundleIDPrefixes: [],
        toneInstructions: """
        The result will be inserted into a general text field. Use a neutral, natural writing style.
        """
    )

    private static let orderedProfiles: [AppToneProfile] = [.email, .chat, .code]

    static func profile(forBundleID bundleID: String?) -> AppToneProfile {
        guard let bundleID else { return .neutral }
        let lowercasedBundleID = bundleID.lowercased()

        for profile in orderedProfiles where profile.bundleIDPrefixes.contains(where: lowercasedBundleID.hasPrefix) {
            return profile
        }

        return .neutral
    }
}
