import XCTest
@testable import RopeCore

final class LandmarkCSVTests: XCTestCase {
    func testFrameRoundTripsThroughOneLine() {
        var points: [PosePoint] = []
        for i in 0..<33 {
            let f = Float(i)
            points.append(PosePoint(x: f / 100, y: f / 200, z: -f / 300, visibility: 0.5, presence: 0.75))
        }
        let frame = PoseFrame(timestampMs: 1_234, landmarks: points, imageWidth: 1080, imageHeight: 1920)
        let line = LandmarkCSV.line(for: frame)
        XCTAssertTrue(line.hasPrefix("1234,1080,1920,"))
        XCTAssertEqual(line.split(separator: ",").count, 3 + 33 * 5)
        XCTAssertEqual(LandmarkCSV.frames(from: line + "\n"), [frame])
    }

    func testShortLinesAreSkipped() {
        XCTAssertEqual(LandmarkCSV.frames(from: "1,2,3\n\n"), [])
    }
}
