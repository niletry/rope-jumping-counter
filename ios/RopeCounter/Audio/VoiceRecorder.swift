import AVFoundation

/// Records a short AAC clip (3 s max) into a `.tmp` file and renames it on success,
/// so a half-written recording never replaces a good one.
final class VoiceRecorder: NSObject, AVAudioRecorderDelegate {
    static let maxDurationSec: TimeInterval = 3

    private var recorder: AVAudioRecorder?
    private var targetURL: URL?
    private var onFinished: (() -> Void)?
    private var discardOnFinish = false

    var isRecording: Bool { recorder?.isRecording ?? false }

    /// Asks for microphone permission; `completion` runs on the main queue.
    static func requestPermission(_ completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Starts recording to `file`. `onAutoStop` fires on the main queue when the clip reaches the
    /// maximum duration or when `stop()` is called.
    func start(file: URL, onAutoStop: @escaping () -> Void) throws {
        if isRecording { stop(discard: true) }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let tmp = file.appendingPathExtension("tmp")
        try? FileManager.default.removeItem(at: tmp)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 24_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ]
        let recorder = try AVAudioRecorder(url: tmp, settings: settings)
        recorder.delegate = self
        guard recorder.record(forDuration: Self.maxDurationSec) else {
            throw NSError(domain: "VoiceRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "录音器无法启动"])
        }
        self.recorder = recorder
        targetURL = file
        onFinished = onAutoStop
        discardOnFinish = false
    }

    /// Stops an in-progress recording. Returns true when a clip was kept.
    @discardableResult
    func stop(discard: Bool = false) -> Bool {
        guard let recorder else { return false }
        discardOnFinish = discard
        recorder.stop()
        return !discard
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let tmp = recorder.url
        if flag && !discardOnFinish, let target = targetURL {
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.moveItem(at: tmp, to: target)
        } else {
            try? FileManager.default.removeItem(at: tmp)
        }
        self.recorder = nil
        targetURL = nil
        let callback = onFinished
        onFinished = nil
        DispatchQueue.main.async { callback?() }
    }
}
