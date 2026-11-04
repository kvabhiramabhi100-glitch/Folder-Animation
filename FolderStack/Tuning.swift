import SwiftUI

/// Every tunable in one place: sizes, slot offsets, springs, timings, glass colours.
enum Tune {
    // MARK: Colours
    static let background = Color(red: 0xF6 / 255, green: 0xF6 / 255, blue: 0xF6 / 255)

    // MARK: Cards (ref image 4)
    static let cardWidthFraction: CGFloat = 0.70     // of screen width
    static let cardMaxWidth: CGFloat = 300
    static let cardAspect: CGFloat = 1.4             // height / width (5:7)
    static let stackCenterY: CGFloat = 0.36          // of screen height
    static let stackCorner: CGFloat = 18
    static let fullscreenCorner: CGFloat = 3
    static let radialCorner: CGFloat = 12
    static let peekCorner: CGFloat = 5

    /// Stack depth slots: offset, tilt and scale for depth 0...3. The cards behind
    /// peek out to the upper right with growing clockwise tilt.
    struct Slot { let dx, dy, rotation, scale: CGFloat }
    static let stackSlots: [Slot] = [
        Slot(dx: 0, dy: 0, rotation: -2.5, scale: 1),
        Slot(dx: 12, dy: -8, rotation: 1.5, scale: 0.99),
        Slot(dx: 22, dy: -13, rotation: 4.5, scale: 0.98),
        Slot(dx: 30, dy: -16, rotation: 7, scale: 0.97),
    ]

    // MARK: Fan (ref image 2): cards pop out of the folder like a hand of cards
    static let fanCenterY: CGFloat = 0.42            // centre card, of screen height
    static let fanRadius: CGFloat = 380              // pivot sits this far below the centre card
    static let fanStep: CGFloat = 7                  // degrees between neighbouring cards
    static let fanScale: CGFloat = 0.47
    /// Compact bundle the photos pop into first, before spreading into the fan.
    static let bundleScale: CGFloat = 0.45
    static let bundleStep: CGFloat = 1               // degrees between bundled cards
    static let bundleTilt: CGFloat = 2.5             // extra tilt per bundled card

    // MARK: Folders / strip (refs 1, 4)
    static let frontSize = CGSize(width: 136, height: 78)  // glass pocket at scale 1
    static let backWidth: CGFloat = 0.83             // back plate width, of the front
    static let backRise: CGFloat = 15                // back plate shows this much above the front
    static let stripClosedY: CGFloat = 0.47          // folder centre when everything is closed
    static let stripOpenInset: CGFloat = 175         // front bottom, from the screen bottom, when open
    static let folderSpacingFraction: CGFloat = 0.333 // of screen width
    static let neighborScale: CGFloat = 0.57
    static let closedFolderScale: CGFloat = 0.94     // active folder while closed; grows to 1 on tap
    static let neighborOpacity: CGFloat = 0.85       // neighbours get a light background-colour veil
    static let veilBlur: CGFloat = 6
    static let labelGap: CGFloat = 21                // front bottom → label centre
    static let labelSize: CGFloat = 14

    /// The 3 cards peeking out of a folder: offset (pt) and tilt (deg).
    struct Peek { let dx, dy, rotation: CGFloat }
    static let peeks: [Peek] = [
        Peek(dx: -18, dy: 0, rotation: -4),
        Peek(dx: 4, dy: -4, rotation: 1),
        Peek(dx: 38, dy: 6, rotation: 8),
    ]
    static let peekWidth: CGFloat = 64               // resting in the folder
    static let peekRise: CGFloat = 25                // card top above the front's top edge
    static let pocketWidth: CGFloat = 40             // photos that don't peek, hidden in the pocket
    static let liftedPeekWidth: CGFloat = 64         // just after the tap (ref image 1)
    static let liftedPeekRise: CGFloat = 41

    // MARK: Radial reveal (ref 10)
    static let radialRadiusFraction: CGFloat = 0.25  // of screen width
    static let radialScale: CGFloat = 0.40
    static let radialSpinDegrees: CGFloat = 150

