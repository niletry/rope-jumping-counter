import SwiftUI
import RopeCore

/// Draws the MediaPipe skeleton over the preview. Same connections, colour and gate as Android.
struct PoseOverlay: View {
    let frame: PoseFrame?
    let mirrorHorizontally: Bool

    private static let skeleton = Color(red: 0xB8 / 255, green: 0xF3 / 255, blue: 0x5A / 255)
    private static let minVisibility: Float = 0.35
    private static let importantPoints = [0, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]
    private static let connections: [(Int, Int)] = [
        (11, 12), (11, 13), (13, 15), (12, 14), (14, 16), (11, 23),
        (12, 24), (23, 24), (23, 25), (25, 27), (24, 26), (26, 28),
    ]

    var body: some View {
        Canvas { context, size in
            guard let current = frame, current.imageWidth > 0, current.imageHeight > 0 else { return }
            let scale = max(size.width / CGFloat(current.imageWidth), size.height / CGFloat(current.imageHeight))
            let offsetX = (size.width - CGFloat(current.imageWidth) * scale) / 2
            let offsetY = (size.height - CGFloat(current.imageHeight) * scale) / 2

            func mapped(_ index: Int) -> CGPoint? {
                guard let point = current[index], point.visibility >= Self.minVisibility else { return nil }
                let x = mirrorHorizontally ? 1 - point.x : point.x
                return CGPoint(x: offsetX + CGFloat(x) * CGFloat(current.imageWidth) * scale,
                               y: offsetY + CGFloat(point.y) * CGFloat(current.imageHeight) * scale)
            }

            for (a, b) in Self.connections {
                guard let start = mapped(a), let end = mapped(b) else { continue }
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: .color(Self.skeleton.opacity(0.86)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            for index in Self.importantPoints {
                guard let p = mapped(index) else { continue }
                context.fill(Path(ellipseIn: CGRect(x: p.x - 6.5, y: p.y - 6.5, width: 13, height: 13)), with: .color(.white))
                context.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(Self.skeleton))
            }
        }
        .allowsHitTesting(false)
    }
}
