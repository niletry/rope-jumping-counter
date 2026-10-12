import Foundation
import UIKit
import MediaPipeTasksVision
import RopeCore

/// Wraps the MediaPipe pose landmarker in live-stream mode. One frame is in flight at a time:
/// callers check `isBusy` and drop frames instead of queueing them, so latency never accumulates.
///
/// A landmarker that stops answering (a GPU graph can die without ever calling the delegate) is
/// replaced by a CPU one after `stallTimeoutMs`, so a workout never hangs on "请全身入镜".
final class PoseLandmarkerProcessor: NSObject, PoseLandmarkerLiveStreamDelegate {
    private var landmarker: PoseLandmarker!
    private var delegate: Delegate = .CPU
    private let onResult: (PoseFrame) -> Void
    private let onError: (String) -> Void
    private var inputSizes: [Int: (Int, Int)] = [:]
    private let lock = NSLock()
    private let watchdog = InFlightWatchdog(timeoutMs: PoseLandmarkerProcessor.stallTimeoutMs)
    private var recovering = false
    private var closed = false
    private var firstFrameLogged = false

    /// Longer than any sane inference, shorter than a user's patience.
    static let stallTimeoutMs: Int64 = 3_000

    /// Which delegate the landmarker ended up on; shown in the replay HUD for diagnostics.
    private(set) var delegateName = "CPU"

    private var busy = false
    /// True while a frame is in flight. Safe to read from any thread. Reading it also notices a
    /// landmarker that stopped answering and starts the switch to the CPU, so a caller that
    /// waits for "not busy" is never stuck forever.
    var isBusy: Bool {
        lock.lock()
        let value = busy
        lock.unlock()
        if value { ensureAlive() }
        return value
    }

    init(onResult: @escaping (PoseFrame) -> Void, onError: @escaping (String) -> Void) throws {
        self.onResult = onResult
        self.onError = onError
        super.init()
        // Prefer the GPU, same as Android; fall back to the CPU if it cannot be initialised.
        // The simulator's software Metal renderer makes the GPU path abort inside MediaPipe, so
        // only the CPU is tried there.
        #if targetEnvironment(simulator)
        let candidates: [(Delegate, String)] = [(.CPU, "CPU")]
        #else
        let candidates: [(Delegate, String)] = [(.GPU, "GPU"), (.CPU, "CPU")]
        #endif
        let (created, used, name) = try Self.create(candidates, delegate: self)
        landmarker = created
        delegate = used
        delegateName = name
        NSLog("Pose landmarker running on \(name)")
    }

    private static func create(_ candidates: [(Delegate, String)], delegate: PoseLandmarkerLiveStreamDelegate) throws -> (PoseLandmarker, Delegate, String) {
        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker_lite", ofType: "task") else {
            throw NSError(domain: "PoseLandmarker", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到姿态模型文件"])
        }
        for (candidate, label) in candidates {
            let options = PoseLandmarkerOptions()
            options.baseOptions.modelAssetPath = modelPath
            options.baseOptions.delegate = candidate
            options.runningMode = .liveStream
            options.numPoses = 1
            options.minPoseDetectionConfidence = 0.50
            options.minPosePresenceConfidence = 0.50
            options.minTrackingConfidence = 0.50
            options.poseLandmarkerLiveStreamDelegate = delegate
            do {
                return (try PoseLandmarker(options: options), candidate, label)
            } catch {
                NSLog("Pose landmarker on \(label) failed: \(error.localizedDescription)")
            }
        }
        throw NSError(domain: "PoseLandmarker", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法初始化姿态模型"])
    }

    /// Replay path: a decoded JPEG with a synthetic timestamp.
    func detect(image: UIImage, timestampMs: Int) {
        do {
            let mpImage = try MPImage(uiImage: image)
            submit(mpImage, timestampMs: timestampMs, width: Int(image.size.width * image.scale), height: Int(image.size.height * image.scale))
        } catch {
            onError(error.localizedDescription)
        }
    }

    /// Camera path: the sample buffer plus the orientation that makes it upright.
    func detect(sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation, timestampMs: Int) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
        let rotated = orientation == .left || orientation == .right || orientation == .leftMirrored || orientation == .rightMirrored
        do {
            let mpImage = try MPImage(sampleBuffer: sampleBuffer, orientation: orientation)
            submit(mpImage, timestampMs: timestampMs, width: rotated ? bufferHeight : bufferWidth, height: rotated ? bufferWidth : bufferHeight)
        } catch {
            onError(error.localizedDescription)
        }
    }

