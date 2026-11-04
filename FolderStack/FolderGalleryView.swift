import SwiftUI

// MARK: - State

enum GalleryPhase: Equatable {
    case closed      // photos tucked in the folder (peeking)
    case peek        // just tapped: photos rise inside the pocket (ref image 1)
    case bundle      // popped out as a compact bundle, about to fan
    case fan         // photos fanned out like a hand of cards (ref image 2)
    case radial      // photos in a ring (every 2nd open)
    case stack       // stacked cards, swipe to send the top card behind
    case fullscreen  // tapped card fills the screen, paged carousel
}

/// How card springs are delayed when `phaseKey` changes.
/// `.strip`: every card uses `stripSpring`. `.leave`: only the album going home staggers.
private enum Stagger { case none, strip, open, close, leave }

/// Which arc the last open used. Upright poses keep the matching orbit angle (with
/// radius 0, so it's invisible) so cards leave and rejoin that arc smoothly.
private enum Arc { case fan, ring }

private struct FolderMetrics {
    let x: CGFloat
    let base: CGFloat      // bottom of the glass front
    let scale: CGFloat
    let emphasis: CGFloat  // 1 = centred, 0 = one slot away or more
    var rotation: CGFloat = 0  // degrees, only while held and dragged around
    var frontTop: CGFloat { base - Tune.frontSize.height * scale }
    /// Centre of the glass front; the folder tilts around it.
    var pivot: CGPoint { CGPoint(x: x, y: base - Tune.frontSize.height * scale / 2) }

    func anchor(_ L: GalleryLayout) -> UnitPoint {
        UnitPoint(x: pivot.x / max(L.w, 1), y: pivot.y / max(L.h, 1))
    }

    /// `p` turned with the folder.
    func rotate(_ p: CGPoint) -> CGPoint {
        guard rotation != 0 else { return p }
        let r = rotation * .pi / 180, dx = p.x - pivot.x, dy = p.y - pivot.y
        return CGPoint(x: pivot.x + dx * cos(r) - dy * sin(r), y: pivot.y + dx * sin(r) + dy * cos(r))
    }
}

private struct Fling: Equatable {
    let id: UUID
    let offset: CGSize
}

/// Sleeps for `ms` milliseconds. Returns false if the task was cancelled.
@MainActor
private func pause(_ ms: Int) async -> Bool {
    do {
        try await Task.sleep(for: .milliseconds(ms))
        return true
    } catch {
        return false
    }
}

// MARK: - View

struct FolderGalleryView: View {
    let albums: [Album]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var activeAlbum = 1   // starts on the 2nd folder, so both neighbours show
    /// The album that was active before the last switch; its photos use the closing stagger.
    @State private var leavingAlbum: Int? = nil
    @State private var phase: GalleryPhase = .closed
    /// Top card of each album's deck. Kept per album, so a deck keeps its order
    /// when it goes home and when it comes out again.
    @State private var fronts: [Int: Int] = [:]
    /// Album whose photos render *above* the folder fronts (i.e. they're out).
    @State private var liftedAlbum: Int? = nil
    @State private var openCount = 0
    /// The user wants photos out. Survives album switches (which briefly close).
    @State private var opened = false
    /// Strip sits at the bottom. Separate from `phase` so it can rise after the photos are home.
    @State private var stripLowered = false
    /// Fullscreen vertical drag: the other photos show at their deck slots, fading in.
    @State private var showDeck = false
    @State private var arc: Arc = .fan
    /// The animation currently moving the strip. Photos in other folders use it
    /// too (with no delay) so they stay glued to their folders.
    @State private var stripSpring = Tune.cardSpring
    /// Accumulated ring rotation per album, in degrees. It only ever grows and every
    /// pose derives its rotation from it, so an interrupted spin never has to be
    /// unwound or reset.
    @State private var spin: [Int: CGFloat] = [:]
    /// Bumped on every phase transition so cards can apply a staggered spring.
    @State private var phaseKey = 0
    @State private var stagger: Stagger = .none
    /// The running timed sequence (pop-out lift, radial reveal, album switch).
    @State private var sequence: Task<Void, Never>? = nil
    /// Pending "tuck behind the deck" after a swipe.
    @State private var flingTask: Task<Void, Never>? = nil

    // Press and hold a folder: colour menu
    /// Chosen palette index per album (nil = the album's own style).
    @State private var colorChoice: [Int: Int] = [:]
    /// Folder drawn above the blurred backdrop. Stays set until the menu has faded out.
    @State private var menuAlbum: Int? = nil
    @State private var menuShown = false
    /// Finger still down after a hold: the folder follows it.
    @State private var holding = false
    @State private var pressStarted = false
    @State private var holdDrag: CGSize = .zero
    @State private var holdTask: Task<Void, Never>? = nil
    @State private var menuTask: Task<Void, Never>? = nil

    // Fullscreen thumbnail slider
    /// Fractional offset of the slider from `frontIndex` while it's dragged.
    @State private var filmDrag: CGFloat = 0
    /// `frontIndex` when the slider drag started.
    @State private var filmStart: Int? = nil

    // Gesture state
    @State private var cardDrag: CGSize = .zero
    @State private var dragAxis: Axis? = nil
    @State private var fling: Fling? = nil
    @State private var stripDrag: CGFloat = 0
    @GestureState private var cardGestureActive = false
    @GestureState private var stripGestureActive = false

