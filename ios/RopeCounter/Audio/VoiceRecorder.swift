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

    override init() {
        super.init()
        // A phone call or Siri ends the recording without a delegate callback; treat it as a
        // discarded take so the UI never stays in the recording state.
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func audioInterrupted(_ note: Notification) {
        guard recorder != nil else { return }
        DispatchQueue.main.async { self.stop(discard: true) }
    }

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
        if recorder.isRecording {
            recorder.stop()  // the delegate finishes the take
        } else {
            finish(recorder, success: false)
        }
        return !discard
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        finish(recorder, success: flag)
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        finish(recorder, success: false)
    }

    private func finish(_ recorder: AVAudioRecorder, success: Bool) {
        guard self.recorder === recorder else { return }
        let tmp = recorder.url
        let size = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? Int) ?? 0
        if success && !discardOnFinish && size > 0, let target = targetURL {
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
