import Foundation

/// Notices when the landmarker has silently stopped answering. MediaPipe's live-stream mode does
/// not always report a graph failure through its delegate (a GPU inference error, for instance,
/// can only surface when the graph is closed), so a frame that stays unanswered for longer than
/// `timeoutMs` is treated as a dead landmarker. Thread-safe. Mirrors `InFlightWatchdog.kt`.
public final class InFlightWatchdog {
    private let timeoutMs: Int64
    private let lock = NSLock()
    private var oldestUnansweredMs: Int64?
    private var unanswered = 0

    public init(timeoutMs: Int64) {
        self.timeoutMs = timeoutMs
    }

    public func submitted(nowMs: Int64) {
        lock.lock(); defer { lock.unlock() }
        if unanswered == 0 { oldestUnansweredMs = nowMs }
        unanswered += 1
    }

    public func answered() {
        lock.lock(); defer { lock.unlock() }
        if unanswered > 0 { unanswered -= 1 }
        if unanswered == 0 { oldestUnansweredMs = nil }
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        unanswered = 0
        oldestUnansweredMs = nil
    }

    public func isStalled(nowMs: Int64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let oldest = oldestUnansweredMs else { return false }
        return nowMs - oldest > timeoutMs
    }
}