    var body: some View {
        GeometryReader { geo in
            let L = GalleryLayout(size: geo.size)

            ZStack {
                Tune.background

                // 0. Soft folder shadows. One shape per folder (not per layer), since
                // the glass is translucent and layered shadows would show through it.
                ForEach(albums.indices, id: \.self) { a in
                    let m = folderMetrics(a, L)
                    let fh = Tune.frontSize.height * m.scale
                    FolderFrontShape()
                        .fill(.black.opacity(menuAlbum == a && menuShown ? 0.24 : 0.16))
                        .frame(width: Tune.frontSize.width * m.scale * 0.94, height: fh * 0.9)
                        .blur(radius: (menuAlbum == a && menuShown ? 18 : 12) * m.scale)
                        .position(x: m.x, y: m.base - fh / 2 + (menuAlbum == a && menuShown ? 18 : 10) * m.scale)
                        .rotationEffect(.degrees(m.rotation), anchor: m.anchor(L))
                        .allowsHitTesting(false)
                        .zIndex(menuAlbum == a ? 50.5 : 0)
                }

                // 1. Folder back plates: a narrower dark slab that shows above the glass.
                ForEach(albums.indices, id: \.self) { a in
                    let m = folderMetrics(a, L)
                    let style = style(a)
                    let top = m.frontTop - Tune.backRise * m.scale
                    let bottom = m.base - 6 * m.scale
                    // Full-width body behind the pocket (starts below the step, so it never shows
                    // above the glass) keeps the glass evenly dark when the folder is empty.
                    let bodyTop = m.frontTop + Tune.frontSize.height * 0.22 * m.scale
                    ZStack {
                        FolderBackView(style: style)
                            .frame(width: Tune.frontSize.width * Tune.backWidth * m.scale, height: bottom - top)
                            .position(x: m.x, y: (top + bottom) / 2)
                        FolderBackView(style: style)
                            .frame(width: Tune.frontSize.width * 0.86 * m.scale, height: bottom - bodyTop)
                            .position(x: m.x, y: (bodyTop + bottom) / 2)
                    }
                    .rotationEffect(.degrees(m.rotation), anchor: m.anchor(L))
                    .allowsHitTesting(false)
                    .zIndex(menuAlbum == a ? 51 : 0)
                }

                // 2. Photos (z 1 when inside a folder, z 10+ when out)
                ForEach(albums.indices, id: \.self) { a in
                    ForEach(albums[a].photos.indices, id: \.self) { i in
                        if shouldRender(a, i) {
                            photoView(a, i, L)
                        }
                    }
                }

                // 2a. Pocket: an opaque fill in the back plate's colour right under the
                // frost. It hides the sharp photos inside the folder and keeps an empty
                // folder evenly dark behind the translucent glass.
                ForEach(albums.indices, id: \.self) { a in
                    let m = folderMetrics(a, L)
                    let fh = Tune.frontSize.height * m.scale
                    FolderFrontShape()
                        .fill(style(a).backBottom)
                        .frame(width: Tune.frontSize.width * m.scale, height: fh)
                        .position(x: m.x, y: m.base - fh / 2)
                        .rotationEffect(.degrees(m.rotation), anchor: m.anchor(L))
                        .allowsHitTesting(false)
                        .zIndex(menuAlbum == a ? 52.4 : 1.4)
                }

                // 2b. Frost: a blurred copy of the folder's photos, clipped to the glass.
                // The copies share the real cards' poses and springs, so a card
                // passing behind the glass is seen blurred through it.
                ForEach(albums.indices, id: \.self) { a in
                    if abs(a - activeAlbum) <= 2 || a == leavingAlbum {
                        let m = folderMetrics(a, L)
                        let fh = Tune.frontSize.height * m.scale
                        ZStack {
                            ForEach(albums[a].photos.indices, id: \.self) { i in
                                if shouldRender(a, i) { frostView(a, i, L) }
                            }
                        }
                        .blur(radius: Tune.glassBlur * m.scale)
                        .mask {
                            FolderFrontShape()
                                .frame(width: Tune.frontSize.width * m.scale, height: fh)
                                .position(x: m.x, y: m.base - fh / 2)
                                .rotationEffect(.degrees(m.rotation), anchor: m.anchor(L))
                        }
                        // Hidden (and skipped by the renderer) while the photos are well clear of the folder.
                        .opacity(liftedAlbum == a && (phase == .stack || phase == .fullscreen) ? 0 : 1)
                        .allowsHitTesting(false)
                        .zIndex(menuAlbum == a ? 52.5 : 1.5)
                    }
                }

                // 3. Glass fronts + labels
                ForEach(albums.indices, id: \.self) { a in
                    let m = folderMetrics(a, L)
                    let fh = Tune.frontSize.height * m.scale
                    GlassFolderFront(style: style(a))
                        .frame(width: Tune.frontSize.width * m.scale, height: fh)
                        .position(x: m.x, y: m.base - fh / 2)
                        .rotationEffect(.degrees(m.rotation), anchor: m.anchor(L))
                        .allowsHitTesting(false)
                        .zIndex(menuAlbum == a ? 53 : 2)

                    Text(albums[a].title)
                        .font(.system(size: Tune.labelSize, weight: a == activeAlbum ? .medium : .regular))
                        .foregroundStyle(Color.primary.opacity(Double(0.45 + 0.45 * m.emphasis)))
                        .fixedSize()
                        .position(x: m.x, y: m.base + Tune.labelGap)
                        .rotationEffect(.degrees(m.rotation), anchor: m.anchor(L))
                        .allowsHitTesting(false)
                        .zIndex(menuAlbum == a ? 53 : 2)
                }

                // 3b. Fade veils. Each folder (back, peeks, glass, label) is faded by a soft
                // background-coloured veil instead of per-layer opacity, so translucent
                // layers never show through each other. Photos that are out sit above it.
                ForEach(albums.indices, id: \.self) { a in
                    let m = folderMetrics(a, L)
                    // Generous padding so lifted peeks and the glass shadow are covered too.
                    let top = m.frontTop - (Tune.liftedPeekRise + 16) * m.scale
                    let bottom = m.base + Tune.labelGap + 26
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Tune.background)
                        .frame(width: Tune.frontSize.width * m.scale + 64, height: bottom - top)
                        .blur(radius: Tune.veilBlur)
                        .position(x: m.x, y: (top + bottom) / 2)
                        .opacity(Double(1 - folderOpacity(m)))
                        .allowsHitTesting(false)
                        .zIndex(3)
                }

                // 4. Folder strip touch area (tap + horizontal scroll)
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: L.w, height: Tune.frontSize.height + 90)
                    .position(x: L.w / 2, y: stripBase(L) - Tune.frontSize.height / 2 + 10)
                    .gesture(stripGesture(L))
                    .allowsHitTesting(phase != .fullscreen)
                    .zIndex(5)

                // 5. Press-and-hold menu: everything but the held folder blurs behind a
                // frosted backdrop, and the colour pill blurs in above the folder.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.03))
                    .opacity(menuShown ? 1 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { dismissMenu() }
                    .allowsHitTesting(menuShown && !holding)
                    .zIndex(50)

                colorPicker(L)
                    .zIndex(60)

                // 6. Thumbnail slider under the fullscreen photo. It rises out of a blur
                // with fullscreen and fades as the photo is dragged down.
                FilmStrip(photos: albums[activeAlbum].photos, tint: style(activeAlbum).placeholder,
                          position: CGFloat(frontIndex) + filmDrag, onTap: filmTapped)
                    .frame(width: L.w, height: Tune.filmThumb.height + 40)
                    .contentShape(Rectangle())
                    .gesture(filmGesture(albums[activeAlbum].photos.count))
                    .blur(radius: phase == .fullscreen ? 0 : 10)
                    .offset(y: phase == .fullscreen ? 0 : 40)
                    .opacity(Double(filmOpacity))
                    .position(x: L.w / 2, y: L.h - Tune.filmBottomInset)
                    .allowsHitTesting(phase == .fullscreen && dragAxis != .vertical)
                    .zIndex(30)
            }
            .onChange(of: cardGestureActive) { _, active in
                // The system cancelled a card drag without calling onEnded: spring back.
                guard !active, dragAxis != nil else { return }
                snapBack()
            }
            .onChange(of: stripGestureActive) { _, active in
                // The system cancelled a strip press without calling onEnded.
                guard !active, pressStarted else { return }
                endPress()
                if stripDrag != 0 { withAnimation(spring(Tune.cardSpring)) { stripDrag = 0 } }
            }
            #if DEBUG
            .task {
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-SelfTest") { await runSelfTest(L) }
                if args.contains("-Demo") { await runDemo(L) }
            }
            #endif
        }
        .ignoresSafeArea()
        .task { ImageStore.shared.prefetch(albums, first: activeAlbum) }
    }

    /// Top of the active stack, or the current page in fullscreen.
    private var frontIndex: Int {
        get { fronts[activeAlbum, default: 0] }
        nonmutating set { fronts[activeAlbum] = newValue }
    }

    // MARK: Photo

    @ViewBuilder
    private func photoView(_ a: Int, _ i: Int, _ L: GalleryLayout) -> some View {
        let n = albums[a].photos.count
        PhotoCardView(photo: albums[a].photos[i], tint: style(a).placeholder)
            .modifier(PoseModifier(pose: pose(a, i, n, L), baseSize: L.cardSize,
                                   castsShadow: !isBuried(a, i, n)))
            .animation(cardAnimation(a, i, n), value: phaseKey)
            .onTapGesture { cardTapped() }
            .gesture(cardDragGesture(n, L))
            .allowsHitTesting(isInteractive(a, i, n))
            .zIndex(zOrder(a, i, n))
    }

    /// Blurred stand-in for a card, seen through the glass (see layer 2b).
    private func frostView(_ a: Int, _ i: Int, _ L: GalleryLayout) -> some View {
        PhotoCardView(photo: albums[a].photos[i], tint: style(a).placeholder)
            .modifier(PoseModifier(pose: pose(a, i, albums[a].photos.count, L), baseSize: L.cardSize,
                                   castsShadow: false))
            .animation(cardAnimation(a, i, albums[a].photos.count), value: phaseKey)
            .zIndex(zOrder(a, i, albums[a].photos.count))
    }

    private func style(_ a: Int) -> FolderStyle {
        colorChoice[a].map { Tune.palette[$0].style } ?? albums[a].style
    }

    /// Cards hidden under the 4th deck slot skip their shadow, so shadows don't pile up.
    private func isBuried(_ a: Int, _ i: Int, _ n: Int) -> Bool {
        a == activeAlbum && phase == .stack && stackRel(i, n) >= Tune.stackSlots.count
            && fling?.id != albums[a].photos[i].id
    }

    /// Only the active album and its neighbours are fully rendered. Other folders
    /// just draw their 3 peeking cards (the rest are invisible anyway).
    private func shouldRender(_ a: Int, _ i: Int) -> Bool {
        deckRel(a, i, albums[a].photos.count) < Tune.peeks.count || abs(a - activeAlbum) <= 1 || a == leavingAlbum
    }

    // MARK: Poses

    private func pose(_ a: Int, _ i: Int, _ n: Int, _ L: GalleryLayout) -> CardPose {
        let p = (a == activeAlbum) ? phase : .closed
        switch p {
        case .closed:     return closedPose(a, i, n, L, lifted: false)
        case .peek:       return closedPose(a, i, n, L, lifted: true)
        case .bundle:     return fanPose(a, i, n, L, bundled: true)
        case .fan:        return fanPose(a, i, n, L)
        case .radial:     return radialPose(a, i, n, L)
        case .stack:      return stackPose(a, i, n, L)
        case .fullscreen: return fullscreenPose(a, i, n, L)
        }
    }

    /// Peeking out of the top of the folder. `lifted` raises them for the
    /// moment between the tap and the pop-out (ref image 1).
    private func closedPose(_ a: Int, _ i: Int, _ n: Int, _ L: GalleryLayout, lifted: Bool) -> CardPose {
        let m = folderMetrics(a, L)
        let s = m.scale
        // The top 3 cards of the deck peek out, the top one in front.
        let rel = deckRel(a, i, n)
        let peeks = rel < Tune.peeks.count
        let peek = Tune.peeks[min(rel, Tune.peeks.count - 1)]
        // Photos that don't peek sit fully inside the pocket, below the step, so
        // they fly home behind the glass instead of fading out mid-air.
        let width = (peeks ? (lifted ? Tune.liftedPeekWidth : Tune.peekWidth) : Tune.pocketWidth) * s
        let height = width * Tune.cardAspect
        let rise = peeks ? (lifted ? Tune.liftedPeekRise : Tune.peekRise) * s
                         : -Tune.frontSize.height * 0.22 * s
        // Turned with the folder while it's held and dragged around.
        let p = m.rotate(CGPoint(x: m.x + (peeks ? peek.dx * s : 0),
                                 y: m.frontTop - rise + height / 2 + (peeks ? peek.dy * s : 0)))
        return CardPose(
            x: p.x, y: p.y,
            orbitRadius: 0,
            orbitAngle: arc == .ring ? ringAngle(a, i, n) - 90 : fanAngle(i, n),  // so cards leave along their arc
            rotation: peek.rotation + m.rotation + turns(a, i, n),
            scale: width / L.cardSize.width,
            opacity: 1,
            corner: Tune.peekCorner)
    }

    /// A hand of cards above the folder (ref image 2). The top card is upright in
    /// the middle; the rest alternate right/left, tilting further out. Cards sit on
    /// a circle around a pivot below, so they fan out of and collapse along arcs.
    /// `bundled`: the same arc squeezed into a compact bundle, so spreading into
    /// the fan swings the cards out around the pivot.
    private func fanPose(_ a: Int, _ i: Int, _ n: Int, _ L: GalleryLayout, bundled: Bool = false) -> CardPose {
        let angle = fanAngle(i, n, step: bundled ? Tune.bundleStep : Tune.fanStep)
        let tilt = bundled ? fanSide(i, n) * Tune.bundleTilt : 0
        return CardPose(
            x: L.w / 2, y: L.h * Tune.fanCenterY + Tune.fanRadius,
            orbitRadius: Tune.fanRadius, orbitAngle: angle,
            rotation: angle + 90 + tilt + turns(a, i, n),
            scale: bundled ? Tune.bundleScale : Tune.fanScale, opacity: 1, corner: Tune.stackCorner)
    }

    /// Orbit angle of a card in the fan (-90° = straight up).
    private func fanAngle(_ i: Int, _ n: Int, step: CGFloat = Tune.fanStep) -> CGFloat {
        -90 + fanSide(i, n) * step
    }

    /// Fan slot: 0 for the top card, then +1, -1, +2, -2 …
    private func fanSide(_ i: Int, _ n: Int) -> CGFloat {
        let rel = stackRel(i, n)
        return CGFloat(rel % 2 == 1 ? (rel + 1) / 2 : -(rel / 2))
    }

    /// Orbit angle upright poses keep, so cards rejoin the arc they came from.
    private func restAngle(_ a: Int, _ i: Int, _ n: Int) -> CGFloat {
        arc == .ring ? ringAngle(a, i, n) + 90 : fanAngle(i, n)
    }

    /// Cards in a ring around the stack centre, each facing outward (ref 10).
    private func radialPose(_ a: Int, _ i: Int, _ n: Int, _ L: GalleryLayout) -> CardPose {
        CardPose(
            x: L.stackCenter.x, y: L.stackCenter.y,
            orbitRadius: L.radialRadius, orbitAngle: ringAngle(a, i, n),
            rotation: ringRotation(a, i, n),
            scale: Tune.radialScale, opacity: 1, corner: Tune.radialCorner)
    }

    /// Stacked deck (ref 7). Top card follows the finger.
    private func stackPose(_ a: Int, _ i: Int, _ n: Int, _ L: GalleryLayout) -> CardPose {
        let rel = stackRel(i, n)
        let slot = Tune.stackSlots[min(rel, Tune.stackSlots.count - 1)]
        // 4 depths are visible. Deeper cards (and the one just tucked) wait in the
        // last slot under the 4th card: opaque, so they never fade in mid-flight.

        var pose = CardPose(
            x: L.stackCenter.x + slot.dx, y: L.stackCenter.y + slot.dy,
            orbitRadius: 0, orbitAngle: restAngle(a, i, n),   // so cards collapse along their arc
            rotation: slot.rotation + turns(a, i, n), scale: slot.scale,
            opacity: 1, corner: Tune.stackCorner)

        if rel == 0 {
            pose.x += cardDrag.width
            pose.y += cardDrag.height
            pose.rotation += cardDrag.width / Tune.swipeRotationDivisor
        }
        if let fling, fling.id == albums[a].photos[i].id {
            pose.x += fling.offset.width
            pose.y += fling.offset.height
            pose.rotation += fling.offset.width / Tune.swipeRotationDivisor
            pose.opacity = 1
        }
        return pose
    }

    /// Paged fullscreen carousel (ref 12), with drag-to-dismiss (ref 13).
    private func fullscreenPose(_ a: Int, _ i: Int, _ n: Int, _ L: GalleryLayout) -> CardPose {
        let cw = L.cardSize.width
        var scale = L.w / cw
        // Pages further than one away wait just off-screen, so they never streak across.
        let d = CGFloat(min(max(i - frontIndex, -2), 2))
        var x = L.w / 2 + d * (cw * scale + Tune.pageGap)
        var y = L.h / 2 + Tune.fullscreenYOffset
        var rotation: CGFloat = 0
        let opacity: CGFloat = abs(i - frontIndex) <= 1 ? 1 : 0

        if i != frontIndex && showDeck {
            // The rest of the deck fades in at its slots, ready to receive the card.
            var deck = stackPose(a, i, n, L)
            deck.opacity = dismissProgress
            return deck
        }
        if dragAxis == .vertical {
            if i == frontIndex {
                x += cardDrag.width * 0.6
                y += cardDrag.height
                scale *= 1 - min(abs(cardDrag.height) / L.h, 0.5) * Tune.dismissShrink
                rotation = cardDrag.width / 30 - cardDrag.height / Tune.dismissTiltDivisor
            }
        } else {
            x += cardDrag.width
        }
        return CardPose(x: x, y: y, orbitRadius: 0, orbitAngle: restAngle(a, i, n),
                        rotation: rotation + turns(a, i, n), scale: scale,
                        opacity: opacity, corner: Tune.fullscreenCorner)
    }

    /// Orbit angle of card `i` on the ring (top = -90°), including the album's spin.
    private func ringAngle(_ a: Int, _ i: Int, _ n: Int) -> CGFloat {
        -90 + 360 * CGFloat(i) / CGFloat(max(n, 1)) + spin[a, default: 0]
    }

    /// Rotation that makes a ring card face outward, kept within ±180° of upright
    /// before the spin so cards turn the short way.
    private func ringRotation(_ a: Int, _ i: Int, _ n: Int) -> CGFloat {
        normalizedDegrees(360 * CGFloat(i) / CGFloat(max(n, 1))) + spin[a, default: 0]
    }

    /// Whole turns the card has made on the ring. Upright poses add these so a card
    /// coming off the spinning ring lands on the nearest turn instead of unwinding.
    private func turns(_ a: Int, _ i: Int, _ n: Int) -> CGFloat {
        360 * (ringRotation(a, i, n) / 360).rounded()
    }

    private func stackRel(_ i: Int, _ n: Int) -> Int {
        ((i - frontIndex) % n + n) % n
    }

    /// Depth of card `i` in album `a`'s own deck.
    private func deckRel(_ a: Int, _ i: Int, _ n: Int) -> Int {
        ((i - fronts[a, default: 0]) % n + n) % n
    }

    // MARK: Layering / interaction

    private func zOrder(_ a: Int, _ i: Int, _ n: Int) -> Double {
        guard liftedAlbum == a, a == activeAlbum else {
            return (menuAlbum == a ? 51 : 1) + Double(n - deckRel(a, i, n)) * 0.001
        }
        switch phase {
        case .closed, .peek: return 1
        case .bundle, .fan: return 10 + Double(n - stackRel(i, n)) * 0.01
        case .radial: return 10 + Double(i) * 0.01
        case .stack:
            return 10 + Double(n - stackRel(i, n)) * 0.01
        case .fullscreen:
            return i == frontIndex ? 20 : 10 + Double(n - stackRel(i, n)) * 0.01
        }
    }

    private func isInteractive(_ a: Int, _ i: Int, _ n: Int) -> Bool {
        guard a == activeAlbum, liftedAlbum == a else { return false }
        switch phase {
        case .stack: return stackRel(i, n) == 0
        case .fullscreen: return i == frontIndex
        default: return false
        }
    }

    private func cardAnimation(_ a: Int, _ i: Int, _ n: Int) -> Animation {
        guard !reduceMotion else { return Tune.reducedSpring }
        let base = Tune.cardSpring
        // Depth in the deck: the top card leaves first and returns last.
        let depth = Double(min(deckRel(a, i, n), Tune.stackSlots.count - 1))
        let lastDepth = Double(Tune.stackSlots.count - 1)
        switch stagger {
        case .none:
            return a == activeAlbum ? base : stripSpring
        case .strip:
            return stripSpring
        case .leave:
            return a == leavingAlbum ? base.delay((lastDepth - depth) * Tune.closeStagger) : stripSpring
        case .open:
            if a == activeAlbum {
                let order = phase == .radial ? Double(i) : depth
                return base.delay(order * Tune.openStagger)
            }
            if a == leavingAlbum { return base.delay((lastDepth - depth) * Tune.closeStagger) }
            return stripSpring
        case .close:
            return a == activeAlbum ? base.delay((lastDepth - depth) * Tune.closeStagger) : stripSpring
        }
    }

    private func spring(_ animation: Animation) -> Animation {
        reduceMotion ? Tune.reducedSpring : animation
    }

    // MARK: Folder strip

    private func folderMetrics(_ a: Int, _ L: GalleryLayout) -> FolderMetrics {
        let x = L.w / 2 + CGFloat(a - activeAlbum) * L.spacing + stripDrag
        let d = min(abs(x - L.w / 2) / L.spacing, 1)
        // The centred folder rests a little smaller while closed and grows on tap.
        let rest = phase == .closed && !stripLowered ? 1 - (1 - Tune.closedFolderScale) * (1 - d) : 1
        let scale = (1 - d * (1 - Tune.neighborScale)) * rest
        guard a == menuAlbum else {
            return FolderMetrics(x: x, base: stripBase(L), scale: scale, emphasis: 1 - d)
        }
        // Held: lifts, grows, and follows the finger 1:1 with a tilt, like the swiped card.
        return FolderMetrics(x: x + holdDrag.width,
                             base: stripBase(L) + holdDrag.height - (menuShown ? Tune.holdLift : 0),
                             scale: scale * (menuShown ? Tune.holdScale : 1), emphasis: 1 - d,
                             rotation: holdDrag.width / Tune.holdTiltDivisor)
    }

    /// The strip sits in the middle of the screen until photos come out.
    private func stripBase(_ L: GalleryLayout) -> CGFloat {
        L.stripBase(lowered: stripLowered)
    }

    private func folderOpacity(_ m: FolderMetrics) -> CGFloat {
        stripOpacity * (Tune.neighborOpacity + (1 - Tune.neighborOpacity) * m.emphasis)
    }

    private var dismissProgress: CGFloat {
        min(abs(cardDrag.height) / Tune.dismissProgressDistance, 1)
    }

    private var stripOpacity: CGFloat {
        guard phase == .fullscreen else { return 1 }
        return dragAxis == .vertical ? dismissProgress : 0
    }

    private func stripTapped(atX x: CGFloat, _ L: GalleryLayout) {
        let nearest = albums.indices.min { a, b in
            abs(folderMetrics(a, L).x - x) < abs(folderMetrics(b, L).x - x)
        }
        guard let target = nearest, abs(folderMetrics(target, L).x - x) < L.spacing / 2 else { return }
        if target == activeAlbum {
            if phase == .closed { open() } else { close() }
        } else {
            select(target)
        }
    }

    /// One gesture for both tap and scroll. Separate tap + drag recognizers race
    /// while a timed sequence re-renders the view, and the tap could win a scroll.
    private func stripGesture(_ L: GalleryLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($stripGestureActive) { _, active, _ in active = true }
            .onChanged { v in
                if !pressStarted {
                    pressStarted = true
                    // Staying still on the centred folder turns the press into a hold.
                    if canHold(at: v.startLocation, L) {
                        holdTask = Task { @MainActor in
                            guard await pause(Tune.holdDelay) else { return }
                            holdTask = nil
                            beginHold()
                        }
                    }
                }
                if holding {
                    holdDrag = v.translation
                    return
                }
                if hypot(v.translation.width, v.translation.height) > Tune.tapSlop {
                    holdTask?.cancel()
                    holdTask = nil
                }
                guard stripDrag != 0 || abs(v.translation.width) > Tune.tapSlop else { return }
                let t = v.translation.width
                let atEdge = (activeAlbum == 0 && t > 0) || (activeAlbum == albums.count - 1 && t < 0)
                stripDrag = atEdge ? rubberBand(t, limit: L.spacing * 0.5) : t
            }
            .onEnded { v in
                if endPress() { return }
                if stripDrag == 0 && abs(v.translation.width) <= Tune.tapSlop && abs(v.translation.height) <= Tune.tapSlop {
                    stripTapped(atX: v.startLocation.x, L)
                    return
                }
                let raw = CGFloat(activeAlbum) - v.predictedEndTranslation.width / L.spacing
                let target = min(max(Int(raw.rounded()), 0), albums.count - 1)
                if target != activeAlbum {
                    select(target)
                } else {
                    withAnimation(spring(Tune.cardSpring)) { stripDrag = 0 }
                }
            }
    }

    // MARK: Thumbnail slider

    private var filmOpacity: CGFloat {
        guard phase == .fullscreen else { return 0 }
        return dragAxis == .vertical ? 1 - dismissProgress : 1
    }

    private func filmTapped(_ i: Int) {
        guard phase == .fullscreen, i != frontIndex else { return }
        Haptics.selection()
        withAnimation(spring(Tune.pageSpring)) {
            frontIndex = i
            filmDrag = 0
        }
    }

    /// Dragging the slider scrubs through the photos: the big photo pages as soon
    /// as another thumbnail reaches the middle, and the release snaps to the
    /// predicted end.
    private func filmGesture(_ n: Int) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { v in
                let start = filmStart ?? frontIndex
                if filmStart == nil { filmStart = start }
                var raw = CGFloat(start) - v.translation.width / Tune.filmSpacing
                let last = CGFloat(n - 1)
                if raw < 0 { raw = rubberBand(raw, limit: 0.6) }
                if raw > last { raw = last + rubberBand(raw - last, limit: 0.6) }
                let nearest = min(max(Int(raw.rounded()), 0), n - 1)
                if nearest != frontIndex {
                    Haptics.selection()
                    // frontIndex and filmDrag change together, so the slider itself doesn't move.
                    withAnimation(spring(Tune.pageSpring)) {
                        frontIndex = nearest
                        filmDrag = raw - CGFloat(nearest)
                    }
                } else {
                    filmDrag = raw - CGFloat(nearest)
                }
            }
            .onEnded { v in
                let start = filmStart ?? frontIndex
                filmStart = nil
                let predicted = CGFloat(start) - v.predictedEndTranslation.width / Tune.filmSpacing
                let target = min(max(Int(predicted.rounded()), 0), n - 1)
                if target != frontIndex { Haptics.selection() }
                withAnimation(spring(Tune.pageSpring)) {
                    frontIndex = target
                    filmDrag = 0
                }
            }
    }

    // MARK: Colour menu

    private func canHold(at p: CGPoint, _ L: GalleryLayout) -> Bool {
        guard menuAlbum == nil, sequence == nil, phase == .closed || phase == .stack else { return false }
        let m = folderMetrics(activeAlbum, L)
        return abs(p.x - m.x) < Tune.frontSize.width * m.scale / 2
            && p.y > m.frontTop - (Tune.backRise + Tune.peekRise) * m.scale
            && p.y < m.base + 8
    }

    private func beginHold() {
        guard pressStarted, !holding, stripDrag == 0, menuAlbum == nil else { return }
        Haptics.impact(.medium)
        holding = true
        menuAlbum = activeAlbum
        withAnimation(Tune.holdSpring) { menuShown = true }
    }

    /// Finger lifted (or the press was cancelled). Returns true if it was a hold,
    /// so the release isn't also treated as a tap or scroll.
    @discardableResult
    private func endPress() -> Bool {
        pressStarted = false
        holdTask?.cancel()
        holdTask = nil
        guard holding else { return false }
        holding = false
        // The menu stays open; the folder springs back under the picker.
        withAnimation(Tune.holdSpring) { holdDrag = .zero }
        return true
    }

    private func dismissMenu() {
        menuTask?.cancel()
        menuTask = nil
        withAnimation(Tune.menuSpring, completionCriteria: .removed) {
            menuShown = false
            holdDrag = .zero
        } completion: {
            // Faded out: put the folder back under the other layers.
            if !menuShown { menuAlbum = nil }
        }
    }

    private func pickColor(_ k: Int) {
        guard let a = menuAlbum else { return }
        Haptics.selection()
        withAnimation(Tune.recolorAnimation) { colorChoice[a] = k }
        menuTask?.cancel()
        menuTask = Task { @MainActor in
            guard await pause(Tune.pickDismissDelay) else { return }
            menuTask = nil
            dismissMenu()
        }
    }

    private func colorPicker(_ L: GalleryLayout) -> some View {
        let a = menuAlbum ?? activeAlbum
        let m = folderMetrics(a, L)
        let count = CGFloat(Tune.palette.count)
        let width = count * Tune.swatchSize + (count - 1) * Tune.swatchSpacing + 16
        let height = Tune.swatchSize + 16
        // Rides above the folder, following it while it's dragged around.
        let x = min(max(m.x, width / 2 + 12), L.w - width / 2 - 12)
        let y = m.frontTop - Tune.backRise * m.scale - Tune.pickerGap - height / 2
        return FolderColorPicker(swatches: Tune.palette,
                                 selected: colorChoice[a] ?? Tune.palette.count - 1,
                                 shown: menuShown, pick: pickColor)
            .position(x: x, y: y)
            .allowsHitTesting(menuShown)
    }

    // MARK: Actions

    /// Cancels any timed sequence and lands an in-flight swipe, so every action
    /// starts from a settled state.
    private func interrupt() {
        sequence?.cancel()
        sequence = nil
        if let task = flingTask {
            task.cancel()
            flingTask = nil
            withAnimation(spring(Tune.tuckSpring)) { fling = nil }
        }
    }

    private func open() {
        let album = activeAlbum
        guard !albums[album].photos.isEmpty else { return }
        interrupt()
        Haptics.impact(.soft)
        opened = true
        openCount += 1
        cardDrag = .zero
        showDeck = false
        // 1st open: fan pop-out. 2nd open: circular reveal. Alternates. Reduce Motion: straight to the stack.
        let useRadial = !reduceMotion && openCount % 2 == 0
        arc = useRadial ? .ring : .fan
        leavingAlbum = nil

        // 1. The folder grows and the photos rise inside the pocket (ref image 1).
        stagger = .strip
        stripSpring = spring(Tune.peekSpring)
        withAnimation(stripSpring) {
            phase = .peek
            phaseKey += 1
        }
        sequence = Task { @MainActor in
            guard await pause(useRadial ? Tune.radialPeekHold : Tune.peekHold) else { return }

            // 2. Pop out into a bundle / ring while the strip drops to the bottom.
            stagger = reduceMotion ? .none : .open
            stripSpring = spring(useRadial ? Tune.radialOutSpring : Tune.openSpring)
            withAnimation(stripSpring) {
                phase = reduceMotion ? .stack : (useRadial ? .radial : .bundle)
                stripLowered = true
                phaseKey += 1
            }
            // Rise from behind the glass first, then jump to the "out" layer.
            guard await pause(Tune.liftDelay) else { return }
            liftedAlbum = album
            guard !reduceMotion else { sequence = nil; return }

            stagger = .strip
            if useRadial {
                guard await pause(Tune.radialHold) else { return }
                withAnimation(Tune.spinAnimation) { spin[album, default: 0] += Tune.radialSpinDegrees }
                // Spiral in while the spin is still settling.
                guard await pause(Tune.spinHold) else { return }
                stripSpring = Tune.spiralInSpring
                withAnimation(stripSpring) {
                    phase = .stack
                    phaseKey += 1
                }
            } else {
                // 3. The bundle spreads into the fan (ref image 2) …
                guard await pause(Tune.bundleHold) else { return }
                stripSpring = Tune.fanOutSpring
                withAnimation(stripSpring) {
                    phase = .fan
                    phaseKey += 1
                }
                // 4. … and collapses into the deck (ref images 3 → 4).
                guard await pause(Tune.fanHold) else { return }
                stripSpring = Tune.fanInSpring
                withAnimation(stripSpring) {
                    phase = .stack
                    phaseKey += 1
                }
            }
            sequence = nil
        }
    }

    private func close() {
        interrupt()
        Haptics.impact(.soft)
        opened = false
        liftedAlbum = nil   // straight back behind the glass
        dragAxis = nil
        showDeck = false
        stagger = reduceMotion ? .none : .close
        leavingAlbum = nil
        stripSpring = spring(Tune.closeSpring)
        withAnimation(stripSpring) {
            phase = .closed
            cardDrag = .zero
            phaseKey += 1
        }
        guard stripLowered else { return }
        // The photos get home first, then the strip rises back to the middle.
        sequence = Task { @MainActor in
            guard await pause(reduceMotion ? 0 : Tune.stripReturnDelay) else { return }
            stagger = .strip
            stripSpring = spring(Tune.stripReturnSpring)
            withAnimation(stripSpring) {
                stripLowered = false
                phaseKey += 1
            }
            sequence = nil
        }
    }

    /// Scroll to another folder. If photos are out, the old ones go home first
    /// and the new folder's photos rise a moment later (ref 14).
    private func select(_ target: Int) {
        interrupt()
        Haptics.selection()
        leavingAlbum = activeAlbum
        liftedAlbum = nil
        dragAxis = nil
        showDeck = false
        stagger = reduceMotion ? .none : .leave
        stripSpring = spring(Tune.cardSpring)
        withAnimation(stripSpring) {
            activeAlbum = target
            stripDrag = 0
            cardDrag = .zero
            phase = .closed
            if !opened { stripLowered = false }
            phaseKey += 1
        }
        guard opened else { return }
        sequence = Task { @MainActor in
            guard await pause(reduceMotion ? 0 : Tune.switchDelay) else { return }
            stagger = reduceMotion ? .none : .open
            withAnimation(spring(Tune.openSpring)) {
                phase = .stack
                phaseKey += 1
            }
            guard await pause(Tune.liftDelay) else { return }
            liftedAlbum = target
            sequence = nil
        }
    }

    private func cardTapped() {
        guard phase == .stack else { return }
        interrupt()
        Haptics.impact(.light)
        stagger = .none
        showDeck = false
        withAnimation(spring(Tune.fullscreenSpring)) {
            phase = .fullscreen
            cardDrag = .zero
            phaseKey += 1
        }
    }

    private func dismissToStack() {
        interrupt()
        Haptics.impact(.light)
        stagger = .none
        withAnimation(spring(Tune.dismissSpring)) {
            phase = .stack
            cardDrag = .zero
            dragAxis = nil
            showDeck = false
            phaseKey += 1
        }
    }

    // MARK: Card gestures

    private func cardDragGesture(_ n: Int, _ L: GalleryLayout) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($cardGestureActive) { _, active, _ in active = true }
            .onChanged { v in
                if dragAxis == nil {
                    dragAxis = abs(v.translation.width) > abs(v.translation.height) ? .horizontal : .vertical
                }
                switch phase {
                case .stack:
                    cardDrag = v.translation
                case .fullscreen:
                    if dragAxis == .horizontal {
                        let t = v.translation.width
                        let atEdge = (frontIndex == 0 && t > 0) || (frontIndex == n - 1 && t < 0)
                        cardDrag = CGSize(width: atEdge ? rubberBand(t, limit: L.w * 0.3) : t, height: 0)
                    } else {
                        showDeck = true
                        cardDrag = v.translation
                    }
                default:
                    break
                }
            }
            .onEnded { v in
                // Each end path clears `dragAxis` inside its own animation, so the
                // poses that depend on it spring instead of jumping.
                let axis = dragAxis
                switch phase {
                case .stack:      endStackDrag(v, n, L)
                case .fullscreen: endFullscreenDrag(v, axis, n, L)
                default:          snapBack()
                }
            }
    }

    private func snapBack() {
        withAnimation(spring(Tune.snapBackSpring), completionCriteria: .removed) {
            cardDrag = .zero
            dragAxis = nil
        } completion: {
            // The deck has faded out by now; put the neighbours back on their pages.
            if dragAxis == nil { showDeck = false }
        }
    }

    /// Swipe: the next card takes the top at once, while the swiped one slides
    /// out a little and then tucks behind the deck (ref 11).
    private func endStackDrag(_ v: DragGesture.Value, _ n: Int, _ L: GalleryLayout) {
        let tx = v.translation.width
        let px = v.predictedEndTranslation.width
        guard abs(tx) > Tune.swipeThreshold || abs(px) > Tune.swipeFlick else {
            snapBack()
            return
        }
        let dir: CGFloat = (abs(px) > abs(tx) ? px : tx) >= 0 ? 1 : -1
        flingTopCard(direction: dir, dy: v.translation.height * 0.4, L)
    }

    private func flingTopCard(direction dir: CGFloat, dy: CGFloat, _ L: GalleryLayout) {
        interrupt()
        Haptics.impact(.light)
        let n = albums[activeAlbum].photos.count
        let frontID = albums[activeAlbum].photos[frontIndex].id
        withAnimation(spring(Tune.flingSpring)) {
            dragAxis = nil
            frontIndex = (frontIndex + 1) % n
            fling = Fling(id: frontID, offset: CGSize(width: dir * L.w * Tune.flingDistanceFraction, height: dy))
            cardDrag = .zero
        }
        flingTask = Task { @MainActor in
            guard await pause(Tune.tuckDelay) else { return }
            flingTask = nil
            withAnimation(spring(Tune.tuckSpring)) { fling = nil }
        }
    }

    private func endFullscreenDrag(_ v: DragGesture.Value, _ axis: Axis?, _ n: Int, _ L: GalleryLayout) {
        if axis == .vertical {
            if abs(v.translation.height) > Tune.dismissThreshold || abs(v.predictedEndTranslation.height) > Tune.dismissFlick {
                dismissToStack()
            } else {
                snapBack()
            }
        } else {
            let threshold = L.w * Tune.pageThresholdFraction
            var target = frontIndex
            if v.predictedEndTranslation.width < -threshold { target += 1 }
            if v.predictedEndTranslation.width > threshold { target -= 1 }
            target = min(max(target, 0), n - 1)
            if target != frontIndex { Haptics.selection() }
            withAnimation(spring(Tune.pageSpring)) {
                frontIndex = target
                cardDrag = .zero
                dragAxis = nil
            }
        }
    }
}

