import UIKit

/// Renders coaching overlays onto a UIImage frame.
struct OverlayRenderer {

    struct Annotation {
        enum Kind {
            case ballCluster(points: [CGPoint], color: UIColor)  // toss arc points
            case apex(point: CGPoint, label: String)
            case targetWindow(rect: CGRect)                      // ideal zone from best serves
            case contactPoint(point: CGPoint, isGood: Bool)
        }
        let kind: Kind
    }

    static func render(frame: UIImage, annotations: [Annotation]) -> UIImage {
        let size = frame.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            frame.draw(at: .zero)
            let cgCtx = ctx.cgContext

            for annotation in annotations {
                switch annotation.kind {
                case .ballCluster(let points, let color):
                    drawBallTrail(ctx: cgCtx, points: points, in: size, color: color)

                case .apex(let point, let label):
                    let pt = toPixel(point, in: size)
                    drawCircle(ctx: cgCtx, at: pt, radius: 14, color: .systemGreen, filled: true)
                    drawLabel(label, at: CGPoint(x: pt.x + 18, y: pt.y - 8), color: .systemGreen)

                case .targetWindow(let rect):
                    let pixRect = toPixelRect(rect, in: size)
                    cgCtx.setStrokeColor(UIColor.systemGreen.withAlphaComponent(0.6).cgColor)
                    cgCtx.setLineWidth(2)
                    cgCtx.setLineDash(phase: 0, lengths: [6, 4])
                    cgCtx.stroke(pixRect)
                    cgCtx.setFillColor(UIColor.systemGreen.withAlphaComponent(0.1).cgColor)
                    cgCtx.fill(pixRect)

                case .contactPoint(let point, let isGood):
                    let pt = toPixel(point, in: size)
                    let color: UIColor = isGood ? .systemGreen : .systemOrange
                    drawCircle(ctx: cgCtx, at: pt, radius: 10, color: color, filled: false)
                    drawLabel("contact", at: CGPoint(x: pt.x + 14, y: pt.y - 6), color: color)
                }
            }
        }
    }

    // MARK: - Drawing helpers

    private static func drawBallTrail(ctx: CGContext, points: [CGPoint], in size: CGSize, color: UIColor) {
        guard points.count >= 2 else { return }
        let pixels = points.map { toPixel($0, in: size) }
        ctx.setStrokeColor(color.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(3)
        ctx.setLineCap(.round)
        ctx.move(to: pixels[0])
        for p in pixels.dropFirst() { ctx.addLine(to: p) }
        ctx.strokePath()

        for (i, p) in pixels.enumerated() {
            let alpha = CGFloat(i) / CGFloat(pixels.count)
            drawCircle(ctx: ctx, at: p, radius: 5, color: color.withAlphaComponent(alpha), filled: true)
        }
    }

    private static func drawCircle(ctx: CGContext, at center: CGPoint, radius: CGFloat, color: UIColor, filled: Bool) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        if filled {
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: rect)
        } else {
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(2.5)
            ctx.strokeEllipse(in: rect)
        }
    }

    private static func drawLabel(_ text: String, at point: CGPoint, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: color,
            .strokeColor: UIColor.black,
            .strokeWidth: -2
        ]
        text.draw(at: point, withAttributes: attrs)
    }

    // Normalized (0–1) → pixel coordinate (UIKit: y=0 top).
    private static func toPixel(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    private static func toPixelRect(_ rect: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: rect.minX * size.width,
            y: rect.minY * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
    }
}