    /// Hands a frame to the landmarker. Frames are dropped while a dead landmarker is being
    /// replaced; the next ones go to the CPU landmarker.
    private func submit(_ image: MPImage, timestampMs: Int, width: Int, height: Int) {
        ensureAlive()
        let now = Self.nowMs()
        lock.lock()
        if closed || recovering {
            lock.unlock()
            return
        }
        busy = true
        inputSizes[timestampMs] = (width, height)
        watchdog.submitted(nowMs: now)
        if !firstFrameLogged {
            firstFrameLogged = true
            NSLog("First frame handed to the \(delegateName) landmarker")
        }
        let current = landmarker!
        lock.unlock()
        do {
            try current.detectAsync(image: image, timestampInMilliseconds: timestampMs)
        } catch {
            lock.lock()
            busy = false
            inputSizes[timestampMs] = nil
            lock.unlock()
            watchdog.answered()
            recoverAsync(reason: error.localizedDescription, report: true)
        }
    }

    /// A frame unanswered for longer than the timeout means the graph died without telling us.
    private func ensureAlive() {
        if watchdog.isStalled(nowMs: Self.nowMs()) { recoverAsync(reason: "姿态识别无响应", report: false) }
    }

    /// Switches to the CPU on a background queue: the delegate runs on the graph's own thread,
    /// and releasing a dead GPU graph can take a while, so neither may happen on the caller.
    private func recoverAsync(reason: String, report: Bool) {
        lock.lock()
        if recovering || closed {
            lock.unlock()
            return
        }
        recovering = true
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            fallBackToCpu(reason: reason, report: report)
            lock.lock()
            recovering = false
            lock.unlock()
        }
    }

    /// Replaces a failed GPU landmarker with a CPU one. Frames in flight are abandoned. When
    /// already on the CPU there is nothing left to fall back to: the frames in flight are dropped
    /// and the pipeline keeps going; `report` decides whether that case is shown to the user.
    private func fallBackToCpu(reason: String, report: Bool) {
        lock.lock()
        let old = landmarker
        let currentDelegate = delegate
        lock.unlock()
        if currentDelegate == .CPU {
            NSLog("Pose landmarker on CPU: \(reason)")
            clearInFlight()
            if report { onError(reason) }
            return
        }
        NSLog("Pose landmarker on GPU failed (\(reason)); switching to CPU")
        let replacement: PoseLandmarker
        do {
            (replacement, _, _) = try Self.create([(.CPU, "CPU")], delegate: self)
        } catch {
            clearInFlight()
            onError(error.localizedDescription)
            return
        }
        lock.lock()
        landmarker = replacement
        delegate = .CPU
        delegateName = "CPU (GPU failed)"
        lock.unlock()
        clearInFlight()
        // Releasing the old landmarker closes its graph; that happens here, off the frame thread.
        _ = old
    }

    private func clearInFlight() {
        lock.lock()
        busy = false
        inputSizes.removeAll()
        lock.unlock()
        watchdog.reset()
    }

    func poseLandmarker(_ poseLandmarker: PoseLandmarker, didFinishDetection result: PoseLandmarkerResult?, timestampInMilliseconds: Int, error: Error?) {
        lock.lock()
        // A late answer from a landmarker that was already replaced is ignored.
        guard poseLandmarker === landmarker else {
            lock.unlock()
            return
        }
        busy = false
        let size = inputSizes.removeValue(forKey: timestampInMilliseconds) ?? (0, 0)
        lock.unlock()
        watchdog.answered()
        if let error {
            recoverAsync(reason: error.localizedDescription, report: true)
            return
        }
        let points = (result?.landmarks.first ?? []).map { lm in
            PosePoint(x: lm.x, y: lm.y, z: lm.z, visibility: lm.visibility?.floatValue ?? 0, presence: lm.presence?.floatValue ?? 0)
        }
        onResult(PoseFrame(timestampMs: Int64(timestampInMilliseconds), landmarks: points, imageWidth: size.0, imageHeight: size.1))
    }

    private static func nowMs() -> Int64 { Int64(CACurrentMediaTime() * 1_000) }
}
