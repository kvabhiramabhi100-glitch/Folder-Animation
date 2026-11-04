import SwiftUI

/// Thumbnail slider under the fullscreen photo. Thumbnails sit on a cylinder
/// facing the viewer: the centred one faces you, and the rest turn away and
/// shrink as they go round the curve.
struct FilmStrip: View {
    let photos: [Photo]
    let tint: Color
    /// Fractional index of the thumbnail in the middle.
    let position: CGFloat
    let onTap: (Int) -> Void

    var body: some View {
        ZStack {
            ForEach(photos.indices, id: \.self) { i in
                PhotoCardView(photo: photos[i], tint: tint)
                    .frame(width: Tune.filmThumb.width, height: Tune.filmThumb.height)
                    .clipShape(RoundedRectangle(cornerRadius: Tune.filmCorner, style: .continuous))
                    .modifier(FilmPose(index: CGFloat(i), position: position))
                    .onTapGesture { onTap(i) }
            }
        }
    }
}

/// Places one thumbnail on the cylinder. Animatable on `position`, so a jump
/// of several thumbnails rolls round the curve instead of sliding straight.
private struct FilmPose: ViewModifier, Animatable {
    let index: CGFloat
    var position: CGFloat

    var animatableData: CGFloat {
        get { position }
        set { position = newValue }
    }

    func body(content: Content) -> some View {
        let degrees = (index - position) * Tune.filmStep
        let radians = degrees * .pi / 180
        // Depth on the cylinder (0 at the front, negative going round), then perspective.
        let z = Tune.filmRadius * (cos(radians) - 1)
        let depthScale = Tune.filmViewDistance / (Tune.filmViewDistance - z)
        let fade = min(max((Tune.filmVisibleDegrees - abs(degrees)) / 25, 0), 1)

        content
            .rotation3DEffect(.degrees(Double(degrees)), axis: (x: 0, y: 1, z: 0),
                              perspective: Tune.filmPerspective)
            .scaleEffect(depthScale)
            .shadow(color: .black.opacity(0.18 * fade), radius: 8, x: 0, y: 5)
            .offset(x: Tune.filmRadius * sin(radians))
            .opacity(Double(fade))
            .zIndex(-Double(abs(index - position)))
            .allowsHitTesting(fade > 0.5)
    }
}