#if DEBUG
import os
private let selfTestLog = Logger(subsystem: "FolderStack", category: "selftest")

extension FolderGalleryView {
    /// Launch with `-SelfTest` to replay every flow and interrupt each timed
    /// sequence at fixed points, so the recording can be checked for glitches.
    fileprivate func runSelfTest(_ L: GalleryLayout) async {
        let steps: [(ms: Int, label: String, run: () -> Void)] = [
            (2000, "open: fan pop-out", { open() }),
            (2300, "close mid-fan", { close() }),
            (3300, "open: radial", { open() }),
            (4200, "switch album mid-spin", { select(1) }),
            (5600, "swipe top card left", { flingTopCard(direction: -1, dy: 0, L) }),
            (5680, "tap mid-fling -> fullscreen", { cardTapped() }),
            (6800, "dismiss to stack", { dismissToStack() }),
            (7800, "swipe right", { flingTopCard(direction: 1, dy: 0, L) }),
            (8800, "close", { close() }),
            (9050, "open mid-close", { open() }),
            (9400, "close mid-peek/ring", { close() }),
        ]
        await run(steps)
    }

    /// Launch with `-Demo` to replay the reference video's flow at its timings
    /// (open, swipes, fullscreen, dismiss, album switch, close, radial open).
    fileprivate func runDemo(_ L: GalleryLayout) async {
        // Give the visible photos up to 10 s to download, so the recording shows real images.
        for _ in 0..<100 where !albums[activeAlbum].photos.allSatisfy(isCached) {
            guard await pause(100) else { return }
        }
        let steps: [(ms: Int, label: String, run: () -> Void)] = [
            (2000, "open: fan", { open() }),
            (4000, "swipe left", { flingTopCard(direction: -1, dy: 0, L) }),
            (5000, "swipe right", { flingTopCard(direction: 1, dy: 0, L) }),
            (6000, "tap -> fullscreen", { cardTapped() }),
            (6900, "page: drag", { pageDrag(-1, L) }),
            (7150, "page: next", { pageSettle(+1) }),
            (8000, "page: drag", { pageDrag(-1, L) }),
            (8250, "page: next", { pageSettle(+1) }),
            (9100, "page: drag", { pageDrag(-1, L) }),
            (9350, "page: next", { pageSettle(+1) }),
            (10200, "page: drag back", { pageDrag(1, L) }),
            (10450, "page: previous", { pageSettle(-1) }),
            (11000, "slider: jump to photo 6", { filmTapped(5) }),
            (12000, "slider: jump back to photo 2", { filmTapped(1) }),
            (13100, "drag down", { dragAxis = .vertical; showDeck = true; cardDrag = CGSize(width: 0, height: 60) }),
            (13400, "drag further", { withAnimation(.linear(duration: 0.4)) { cardDrag = CGSize(width: 10, height: 150) } }),
            (14100, "release", { dismissToStack() }),
            (15500, "switch album", { select(2) }),
            (19100, "close", { close() }),
            (20650, "open: radial", { open() }),
            (23400, "hold the open folder", { pressStarted = true; beginHold() }),
            (24100, "drag it around", { withAnimation(.easeInOut(duration: 0.5)) { holdDrag = CGSize(width: 70, height: -40) } }),
            (24700, "drag the other way", { withAnimation(.easeInOut(duration: 0.6)) { holdDrag = CGSize(width: -60, height: -15) } }),
            (25400, "release", { endPress() }),
            (26200, "pick yellow", { pickColor(2) }),
            (28000, "close", { close() }),
            (29600, "hold the closed folder", { pressStarted = true; beginHold() }),
            (30300, "drag it", { withAnimation(.easeInOut(duration: 0.5)) { holdDrag = CGSize(width: -50, height: 30) } }),
            (30900, "release", { endPress() }),
            (31700, "pick blue", { pickColor(3) }),
            (33100, "switch album", { select(3) }),
            (34400, "open", { open() }),
        ]
        await run(steps)
    }

