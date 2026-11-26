import AVFoundation
import Foundation

/// Decodes a recording with AVAssetReader. This is a second decoder next to FluidAudio's
/// AVAudioFile-based reader: when that one returns almost no samples for a recording
/// that clearly contained speech, this one reads the file independently.
enum RecordingDecoder {
    static let sampleRate: Double = 16_000

    static func monoSamples16k(from url: URL) throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else {
            throw DictationError.transcriptionFailed("The recording contains no audio track.")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ])
        guard reader.canAdd(output) else {
            throw DictationError.transcriptionFailed("The recording cannot be decoded.")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? DictationError.transcriptionFailed("The recording cannot be decoded.")
        }

        var samples: [Float] = []
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let byteCount = CMBlockBufferGetDataLength(blockBuffer)
            var chunk = [Float](repeating: 0, count: byteCount / MemoryLayout<Float>.size)
            let status = chunk.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: byteCount, destination: bytes.baseAddress!)
            }
            if status == kCMBlockBufferNoErr {
                samples.append(contentsOf: chunk)
            }
        }
        if reader.status == .failed {
            throw reader.error ?? DictationError.transcriptionFailed("The recording cannot be decoded.")
        }
        return samples
    }
}

/// Keeps recordings whose transcription failed, so a long dictation is never just gone.
/// ~/Library/Application Support/WisperClone/FailedRecordings, newest `limit` files.
struct FailedRecordingArchive {
    let directory: URL
    var limit = 10

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WisperClone", isDirectory: true)
            .appendingPathComponent("FailedRecordings", isDirectory: true)
    }

    /// Moves the recording into the archive. Returns the new location, or nil if it failed.
    @discardableResult
    func preserve(_ fileURL: URL) -> URL? {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let stamp = Self.timestampFormatter.string(from: Date())
            let destination = directory.appendingPathComponent(
                "\(stamp)-\(UUID().uuidString.prefix(8)).\(fileURL.pathExtension)"
            )
            try fileManager.moveItem(at: fileURL, to: destination)
            prune()
            return destination
        } catch {
            return nil
        }
    }

    private func prune() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }
        let newestFirst = files.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return left > right
        }
        for file in newestFirst.dropFirst(limit) {
            try? fileManager.removeItem(at: file)
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}
