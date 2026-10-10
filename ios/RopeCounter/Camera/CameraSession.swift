import AVFoundation
import UIKit

/// Owns the capture session and hands BGRA sample buffers to the pose processor.
/// Frames that arrive while the landmarker is still busy are dropped, never queued.
final class CameraSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Lens { case front, back }

    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.yzrun.ropecounter.camera", qos: .userInitiated)
    private var input: AVCaptureDeviceInput?
    private(set) var lens: Lens = .front
    /// Set from the main thread before `start()`; read on the capture queue.
    weak var processor: PoseLandmarkerProcessor?
    var shouldAnalyze: () -> Bool = { true }
    var onError: ((String) -> Void)?

    static func requestAccess(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in DispatchQueue.main.async { completion(granted) } }
        default: completion(false)
        }
    }

    func configure(lens: Lens) {
        queue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1280x720
            if let input = self.input { self.session.removeInput(input) }
            self.lens = lens
            let position: AVCaptureDevice.Position = lens == .front ? .front : .back
            self.input = nil
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
               let input = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(input) {
                self.session.addInput(input)
                self.input = input
            }
            if !self.session.outputs.contains(self.output) {
                self.output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                self.output.alwaysDiscardsLateVideoFrames = true
                self.output.setSampleBufferDelegate(self, queue: self.queue)
                if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
            }
            // The data output is left unrotated and unmirrored (its defaults); MediaPipe is told
            // how to orient each buffer instead. Writing isVideoMirrored here would throw unless
            // automaticallyAdjustsVideoMirroring is disabled first.
            self.session.commitConfiguration()
            if self.input == nil {
                DispatchQueue.main.async { self.onError?("摄像头启动失败") }
            } else if !self.session.outputs.contains(self.output) {
                DispatchQueue.main.async { self.onError?("无法读取摄像头画面") }
            }
        }
    }

    func start() {
        queue.async { if !self.session.isRunning { self.session.startRunning() } }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    func switchLens() {
        configure(lens: lens == .front ? .back : .front)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard shouldAnalyze(), let processor, !processor.isBusy else { return }
        let ms = Int(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1_000)
        // Portrait app: the sensor delivers landscape buffers; `.right` rotates them upright for
        // the back camera, `.leftMirrored` for the front camera (which is physically mirrored).
        let orientation: UIImage.Orientation = lens == .front ? .leftMirrored : .right
        processor.detect(sampleBuffer: sampleBuffer, orientation: orientation, timestampMs: ms)
    }
}
