import Foundation
import UIKit
import RopeCore

/// Debug input: feeds a directory of JPEG frames at 30 fps, skipping frames while the
/// landmarker is busy (like a live camera would), and dumps every result to a landmark CSV.
final class ReplaySource {
    struct Progress {
        var fed = 0
        var total = 0
        var analyzed = 0
        var finished = false
        /// The frame currently on screen, so the skeleton can be checked against the picture.
        var image: UIImage?
    }

    private let files: [URL]
    private let processor: PoseLandmarkerProcessor
    private let onProgress: (Progress) -> Void
    private var timer: Timer?
    private var index = 0
    private var progress = Progress()
    private var csvHandle: FileHandle?
    let csvURL: URL

    static let frameIntervalMs = 1_000.0 / 30.0

    init(directory: URL, processor: PoseLandmarkerProcessor, onProgress: @escaping (Progress) -> Void) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        files = names.filter { $0.lowercased().hasSuffix(".jpg") || $0.lowercased().hasSuffix(".jpeg") }
            .sorted().map { directory.appendingPathComponent($0) }
        self.processor = processor
        self.onProgress = onProgress
        progress.total = files.count
        csvURL = AppDirectories.documents.appendingPathComponent("replay_landmarks.csv")
        FileManager.default.createFile(atPath: csvURL.path, contents: nil)
        csvHandle = try? FileHandle(forWritingTo: csvURL)
    }

    /// Call from the processor's result callback so analyzed frames are counted and dumped.
    func record(_ frame: PoseFrame) {
        progress.analyzed += 1
        if let data = (LandmarkCSV.line(for: frame) + "\n").data(using: .utf8) {
            csvHandle?.write(data)
        }
        DispatchQueue.main.async { self.onProgress(self.progress) }
    }

    func start() {
        guard timer == nil else { return }
        onProgress(progress)
        timer = Timer.scheduledTimer(withTimeInterval: Self.frameIntervalMs / 1_000, repeats: true) { [weak self] _ in
            self?.feedNext()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        try? csvHandle?.close()
        csvHandle = nil
    }

    private func feedNext() {
        guard index < files.count else {
            progress.finished = true
            onProgress(progress)
            stop()
            return
        }
        let i = index
        index += 1
        progress.fed = index
        guard let image = UIImage(contentsOfFile: files[i].path) else { onProgress(progress); return }
        progress.image = image
        onProgress(progress)
        if processor.isBusy { return }
        processor.detect(image: image, timestampMs: Int(Double(i) * Self.frameIntervalMs))
    }
}