    /// Demo stand-in for a horizontal finger drag in fullscreen.
    private func pageDrag(_ dir: CGFloat, _ L: GalleryLayout) {
        dragAxis = .horizontal
        withAnimation(.linear(duration: 0.22)) { cardDrag = CGSize(width: dir * L.w * 0.4, height: 0) }
    }

    /// Demo stand-in for releasing that drag past the page threshold.
    private func pageSettle(_ step: Int) {
        Haptics.selection()
        withAnimation(spring(Tune.pageSpring)) {
            frontIndex = min(max(frontIndex + step, 0), albums[activeAlbum].photos.count - 1)
            cardDrag = .zero
            dragAxis = nil
        }
    }

    private func isCached(_ photo: Photo) -> Bool {
        if case .remote(let url) = photo.source { return ImageStore.shared.cached(url) != nil }
        return true
    }

    private func run(_ steps: [(ms: Int, label: String, run: () -> Void)]) async {
        var elapsed = 0
        for step in steps {
            guard await pause(step.ms - elapsed) else { return }
            elapsed = step.ms
            selfTestLog.notice("SELFTEST \(step.ms)ms \(step.label, privacy: .public)")
            step.run()
        }
    }
}
#endif

#Preview {
    FolderGalleryView(albums: Album.samples)
}
