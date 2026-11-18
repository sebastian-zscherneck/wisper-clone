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

/// Short tones plus haptic taps. The tones are synthesized in code, so the app ships no
/// audio files; a WAV file in the user's sounds folder replaces the tone of its event.
@MainActor
final class DictationFeedback: DictationFeedbackProviding {
    private static let synthesizedVolume: Float = 0.35

    private var players: [FeedbackEvent: AVAudioPlayer] = [:]

    init(soundsDirectory: URL? = FeedbackSoundLibrary.defaultDirectory) {
        for event in FeedbackEvent.allCases {
            let sound = FeedbackSoundLibrary.sound(for: event, in: soundsDirectory)
            // A custom file that is not playable audio must not silence the event.
            guard let player = (try? AVAudioPlayer(data: sound.data))
                ?? (try? AVAudioPlayer(data: ToneSynthesizer.wavData(for: event))) else { continue }
            // Custom files play as authored; the synthesized tones are loud at full volume.
            player.volume = sound.isCustom ? 1 : Self.synthesizedVolume
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

/// Finds the sound of an event: `<event>.wav` in the sounds folder, else the built-in tone.
enum FeedbackSoundLibrary {
    struct Sound: Equatable {
        let data: Data
        let isCustom: Bool
    }

    /// ~/Library/Application Support/WisperClone/Sounds
    static var defaultDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("WisperClone", isDirectory: true)
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    static func fileName(for event: FeedbackEvent) -> String {
        switch event {
        case .started: return "started.wav"
        case .finished: return "finished.wav"
        case .cancelled: return "cancelled.wav"
        case .failed: return "failed.wav"
        }
    }

    static func sound(for event: FeedbackEvent, in directory: URL?) -> Sound {
        if let directory,
           let data = try? Data(contentsOf: directory.appendingPathComponent(fileName(for: event))) {
            return Sound(data: data, isCustom: true)
        }
        return Sound(data: ToneSynthesizer.wavData(for: event), isCustom: false)
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
