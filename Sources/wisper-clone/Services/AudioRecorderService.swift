import AVFoundation
import Foundation

@MainActor
protocol AudioRecording {
    var isRecording: Bool { get }
    var selectedInputDeviceID: String? { get set }
    var currentAudioLevel: Float { get }
    func requestPermission() async -> Bool
    func availableInputDevices() -> [AudioInputDevice]
    func startRecording() throws -> URL
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
        await withCheckedContinuation { continuation in
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

    func startRecording() throws -> URL {
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

        session.startRunning()
        guard session.isRunning else {
            throw DictationError.recordingUnavailable
        }

        guard AVCaptureAudioFileOutput.availableOutputFileTypes().contains(.m4a) else {
            session.stopRunning()
            throw DictationError.recordingUnavailable
        }

        fileOutput.startRecording(
            to: fileURL,
            outputFileType: .m4a,
            recordingDelegate: self
        )

        self.session = session
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

        if let selectedInputDeviceID,
           let selectedDevice = devices.first(where: { $0.uniqueID == selectedInputDeviceID }) {
            return selectedDevice
        }

        if let nonBluetoothDevice = devices.first(where: { !$0.isBluetoothLikeInput }) {
            return nonBluetoothDevice
        }

        if let defaultDevice = AVCaptureDevice.default(for: .audio) {
            return defaultDevice
        }

        if let firstDevice = devices.first {
            return firstDevice
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
}
