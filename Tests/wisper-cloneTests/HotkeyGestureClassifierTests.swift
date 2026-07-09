import Foundation
import Testing
@testable import wisper_clone

private let testTapWindow: Duration = .milliseconds(50)

@MainActor
private final class GestureRecorder {
    var events: [String] = []

    func attach(to classifier: HotkeyGestureClassifier) {
        classifier.onPress = { [weak self] in self?.events.append("press") }
        classifier.onRelease = { [weak self] in self?.events.append("release") }
        classifier.onDoubleTap = { [weak self] in self?.events.append("doubleTap") }
    }
}

@MainActor
@Test func hotkeyGesture_holdLongerThanWindow_firesPressAndReleaseImmediately() async throws {
    let classifier = HotkeyGestureClassifier(tapWindow: testTapWindow)
    let recorder = GestureRecorder()
    recorder.attach(to: classifier)

    classifier.keyPressed()
    #expect(recorder.events == ["press"])

    try await Task.sleep(for: testTapWindow * 3)
    classifier.keyReleased()
    #expect(recorder.events == ["press", "release"])

    // No delayed callback should fire afterwards.
    try await Task.sleep(for: testTapWindow * 3)
    #expect(recorder.events == ["press", "release"])
}

@MainActor
@Test func hotkeyGesture_singleShortTap_delaysReleaseUntilWindowElapses() async throws {
    let classifier = HotkeyGestureClassifier(tapWindow: testTapWindow)
    let recorder = GestureRecorder()
    recorder.attach(to: classifier)

    classifier.keyPressed()
    classifier.keyReleased()

    #expect(recorder.events == ["press"])

    try await Task.sleep(for: testTapWindow * 3)
    #expect(recorder.events == ["press", "release"])
}

@MainActor
@Test func hotkeyGesture_secondPressWithinWindow_firesDoubleTapAndSwallowsRelease() async throws {
    let classifier = HotkeyGestureClassifier(tapWindow: testTapWindow)
    let recorder = GestureRecorder()
    recorder.attach(to: classifier)

    classifier.keyPressed()
    classifier.keyReleased()
    classifier.keyPressed() // Second press, well within the tap window.

    #expect(recorder.events == ["press", "doubleTap"])

    classifier.keyReleased() // Release of the second tap must be swallowed.
    try await Task.sleep(for: testTapWindow * 3)
    #expect(recorder.events == ["press", "doubleTap"])
}

@MainActor
@Test func hotkeyGesture_afterDoubleTap_nextPressFiresAgain() async throws {
    let classifier = HotkeyGestureClassifier(tapWindow: testTapWindow)
    let recorder = GestureRecorder()
    recorder.attach(to: classifier)

    classifier.keyPressed()
    classifier.keyReleased()
    classifier.keyPressed()
    classifier.keyReleased() // Swallowed.

    #expect(recorder.events == ["press", "doubleTap"])

    classifier.keyPressed()
    classifier.keyReleased()
    #expect(recorder.events == ["press", "doubleTap", "press"])

    try await Task.sleep(for: testTapWindow * 3)
    #expect(recorder.events == ["press", "doubleTap", "press", "release"])
}
