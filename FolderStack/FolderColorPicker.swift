import SwiftUI

/// Pill of colour swatches shown above a held folder. It blurs in: the pill
/// grows out of a blur while the swatches pop in one after another.
struct FolderColorPicker: View {
    let swatches: [Tune.Swatch]
    let selected: Int
    let shown: Bool
    let pick: (Int) -> Void

    var body: some View {
        HStack(spacing: Tune.swatchSpacing) {
            ForEach(swatches.indices, id: \.self) { k in
                Button { pick(k) } label: { swatch(k) }
                    .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(.white.opacity(0.55)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 8)
        }
        .scaleEffect(shown ? 1 : 0.85, anchor: .bottom)
        .blur(radius: shown ? 0 : 14)
        .opacity(shown ? 1 : 0)
        .animation(Tune.menuSpring, value: shown)
    }

    private func swatch(_ k: Int) -> some View {
        let color = swatches[k].color
        let isSelected = k == selected
        return Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(.black.opacity(0.06), lineWidth: 0.5))
            // Selected: the dot shrinks inside a ring of its own colour.
            .padding(isSelected ? 4 : 0)
            .background { Circle().strokeBorder(color, lineWidth: 2).opacity(isSelected ? 1 : 0) }
            .frame(width: Tune.swatchSize, height: Tune.swatchSize)
            .contentShape(Circle())
            .animation(Tune.holdSpring, value: isSelected)
            .scaleEffect(shown ? 1 : 0.4)
            .blur(radius: shown ? 0 : 6)
            .opacity(shown ? 1 : 0)
            .animation(Tune.menuSpring.delay(shown ? Double(k) * 0.025 : 0), value: shown)
    }
}
