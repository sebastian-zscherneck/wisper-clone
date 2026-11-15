import AppKit
import AVFoundation

/// Moments in a dictation that get a sound and a trackpad tap.
enum FeedbackEvent: CaseIterable, Sendable {
    case started
    case finished
    case cancelled
    case failed
}

@MainActor
protocol DictationFeedbackProviding {
    func signal(_ event: FeedbackEvent, sound: Bool, haptic: Bool)
}

/// Short synthesized tones plus haptic taps. The tones are generated in code, so the
/// app ships no audio files.
@MainActor
final class DictationFeedback: DictationFeedbackProviding {
    private var players: [FeedbackEvent: AVAudioPlayer] = [:]

    init() {
        for event in FeedbackEvent.allCases {
            guard let player = try? AVAudioPlayer(data: ToneSynthesizer.wavData(for: event)) else { continue }
            player.volume = 0.35
            player.prepareToPlay()
            players[event] = player
        }
    }

    func signal(_ event: FeedbackEvent, sound: Bool, haptic: Bool) {
        if sound, let player = players[event] {
            player.currentTime = 0
            player.play()
        }
        if haptic {
            // Only felt while a finger rests on a Force Touch trackpad.
            NSHapticFeedbackManager.defaultPerformer.perform(
                event == .failed ? .levelChange : .generic,
                performanceTime: .now
            )
        }
    }
}

/// Builds the feedback tones: soft sine notes with a quick attack and a smooth fade.
enum ToneSynthesizer {
    private struct Note {
        let frequency: Double
        let duration: Double
    }

    private static let sampleRate = 44_100.0

    private static func notes(for event: FeedbackEvent) -> [Note] {
        switch event {
        case .started:
            return [Note(frequency: 587.33, duration: 0.07), Note(frequency: 880.0, duration: 0.11)]
        case .finished:
            return [Note(frequency: 880.0, duration: 0.07), Note(frequency: 587.33, duration: 0.11)]
        case .cancelled:
            return [Note(frequency: 392.0, duration: 0.12)]
        case .failed:
            return [Note(frequency: 311.13, duration: 0.09), Note(frequency: 277.18, duration: 0.14)]
        }
    }

    static func samples(for event: FeedbackEvent) -> [Float] {
        notes(for: event).flatMap { note -> [Float] in
            let count = Int(note.duration * sampleRate)
            return (0..<count).map { index in
                let time = Double(index) / sampleRate
                let attack = min(1, time / 0.006)
                let fade = pow(1 - Double(index) / Double(count), 2)
                let tone = sin(2 * .pi * note.frequency * time) + 0.25 * sin(4 * .pi * note.frequency * time)
                return Float(tone * attack * fade * 0.6)
            }
        }
    }

    /// 16-bit mono PCM in a WAV container.
    static func wavData(for event: FeedbackEvent) -> Data {
        let pcm = samples(for: event).map { Int16(max(-1, min(1, $0)) * Float(Int16.max)) }
        let byteCount = UInt32(pcm.count * 2)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + byteCount)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate) * 2)
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(byteCount)
        pcm.forEach { append($0) }
        return data
    }
}
