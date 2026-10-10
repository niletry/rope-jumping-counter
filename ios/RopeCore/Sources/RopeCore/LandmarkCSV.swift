import Foundation

/// One frame per line: `timestampMs,imageWidth,imageHeight,` followed by 33 groups of
/// `x,y,z,visibility,presence`. Same layout the Android ReplayHarnessTest reads, so a dump from
/// either platform can be replayed through either detector.
public enum LandmarkCSV {
    public static let landmarkCount = 33

    public static func line(for frame: PoseFrame) -> String {
        var columns: [String] = [String(frame.timestampMs), String(frame.imageWidth), String(frame.imageHeight)]
        columns.reserveCapacity(3 + landmarkCount * 5)
        for i in 0..<landmarkCount {
            let p = frame[i] ?? PosePoint(x: 0, y: 0, z: 0, visibility: 0, presence: 0)
            columns.append(contentsOf: [p.x.description, p.y.description, p.z.description, p.visibility.description, p.presence.description])
        }
        return columns.joined(separator: ",")
    }

    public static func frames(from text: String) -> [PoseFrame] {
        text.split(whereSeparator: \.isNewline).compactMap { line -> PoseFrame? in
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cols.count >= 3 + landmarkCount * 5,
                  let ts = Int64(cols[0]), let w = Int(cols[1]), let h = Int(cols[2]) else { return nil }
            var points: [PosePoint] = []
            points.reserveCapacity(landmarkCount)
            for i in 0..<landmarkCount {
                let b = 3 + i * 5
                guard let x = Float(cols[b]), let y = Float(cols[b + 1]), let z = Float(cols[b + 2]),
                      let v = Float(cols[b + 3]), let pr = Float(cols[b + 4]) else { return nil }
                points.append(PosePoint(x: x, y: y, z: z, visibility: v, presence: pr))
            }
            return PoseFrame(timestampMs: ts, landmarks: points, imageWidth: w, imageHeight: h)
        }
    }
}
