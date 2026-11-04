import SwiftUI

// MARK: - Style

struct FolderStyle {
    var backTop: Color
    var backBottom: Color
    var glassTop: Color
    var glassBottom: Color
    var placeholder: Color
    // Presets (.graphite / .lavender / .sky / .tinted) live in Tuning.swift.
}

// MARK: - Shapes

/// Front pocket of the folder: high on the left, stepping down with a short
/// curve just right of centre, and tapering slightly toward the bottom.
struct FolderFrontShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let topR = h * 0.13            // top corners
        let bottomR = h * 0.10         // bottom corners
        let lowTop = h * 0.22          // how far the right part drops
        let stepX = w * 0.55           // where the step starts
        let stepW = w * 0.09           // width of the step curve
        let taper = w * 0.06           // bottom inset on each side

        let tl = CGPoint(x: 0, y: 0), tr = CGPoint(x: w, y: lowTop)
        let br = CGPoint(x: w - taper, y: h), bl = CGPoint(x: taper, y: h)
        func toward(_ a: CGPoint, _ b: CGPoint, _ d: CGFloat) -> CGPoint {
            let len = max(hypot(b.x - a.x, b.y - a.y), 0.001)
            return CGPoint(x: a.x + (b.x - a.x) * d / len, y: a.y + (b.y - a.y) * d / len)
        }

        var p = Path()
        p.move(to: CGPoint(x: topR, y: 0))
        p.addLine(to: CGPoint(x: stepX, y: 0))
        p.addCurve(to: CGPoint(x: stepX + stepW, y: lowTop),
                   control1: CGPoint(x: stepX + stepW * 0.55, y: 0),
                   control2: CGPoint(x: stepX + stepW * 0.45, y: lowTop))
        p.addLine(to: CGPoint(x: w - topR, y: lowTop))
        p.addQuadCurve(to: toward(tr, br, topR), control: tr)
        p.addLine(to: toward(br, tr, bottomR))
        p.addQuadCurve(to: toward(br, bl, bottomR), control: br)
        p.addLine(to: toward(bl, br, bottomR))
        p.addQuadCurve(to: toward(bl, tl, bottomR), control: bl)
        p.addLine(to: toward(tl, bl, topR))
        p.addQuadCurve(to: CGPoint(x: topR, y: 0), control: tl)
        p.closeSubpath()
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

// MARK: - Views

/// Solid back plate. Photos sit between this and the glass front.
struct FolderBackView: View {
    let style: FolderStyle

    var body: some View {
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) * 0.14
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(LinearGradient(colors: [style.backTop, style.backBottom],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 0.8)
                )
        }
    }
}

/// Glass pocket tint. The frost itself comes from the gallery, which draws a
/// blurred copy of the tucked-in photos clipped to `FolderFrontShape` just
/// below this layer (a material only showed them as faint tints).
/// (On iOS 26 you can try `.glassEffect(.clear, in: FolderFrontShape())` instead.)
struct GlassFolderFront: View {
    let style: FolderStyle

    var body: some View {
        let shape = FolderFrontShape()
        shape
            .fill(LinearGradient(colors: [style.glassTop, style.glassBottom],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(   // soft sheen across the top
                shape.fill(LinearGradient(colors: [.white.opacity(0.20), .clear],
                                          startPoint: .top, endPoint: .center))
            )
            .overlay(   // bright rim on the top edge
                shape.stroke(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.04)],
                                            startPoint: .top, endPoint: .bottom),
                             lineWidth: 1)
            )
    }
}
