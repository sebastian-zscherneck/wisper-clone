import Foundation
import Testing
@testable import wisper_clone

@Test func waveform_sustainedLoudSpeech_keepsMovingInsteadOfFillingUp() {
    let loud = [Float](repeating: 0.75, count: 40)
    let frames = stride(from: 0.0, to: 2.0, by: 1.0 / 30.0).map {
        WaveformLevels.barLevels(samples: loud, barCount: 10, time: $0)
    }

    // No bar is ever pinned at full height.
    #expect(frames.allSatisfy { $0.allSatisfy { $0 < 0.95 } })
    // Every bar moves visibly over time although the input level is constant.
    for bar in 0..<10 {
        let heights = frames.map { $0[bar] }
        let tallest = heights.max() ?? 0
        // The outer bars are short, so the movement is measured against the bar itself.
        #expect(tallest - (heights.min() ?? 0) > tallest * 0.3)
    }
}

@Test func waveform_silence_staysFlat() {
    let levels = WaveformLevels.barLevels(samples: [Float](repeating: 0, count: 40), barCount: 10, time: 1.3)
    #expect(levels.allSatisfy { $0 == 0 })
    #expect(WaveformLevels.barLevels(samples: [], barCount: 10, time: 1.3).allSatisfy { $0 == 0 })
}

@Test func waveform_louderInputGivesTallerBars_andStaysInRange() {
    let quiet = WaveformLevels.barLevels(samples: [Float](repeating: 0.3, count: 40), barCount: 10, time: 0.5)
    let loud = WaveformLevels.barLevels(samples: [Float](repeating: 1.0, count: 40), barCount: 10, time: 0.5)
    #expect(zip(quiet, loud).allSatisfy { $0 < $1 })
    #expect(loud.allSatisfy { $0 >= 0 && $0 <= 1 })
}
