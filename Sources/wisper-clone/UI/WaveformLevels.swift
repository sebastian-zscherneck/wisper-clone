import Foundation

/// Turns the recent microphone levels into bar heights (0...1) for the Flow Bar waveform.
enum WaveformLevels {
    /// The microphone reports a slow average, so continuous speech is an almost constant
    /// level. Each bar therefore sways at its own pace, scaled by the loudness: speech
    /// stays a moving wave instead of a filled block, and silence stays flat.
    static func barLevels(samples: [Float], barCount: Int, time: TimeInterval) -> [CGFloat] {
        let centre = CGFloat(barCount - 1) / 2
        return (0..<barCount).map { index in
            // The middle bars show the newest level, the outer bars older ones.
            let distance = abs(CGFloat(index) - centre)
            let sampleIndex = samples.count - 1 - Int(distance.rounded(.down)) * 2
            guard sampleIndex >= 0 else { return 0 }

            let level = Double(max(0, min(1, samples[sampleIndex])))
            // Leaves headroom: normal speech sits around 0.6-0.8 and must not hit the top.
            let loudness = pow(level, loudnessExponent)
            let envelope = 1 - Double(distance) / (Double(centre) + 1.5)
            let pace = swayBasePace + swayPaceSpread * Double((index * 5) % barCount) / Double(barCount)
            let sway = 1 - swayDepth * (0.5 + 0.5 * sin(time * pace + Double(index) * 1.7))
            return CGFloat(loudness * envelope * sway)
        }
    }

    private static let loudnessExponent = 1.5
    /// Radians per second of the slowest bar, and how much faster the fastest one is.
    private static let swayBasePace = 7.0
    private static let swayPaceSpread = 6.0
    /// Share of a bar's height that the sway takes away at its lowest point.
    private static let swayDepth = 0.55
}
