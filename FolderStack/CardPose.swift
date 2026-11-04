import SwiftUI

/// Every photo card is drawn from a single `CardPose`.
/// Each gallery state (in folder, radial, stack, fullscreen) just computes a
/// different pose, and SwiftUI interpolates between them.
///
/// Because the pose is `VectorArithmetic`, *all* fields animate together –
/// including `orbitRadius` / `orbitAngle`, which is what makes cards travel
/// along an arc (spiral out of the folder, spin in the circle, spiral into the stack)
/// instead of moving in straight lines.
struct CardPose: VectorArithmetic {
    var x: CGFloat = 0
    var y: CGFloat = 0
    /// Polar offset added on top of (x, y). 0 = no orbit.
    var orbitRadius: CGFloat = 0
    /// Degrees. Only visible while `orbitRadius > 0`.
    var orbitAngle: CGFloat = 0
    /// Card rotation in degrees.
    var rotation: CGFloat = 0
    var scale: CGFloat = 1
    var opacity: CGFloat = 1
    /// On-screen corner radius in points (independent of scale).
    var corner: CGFloat = 22

    static var zero: CardPose {
        CardPose(x: 0, y: 0, orbitRadius: 0, orbitAngle: 0, rotation: 0, scale: 0, opacity: 0, corner: 0)
    }

    static func + (l: CardPose, r: CardPose) -> CardPose {
        CardPose(x: l.x + r.x, y: l.y + r.y,
                 orbitRadius: l.orbitRadius + r.orbitRadius, orbitAngle: l.orbitAngle + r.orbitAngle,
                 rotation: l.rotation + r.rotation, scale: l.scale + r.scale,
                 opacity: l.opacity + r.opacity, corner: l.corner + r.corner)
    }

    static func - (l: CardPose, r: CardPose) -> CardPose {
        CardPose(x: l.x - r.x, y: l.y - r.y,
                 orbitRadius: l.orbitRadius - r.orbitRadius, orbitAngle: l.orbitAngle - r.orbitAngle,
                 rotation: l.rotation - r.rotation, scale: l.scale - r.scale,
                 opacity: l.opacity - r.opacity, corner: l.corner - r.corner)
    }

    mutating func scale(by rhs: Double) {
        let k = CGFloat(rhs)
        x *= k; y *= k; orbitRadius *= k; orbitAngle *= k
        rotation *= k; scale *= k; opacity *= k; corner *= k
    }

    var magnitudeSquared: Double {
        let parts: [CGFloat] = [x, y, orbitRadius, orbitAngle, rotation, scale, opacity, corner]
        return Double(parts.reduce(0) { $0 + $1 * $1 })
    }
}

/// Applies a `CardPose` to a card. Animatable, so SwiftUI re-runs `body`
/// every frame with the interpolated pose.
struct PoseModifier: ViewModifier, Animatable {
    var pose: CardPose
    let baseSize: CGSize
    var castsShadow = true

    var animatableData: CardPose {
        get { pose }
        set { pose = newValue }
    }

    func body(content: Content) -> some View {
        let radians = pose.orbitAngle * .pi / 180
        let px = pose.x + pose.orbitRadius * cos(radians)
        let py = pose.y + pose.orbitRadius * sin(radians)
        let s = max(pose.scale, 0.001)
        let alpha = min(max(pose.opacity, 0), 1)
        // Small cards (peeking in a folder) get no shadow: cheaper, and they sit under glass.
        let shadow = castsShadow ? alpha * min(max((s - 0.3) / 0.4, 0), 1) : 0

        content
            .frame(width: baseSize.width, height: baseSize.height)
            .clipShape(RoundedRectangle(cornerRadius: pose.corner / s, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: pose.corner / s, style: .continuous))
            .shadow(color: .black.opacity(0.2 * shadow), radius: 16 * shadow, x: 0, y: 10 * shadow)
            .scaleEffect(s)
            .rotationEffect(.degrees(Double(pose.rotation)))
            .opacity(Double(alpha))
            .position(x: px, y: py)
    }
}

// MARK: - Small math helpers

func normalizedDegrees(_ value: CGFloat) -> CGFloat {
    var v = value.truncatingRemainder(dividingBy: 360)
    if v > 180 { v -= 360 }
    if v <= -180 { v += 360 }
    return v
}

func rubberBand(_ x: CGFloat, limit: CGFloat) -> CGFloat {
    let sign: CGFloat = x < 0 ? -1 : 1
    return sign * limit * (1 - 1 / (abs(x) / limit * 0.55 + 1))
}
