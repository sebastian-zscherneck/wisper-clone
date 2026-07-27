import Foundation
import Testing
@testable import wisper_clone

private func makeSettings(
    enabled: Bool = true,
    text: String = "Made with WisprFlow",
    separator: SignatureSeparator = .newline,
    apps: [SignatureApp] = SignatureApp.defaults
) -> SignatureSettings {
    var settings = SignatureSettings()
    settings.isAutoAppendEnabled = enabled
    settings.text = text
    settings.separator = separator
    settings.apps = apps
    return settings
}

@Test func signature_appendsForConfiguredApp() {
    #expect(SignatureAppender.shouldAppend(
        settings: makeSettings(),
        bundleID: "com.tinyspeck.slackmacgap"
    ))
}

@Test func signature_matchesBundleIDCaseInsensitively() {
    #expect(SignatureAppender.shouldAppend(
        settings: makeSettings(),
        bundleID: "NET.WHATSAPP.WHATSAPP"
    ))
}

@Test func signature_matchesBundleIDPrefix() {
    let settings = makeSettings(apps: [SignatureApp(bundleID: "com.jetbrains.", name: "JetBrains")])

    #expect(SignatureAppender.shouldAppend(settings: settings, bundleID: "com.jetbrains.intellij"))
}

@Test func signature_skipsUnconfiguredApp() {
    #expect(!SignatureAppender.shouldAppend(
        settings: makeSettings(),
        bundleID: "com.apple.mail"
    ))
}

@Test func signature_skipsWhenAutoAppendDisabled() {
    #expect(!SignatureAppender.shouldAppend(
        settings: makeSettings(enabled: false),
        bundleID: "com.tinyspeck.slackmacgap"
    ))
}

@Test func signature_skipsWhenTextIsBlank() {
    #expect(!SignatureAppender.shouldAppend(
        settings: makeSettings(text: "   "),
        bundleID: "com.tinyspeck.slackmacgap"
    ))
}

@Test func signature_skipsWhenBundleIDIsUnknown() {
    #expect(!SignatureAppender.shouldAppend(settings: makeSettings(), bundleID: nil))
}

@Test func signature_skipsWhenNoAppsConfigured() {
    #expect(!SignatureAppender.shouldAppend(
        settings: makeSettings(apps: []),
        bundleID: "com.tinyspeck.slackmacgap"
    ))
}

@Test func signature_appendsOnNewLine() {
    let result = SignatureAppender.append("Made with WisprFlow", to: "hey team", separator: .newline)

    #expect(result == "hey team\nMade with WisprFlow")
}

@Test func signature_appendsOnSameLine() {
    let result = SignatureAppender.append("— Made with WisprFlow", to: "hey team", separator: .space)

    #expect(result == "hey team — Made with WisprFlow")
}

@Test func signature_appendsAfterBlankLine() {
    let result = SignatureAppender.append("Made with WisprFlow", to: "hey team", separator: .blankLine)

    #expect(result == "hey team\n\nMade with WisprFlow")
}

@Test func signature_doesNotStackWhenTextAlreadyEndsWithIt() {
    let once = SignatureAppender.append("Made with WisprFlow", to: "hey team", separator: .newline)
    let twice = SignatureAppender.append("Made with WisprFlow", to: once, separator: .newline)

    #expect(twice == once)
}

@Test func signature_ignoresCaseWhenDetectingAnExistingSignature() {
    let result = SignatureAppender.append(
        "Made with WisprFlow",
        to: "hey team made with wisprflow",
        separator: .newline
    )

    #expect(result == "hey team made with wisprflow")
}

@Test func signature_returnsTextUnchangedWhenSignatureIsBlank() {
    #expect(SignatureAppender.append("  ", to: "hey team", separator: .newline) == "hey team")
}

@Test func signature_returnsSignatureAloneWhenTextIsBlank() {
    #expect(SignatureAppender.append("Made with WisprFlow", to: "   ", separator: .newline) == "Made with WisprFlow")
}
