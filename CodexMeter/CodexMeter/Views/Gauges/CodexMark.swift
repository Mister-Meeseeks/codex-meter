import SwiftUI

/// Six-petal blossom — an approximation of OpenAI's hex-knot brand
/// pattern. Three full-height lens-shape ellipses rotated by 0°, 60°,
/// and 120° overlap to form six outer petal tips with 6-fold symmetry;
/// the hexagonal silhouette is implied by the tip positions, not drawn
/// explicitly. Drawn with `Canvas` so it stays crisp at the 4–8pt
/// sizes used as a brand watermark on `VesselGauge` and `PacingArc`.
///
/// Color is template-friendly — pass `.primary` for menu-bar template
/// tinting, or any explicit color.
struct CodexMark: View {
    var color: Color = .primary
    var size: CGFloat = 4
    var lineWidth: CGFloat = 0.7

    var body: some View {
        Canvas { context, canvas in
            let cx = canvas.width / 2
            let cy = canvas.height / 2
            // Inset by half the stroke so the outermost edges land on the
            // bounding box, avoiding clipped strokes.
            let r = min(canvas.width, canvas.height) / 2 - lineWidth / 2

            // Three lens-shape ellipses rotated by 0°, 60°, and 120°. Each
            // lens is full-height (2r) and ~half the radius wide. The
            // overlap creates six outer tips at hexagonal vertices, which
            // is what reads as the Codex blossom silhouette.
            let lensWidth = r * 0.55
            let lensHeight = r * 2
            let lensRect = CGRect(
                x: -lensWidth / 2,
                y: -lensHeight / 2,
                width: lensWidth,
                height: lensHeight
            )
            for i in 0..<3 {
                context.drawLayer { ctx in
                    ctx.translateBy(x: cx, y: cy)
                    ctx.rotate(by: .radians(Double(i) * .pi / 3))
                    ctx.stroke(
                        Path(ellipseIn: lensRect),
                        with: .color(color),
                        style: StrokeStyle(lineWidth: lineWidth)
                    )
                }
            }
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
        CodexMark(size: 64, lineWidth: 3)
    }
    .padding()
    .background(.background)
}