    // MARK: Gestures
    static let tapSlop: CGFloat = 8                  // strip: movement below this is a tap
    static let swipeThreshold: CGFloat = 90
    static let swipeFlick: CGFloat = 260             // predicted end translation
    static let swipeRotationDivisor: CGFloat = 40    // deg = dx / divisor
    static let flingDistanceFraction: CGFloat = 0.32 // of screen width
    static let dismissThreshold: CGFloat = 110
    static let dismissFlick: CGFloat = 320
    static let dismissProgressDistance: CGFloat = 220
    static let dismissShrink: CGFloat = 0.45         // scale loss per screen-height dragged
    static let dismissTiltDivisor: CGFloat = 11      // deg = -dy / divisor (dragging down tilts left)
    static let pageThresholdFraction: CGFloat = 0.25
    static let pageGap: CGFloat = 18

    // MARK: Springs
    static let cardSpring = Animation.spring(response: 0.55, dampingFraction: 0.8)
    static let openSpring = Animation.spring(response: 0.55, dampingFraction: 0.78)
    static let peekSpring = Animation.spring(response: 0.3, dampingFraction: 0.75)
    static let fanOutSpring = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let fanInSpring = Animation.spring(response: 0.55, dampingFraction: 0.8)
    static let closeSpring = Animation.spring(response: 0.5, dampingFraction: 0.85)
    static let radialOutSpring = Animation.spring(response: 0.6, dampingFraction: 0.78)
    static let spinAnimation = Animation.spring(response: 0.85, dampingFraction: 0.9)
    static let spiralInSpring = Animation.spring(response: 0.6, dampingFraction: 0.8)
    static let fullscreenSpring = Animation.spring(response: 0.5, dampingFraction: 0.86)
    static let dismissSpring = Animation.spring(response: 0.5, dampingFraction: 0.82)
    static let stripReturnSpring = Animation.spring(response: 0.5, dampingFraction: 0.86)
    static let snapBackSpring = Animation.spring(response: 0.38, dampingFraction: 0.75)
    static let flingSpring = Animation.spring(response: 0.28, dampingFraction: 1)
    static let tuckSpring = Animation.spring(response: 0.45, dampingFraction: 0.8)
    static let pageSpring = Animation.spring(response: 0.42, dampingFraction: 0.88)
    /// Used for everything when Reduce Motion is on.
    static let reducedSpring = Animation.spring(response: 0.3, dampingFraction: 1)

    // MARK: Fullscreen thumbnail slider
    static let fullscreenYOffset: CGFloat = -36      // photo centre, from the screen centre
    static let filmBottomInset: CGFloat = 102        // slider centre, from the screen bottom
    static let filmThumb = CGSize(width: 76, height: 96)
    static let filmCorner: CGFloat = 12
    static let filmStep: CGFloat = 24                // degrees round the cylinder between thumbnails
    static let filmRadius: CGFloat = 215             // cylinder radius
    static let filmViewDistance: CGFloat = 520       // eye distance for the depth scale
    static let filmPerspective: CGFloat = 0.55
    static let filmVisibleDegrees: CGFloat = 100     // thumbnails fade out past this angle
    static let filmSpacing: CGFloat = 87             // drag distance per thumbnail

    // MARK: Colour picker (press and hold a folder)
    struct Swatch { let color: Color; let style: FolderStyle }
    static let palette: [Swatch] = [
        Color(red: 0.95, green: 0.42, blue: 0.36), Color(red: 0.96, green: 0.65, blue: 0.23),
        Color(red: 0.96, green: 0.81, blue: 0.29), Color(red: 0.36, green: 0.75, blue: 0.92),
        Color(red: 0.40, green: 0.82, blue: 0.48), Color(red: 0.69, green: 0.36, blue: 0.88),
    ].map { Swatch(color: $0, style: .tinted($0)) } + [Swatch(color: Color(white: 0.23), style: .graphite)]
    static let swatchSize: CGFloat = 34
    static let swatchSpacing: CGFloat = 10
    static let pickerGap: CGFloat = 30           // picker bottom → top of the lifted back plate
    static let holdDelay = 400                   // ms of stillness before a press becomes a hold
    static let holdScale: CGFloat = 1.12         // folder grows while held
    static let holdLift: CGFloat = 14            // and rises this much
    static let holdTiltDivisor: CGFloat = 30     // deg = dx / divisor while dragging it around
    static let holdSpring = Animation.spring(response: 0.38, dampingFraction: 0.72)
    static let menuSpring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let recolorAnimation = Animation.easeInOut(duration: 0.35)
    static let pickDismissDelay = 450            // ms the new colour shows before the menu closes
    static let glassBlur: CGFloat = 9            // frost: blur of the photos seen through the glass

