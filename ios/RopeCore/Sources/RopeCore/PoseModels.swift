import Foundation

/// One normalized MediaPipe landmark. Coordinates are 0..1 with the origin at the top-left.
public struct PosePoint: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float
    public var visibility: Float
    public var presence: Float

    public init(x: Float, y: Float, z: Float, visibility: Float, presence: Float) {
        self.x = x
        self.y = y
        self.z = z
        self.visibility = visibility
        self.presence = presence
    }
}

/// The 33 MediaPipe pose landmarks of one frame plus the image size they were computed on.
public struct PoseFrame: Equatable, Sendable {
    public var timestampMs: Int64
    public var landmarks: [PosePoint]
    public var imageWidth: Int
    public var imageHeight: Int

    public init(timestampMs: Int64, landmarks: [PosePoint], imageWidth: Int, imageHeight: Int) {
        self.timestampMs = timestampMs
        self.landmarks = landmarks
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }

    public subscript(index: Int) -> PosePoint? {
        landmarks.indices.contains(index) ? landmarks[index] : nil
    }
}

public enum MotionState: String, Sendable {
    case calibrating = "CALIBRATING"
    case ready = "READY"
    case rising = "RISING"
    case airborne = "AIRBORNE"
    case landing = "LANDING"
    case lost = "LOST"
}

public struct JumpDetection: Equatable, Sendable {
    public var jumpDetected: Bool
    public var state: MotionState
    public var quality: Float
    public var guidance: String
    public var normalizedLift: Float
    /// Jumps completed in this frame; can exceed 1 right after calibration replays buffered frames.
    public var jumpCount: Int

    public init(jumpDetected: Bool, state: MotionState, quality: Float, guidance: String, normalizedLift: Float, jumpCount: Int? = nil) {
        self.jumpDetected = jumpDetected
        self.state = state
        self.quality = quality
        self.guidance = guidance
        self.normalizedLift = normalizedLift
        self.jumpCount = jumpCount ?? (jumpDetected ? 1 : 0)
    }
}
