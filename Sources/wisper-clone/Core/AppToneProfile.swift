import Foundation

struct AppToneProfile: Equatable, Sendable {
    let name: String
    let bundleIDPrefixes: [String]
    let toneInstructions: String

    static let email = AppToneProfile(
        name: "Email",
        bundleIDPrefixes: ["com.apple.mail", "com.microsoft.outlook", "com.readdle.smartemail"],
        toneInstructions: """
        The result will be inserted into an email, so the context is comparatively formal. Structure the text: if a greeting was dictated ("Hallo Frau Müller", "Hi team"), place it on its own line followed by an empty line. Break the body into short paragraphs separated by empty lines, one topic per paragraph. If a sign-off was dictated ("Viele Grüße", "Best"), place it on its own line at the end. Use complete sentences and correct punctuation. Do not invent a greeting or sign-off that was not dictated, and do not drop any content.
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
        The result will be inserted into a chat message (Slack, Discord, iMessage), so use a casual, conversational register. Lowercase sentence starts and a missing final period are fine if that matches the dictation. No greetings or sign-offs unless dictated. Casual register does NOT mean shorter: keep every point and detail the speaker made.
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

    private static let browserBundleIDPrefixes: [String] = [
        "com.apple.safari",
        "com.google.chrome",
        "company.thebrowser.browser",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.brave.browser",
        "com.vivaldi.vivaldi"
    ]

    private static let emailWindowTitleKeywords: [String] = [
        "gmail", "mail", "outlook", "posteingang", "compose", "nachricht", "e-mail", "email"
    ]

    static func profile(forBundleID bundleID: String?) -> AppToneProfile {
        profile(forBundleID: bundleID, windowTitle: nil)
    }

    static func profile(forBundleID bundleID: String?, windowTitle: String?) -> AppToneProfile {
        guard let bundleID else { return .neutral }
        let lowercasedBundleID = bundleID.lowercased()

        if browserBundleIDPrefixes.contains(where: lowercasedBundleID.hasPrefix) {
            let lowercasedTitle = windowTitle?.lowercased()
            if let lowercasedTitle, emailWindowTitleKeywords.contains(where: lowercasedTitle.contains) {
                return .email
            }
            return .neutral
        }

        for profile in orderedProfiles where profile.bundleIDPrefixes.contains(where: lowercasedBundleID.hasPrefix) {
            return profile
        }

        return .neutral
    }
}