    // MARK: Timings (ms)
    static let peekHold = 420        // photos rise inside the pocket, then pop out
    static let radialPeekHold = 100  // same, before the ring reveal
    static let liftDelay = 120       // photos stay behind the glass this long
    static let bundleHold = 200      // bundle on screen, before spreading into the fan
    static let fanHold = 350         // fan on screen, before collapsing into the stack
    static let openStagger = 0.035   // s per card
    static let closeStagger = 0.025  // s per card
    static let radialHold = 100      // after lift, before the ring spins
    static let spinHold = 500        // after the spin starts, before spiralling in
    static let tuckDelay = 150       // fling → tuck behind the deck
    static let switchDelay = 150     // old album heads home first, then the new one rises
    static let stripReturnDelay = 450 // close: photos get home, then the strip rises
}

/// Screen-derived sizes.
struct GalleryLayout {
    let size: CGSize
    var w: CGFloat { size.width }
    var h: CGFloat { size.height }

    var cardSize: CGSize {
        let cw = min(w * Tune.cardWidthFraction, Tune.cardMaxWidth)
        return CGSize(width: cw, height: cw * Tune.cardAspect)
    }
    var stackCenter: CGPoint { CGPoint(x: w / 2, y: h * Tune.stackCenterY) }
    var spacing: CGFloat { w * Tune.folderSpacingFraction }
    /// Front-bottom line of the folder strip: centred while closed, at the bottom when open.
    func stripBase(lowered: Bool) -> CGFloat {
        lowered ? h - Tune.stripOpenInset : h * Tune.stripClosedY + Tune.frontSize.height / 2
    }
    var radialRadius: CGFloat { w * Tune.radialRadiusFraction }
}

// MARK: - Glass colours

extension FolderStyle {
    /// Dark graphite glass – reference 3. The default.
    static let graphite = FolderStyle(
        backTop: Color(white: 0.18), backBottom: Color(white: 0.18),
        glassTop: Color(white: 0.75).opacity(0.30), glassBottom: Color(white: 0.10).opacity(0.60),
        placeholder: Color(white: 0.55))

    /// A folder in one colour: darker back plate, lighter translucent glass.
    static func tinted(_ color: Color) -> FolderStyle {
        let c = UIColor(color)
        return FolderStyle(
            backTop: Color(c.adjusted(brightness: 0.86)), backBottom: Color(c.adjusted(brightness: 0.74)),
            glassTop: Color(c.adjusted(saturation: 0.8, brightness: 1.08)).opacity(0.72),
            glassBottom: Color(c.adjusted(brightness: 0.95)).opacity(0.84),
            placeholder: color)
    }

    /// Lavender glass – reference 2.
    static let lavender = FolderStyle(
        backTop: Color(red: 0.33, green: 0.30, blue: 0.38), backBottom: Color(red: 0.12, green: 0.11, blue: 0.15),
        glassTop: Color(red: 0.80, green: 0.74, blue: 0.95).opacity(0.30),
        glassBottom: Color(red: 0.30, green: 0.26, blue: 0.42).opacity(0.60),
        placeholder: Color(red: 0.62, green: 0.58, blue: 0.80))

    /// Sky-blue glass – reference 5.
    static let sky = FolderStyle(
        backTop: Color(red: 0.50, green: 0.74, blue: 0.94), backBottom: Color(red: 0.30, green: 0.56, blue: 0.86),
        glassTop: Color(red: 0.80, green: 0.91, blue: 1.0).opacity(0.35),
        glassBottom: Color(red: 0.42, green: 0.68, blue: 0.93).opacity(0.55),
        placeholder: Color(red: 0.55, green: 0.75, blue: 0.95))
}

private extension UIColor {
    func adjusted(saturation ds: CGFloat = 1, brightness db: CGFloat = 1) -> UIColor {
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: min(sat * ds, 1), brightness: min(b * db, 1), alpha: a)
    }
}
