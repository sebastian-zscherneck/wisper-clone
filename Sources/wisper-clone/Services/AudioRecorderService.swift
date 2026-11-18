import AVFoundation
import CoreAudio
import Foundation

@MainActor
protocol AudioRecording {
    var isRecording: Bool { get }
    var selectedInputDeviceID: String? { get set }
    var currentAudioLevel: Float { get }
    func requestPermission() async -> Bool
    func availableInputDevices() -> [AudioInputDevice]
    func startRecording() async throws -> URL
    func stopRecording() async throws -> URL
    func cancelRecording()
}

@MainActor
final class AudioRecorderService: NSObject, AudioRecording, AVCaptureFileOutputRecordingDelegate {
    private var session: AVCaptureSession?
    private var fileOutput: AVCaptureAudioFileOutput?
    private var currentFileURL: URL?
    private var stopContinuation: CheckedContinuation<URL, Error>?
    var selectedInputDeviceID: String?

    var isRecording: Bool {
        fileOutput?.isRecording == true
    }

    var currentAudioLevel: Float {
        guard let channel = fileOutput?.connections.first?.audioChannels.first else { return 0 }
        return max(0, min(1, (channel.averagePowerLevel + 50) / 50))
    }

    func requestPermission() async -> Bool {
        // Already granted: skip the round trip to the permission service on every press.
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            return true
        }
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func availableInputDevices() -> [AudioInputDevice] {
        inputCaptureDevices().map { device in
            AudioInputDevice(
                id: device.uniqueID,
                name: device.localizedName,
                isBluetoothLike: device.isBluetoothLikeInput
            )
        }
    }

    func startRecording() async throws -> URL {
        guard !isRecording else {
            if let currentFileURL {
                return currentFileURL
            }
            throw DictationError.recordingUnavailable
        }

        let device = try selectedCaptureDevice()
        let input = try AVCaptureDeviceInput(device: device)
        let session = AVCaptureSession()
        let fileOutput = AVCaptureAudioFileOutput()

        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw DictationError.recordingUnavailable
        }
        session.addInput(input)

        guard session.canAddOutput(fileOutput) else {
            session.commitConfiguration()
            throw DictationError.recordingUnavailable
        }
        session.addOutput(fileOutput)
        session.commitConfiguration()

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wisper-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        // startRunning blocks until the hardware answers. Off the main thread the Flow Bar
        // keeps animating meanwhile. The session is stored first so a cancel can stop it.
        self.session = session
        nonisolated(unsafe) let startingSession = session
        await Task.detached(priority: .userInitiated) {
            startingSession.startRunning()
        }.value
        guard self.session === session else {
            session.stopRunning()
            throw CancellationError()
        }
        guard session.isRunning else {
            self.session = nil
            throw DictationError.recordingUnavailable
        }

        guard AVCaptureAudioFileOutput.availableOutputFileTypes().contains(.m4a) else {
            session.stopRunning()
            self.session = nil
            throw DictationError.recordingUnavailable
        }

        // Re-encode to mono/16kHz/32kbps AAC before writing to disk: speech-to-text
        // doesn't need stereo or a high sample rate, and a smaller file uploads faster.
        fileOutput.audioSettings = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000
        ]

        fileOutput.startRecording(
            to: fileURL,
            outputFileType: .m4a,
            recordingDelegate: self
        )

        self.fileOutput = fileOutput
        currentFileURL = fileURL
        return fileURL
    }

    func stopRecording() async throws -> URL {
        guard let fileOutput, currentFileURL != nil else {
            throw DictationError.recordingUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            stopContinuation = continuation
            fileOutput.stopRecording()
        }
    }

    func cancelRecording() {
        let fileURL = currentFileURL
        fileOutput?.stopRecording()
        cleanupCapture()

        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            finishRecording(fileURL: outputFileURL, error: error)
        }
    }

    private func finishRecording(fileURL: URL, error: Error?) {
        let continuation = stopContinuation
        stopContinuation = nil
        cleanupCapture()

        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume(returning: fileURL)
        }
    }

    private func cleanupCapture() {
        session?.stopRunning()
        session = nil
        fileOutput = nil
        currentFileURL = nil
    }

    private func selectedCaptureDevice() throws -> AVCaptureDevice {
        let devices = inputCaptureDevices()
        let candidates = devices.map { device in
            InputDeviceCandidate(
                id: device.uniqueID,
                isWireless: device.isBluetoothLikeInput || device.isContinuityInput,
                isBuiltIn: device.isBuiltInInput,
                isExplicitOnly: device.isContinuityInput
            )
        }
        let pickedID = InputDeviceSelector.pick(
            from: candidates,
            selectedID: selectedInputDeviceID,
            defaultID: AVCaptureDevice.default(for: .audio)?.uniqueID,
            isLidClosed: LidState.isClosed
        )

        if let pickedDevice = devices.first(where: { $0.uniqueID == pickedID }) {
            return pickedDevice
        }

        // The system default can be a device the discovery session does not list.
        if let defaultDevice = AVCaptureDevice.default(for: .audio) {
            return defaultDevice
        }

        throw DictationError.recordingUnavailable
    }

    private func inputCaptureDevices() -> [AVCaptureDevice] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external, .continuityCamera],
            mediaType: .audio,
            position: .unspecified
        )
        return discoverySession.devices
    }
}

private extension AVCaptureDevice {
    var isBluetoothLikeInput: Bool {
        let normalizedName = localizedName.lowercased()
        return normalizedName.contains("airpods")
            || normalizedName.contains("bluetooth")
            || normalizedName.contains("beats")
    }

    var isBuiltInInput: Bool {
        transportType == Int32(bitPattern: kAudioDeviceTransportTypeBuiltIn)
    }

    /// An iPhone used as a microphone.
    var isContinuityInput: Bool {
        transportType == Int32(bitPattern: kAudioDeviceTransportTypeContinuityCaptureWired)
            || transportType == Int32(bitPattern: kAudioDeviceTransportTypeContinuityCaptureWireless)
    }
}
