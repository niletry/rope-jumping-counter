import XCTest
@testable import RopeCore

/// Offline regression harness, mirror of the Android ReplayHarnessTest. Replays a landmark CSV
/// through JumpDetector, prints per-segment counts against ground truth and writes a per-frame
/// trace next to the CSV so the two platforms' detectors can be diffed line by line.
/// Run with: REPLAY_CSV=/path/landmarks.csv swift test --filter ReplayHarness
final class ReplayHarnessTests: XCTestCase {
    // Ground truth for the 2026-10-09 test video: segment boundaries (ms) are the midpoints of
    // the four interruptions, counts come from the reference app's on-screen counter.
    private let segmentEnds: [Int64] = [3_700, 20_950, 36_550, 50_600, 61_000]
    private let truth = [4, 43, 29, 29, 18]

    func testReplayDumpedLandmarks() throws {
        guard let path = ProcessInfo.processInfo.environment["REPLAY_CSV"], FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("no REPLAY_CSV given")
        }
        let frames = LandmarkCSV.frames(from: try String(contentsOfFile: path, encoding: .utf8))
        let detector = JumpDetector()
        var jumps: [Int64] = []
        var trace = ""
        for f in frames {
            let d = detector.process(f)
            trace += "\(f.timestampMs),\(d.state.rawValue),\(String(format: "%.4f", d.normalizedLift)),\(d.jumpDetected ? 1 : 0),\(d.guidance)\n"
            if d.jumpDetected { jumps.append(f.timestampMs) }
        }
        var seg = [Int](repeating: 0, count: 5)
        for t in jumps {
            seg[max(segmentEnds.firstIndex { t <= $0 } ?? 0, 0)] += 1
        }
        let diffs = seg.indices.map { String(format: "%+d", seg[$0] - truth[$0]) }
        let report = """
        REPLAY frames=\(frames.count)
        truth  \(truth.map(String.init).joined(separator: " ")) total \(truth.reduce(0, +))
        swift  \(diffs.joined(separator: " ")) total \(jumps.count)

        """
        print(report)
        try trace.write(toFile: path + ".swift.trace.csv", atomically: true, encoding: .utf8)
        try jumps.map(String.init).joined(separator: "\n").write(toFile: path + ".swift.jumps.txt", atomically: true, encoding: .utf8)
    }
}
