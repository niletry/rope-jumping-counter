import Foundation
import UIKit
import MediaPipeTasksVision
import RopeCore

/// Wraps the MediaPipe pose landmarker in live-stream mode. One frame is in flight at a time:
/// callers check `isBusy` and drop frames instead of queueing them, so latency never accumulates.
final class PoseLandmarkerProcessor: NSObject, PoseLandmarkerLiveStreamDelegate {
    private var landmarker: PoseLandmarker!
    private let onResult: (PoseFrame) -> Void
    private let onError: (String) -> Void
    private var inputSizes: [Int: (Int, Int)] = [:]
    private let lock = NSLock()

    /// Which delegate the landmarker ended up on; shown in the replay HUD for diagnostics.
    private(set) var delegateName = "CPU"

    private(set) var isBusy = false

    init(onResult: @escaping (PoseFrame) -> Void, onError: @escaping (String) -> Void) throws {
        self.onResult = onResult
        self.onError = onError
        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker_lite", ofType: "task") else {
            throw NSError(domain: "PoseLandmarker", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到姿态模型文件"])
        }
        var created: PoseLandmarker?
        var name = "CPU"
        super.init()
        // Prefer the GPU, same as Android; fall back to the CPU if it cannot be initialised.
        // The simulator's software Metal renderer makes the GPU path abort inside MediaPipe, so
        // only the CPU is tried there.
        #if targetEnvironment(simulator)
        let candidates = [(Delegate.CPU, "CPU")]
        #else
        let candidates = [(Delegate.GPU, "GPU"), (Delegate.CPU, "CPU")]
        #endif
        for (delegate, label) in candidates {
            let options = PoseLandmarkerOptions()
            options.baseOptions.modelAssetPath = modelPath
            options.baseOptions.delegate = delegate
            options.runningMode = .liveStream
            options.numPoses = 1
            options.minPoseDetectionConfidence = 0.50
            options.minPosePresenceConfidence = 0.50
            options.minTrackingConfidence = 0.50
            options.poseLandmarkerLiveStreamDelegate = self
            do {
                created = try PoseLandmarker(options: options)
                name = label
                break
            } catch {
                NSLog("Pose landmarker on \(label) failed: \(error.localizedDescription)")
            }
        }
        guard let created else {
            throw NSError(domain: "PoseLandmarker", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法初始化姿态模型"])
        }
        landmarker = created
        delegateName = name
        NSLog("Pose landmarker running on \(name)")
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

    private func submit(_ image: MPImage, timestampMs: Int, width: Int, height: Int) {
        lock.lock()
        isBusy = true
        inputSizes[timestampMs] = (width, height)
        lock.unlock()
        do {
            try landmarker.detectAsync(image: image, timestampInMilliseconds: timestampMs)
        } catch {
            lock.lock()
            isBusy = false
            inputSizes[timestampMs] = nil
            lock.unlock()
            onError(error.localizedDescription)
        }
    }

    func poseLandmarker(_ poseLandmarker: PoseLandmarker, didFinishDetection result: PoseLandmarkerResult?, timestampInMilliseconds: Int, error: Error?) {
        lock.lock()
        isBusy = false
        let size = inputSizes.removeValue(forKey: timestampInMilliseconds) ?? (0, 0)
        lock.unlock()
        if let error {
            onError(error.localizedDescription)
            return
        }
        let points = (result?.landmarks.first ?? []).map { lm in
            PosePoint(x: lm.x, y: lm.y, z: lm.z, visibility: lm.visibility?.floatValue ?? 0, presence: lm.presence?.floatValue ?? 0)
        }
        onResult(PoseFrame(timestampMs: Int64(timestampInMilliseconds), landmarks: points, imageWidth: size.0, imageHeight: size.1))
    }
}
