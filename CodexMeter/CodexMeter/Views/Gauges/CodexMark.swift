import SwiftUI

/// Hexagonal outline, a tiny approximation of OpenAI's hex-knot brand
/// pattern. Drawn with `Canvas` so it stays crisp at the 4–8pt sizes
/// used as a brand watermark on `VesselGauge`. Color is template-friendly
/// — pass `.primary` for menu-bar template tinting, or any explicit color.
///
/// Structurally analogous to the previous `ClaudeMark` (a sunburst): the
/// call sites in `VesselGauge` and `PacingArc` use the same size + line
/// weight, so the visual layout is unchanged.
struct CodexMark: View {
    var color: Color = .primary
    var size: CGFloat = 4
    var lineWidth: CGFloat = 0.7

    var body: some View {
        Canvas { context, canvas in
            let cx = canvas.width / 2
            let cy = canvas.height / 2
            // Inset by half the stroke so the polygon's outer edge lands
            // exactly on the bounding box, avoiding clipped strokes.
            let r = min(canvas.width, canvas.height) / 2 - lineWidth / 2
            var path = Path()
            for i in 0..<6 {
                // Start at the top vertex (12 o'clock) and walk clockwise.
                let angle = Double(i) * .pi / 3 - .pi / 2
                let x = cx + CGFloat(cos(angle)) * r
                let y = cy + CGFloat(sin(angle)) * r
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.closeSubpath()
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round)
            )
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 16) {
        CodexMark(size: 4)
        CodexMark(size: 8)
        CodexMark(size: 16)
        CodexMark(size: 32, lineWidth: 2)
    }
    .padding()
    .background(.background)
}
