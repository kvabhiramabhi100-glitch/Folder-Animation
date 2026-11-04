# FolderStack: glass folder photo gallery (SwiftUI, iOS 17+)

A row of glass folders sits in the middle of the screen. Tapping a folder grows it and lifts its photos inside the pocket. They pop out as a compact bundle while the folder strip drops to the bottom, spread into a hand of cards, then collapse into a swipeable stack. Tapping a card opens a fullscreen carousel, and dragging up or down closes it back to the stack. Pressing and holding the centred folder lifts it over a blurred backdrop, lets you drag it around, and shows a colour pill to recolour it.

## Build / run
- `FolderStack.xcodeproj` uses a synchronized folder group: any `.swift` file in `FolderStack/` is compiled automatically.
- Build: `xcodebuild -project FolderStack.xcodeproj -scheme FolderStack -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build`. It should report zero warnings.
- Demo photos come from picsum.photos, so the simulator needs network access. A cold launch takes a few seconds before the photos appear.
- **Self-test (DEBUG only):** launch with `-SelfTest`, e.g. `xcrun simctl launch booted com.example.FolderStack -SelfTest`. It replays every flow and interrupts each timed sequence at fixed times: close mid-fan, switch album mid-spin, tap mid-fling, open mid-close, close mid-peek. Record it with `xcrun simctl io booted recordVideo` to check for glitches. Steps are logged under subsystem `FolderStack`, category `selftest`.
- **Demo (DEBUG only):** launch with `-Demo` to replay the reference screen recording's flow at its timings: open, two swipes, fullscreen, drag-dismiss, album switch, close, then a radial open. It waits up to 10 s for the photos to download first. Record it and compare frames against the reference video.

## Files
- `FolderStackApp.swift`: app entry point.
- `Tuning.swift`: **every tunable**. `Tune` holds sizes, stack slots, fan and peek layout, springs, timings and the glass colours (`FolderStyle.graphite` / `.lavender` / `.sky`). `GalleryLayout` holds screen-derived sizes.
- `Models.swift`: `Album` and `Photo` (`.remote(URL)` or `.asset(name)`; `Album.assetSamples` shows the asset-catalog naming). Also `ImageStore` (download, downsample and decode off the main thread, kept in an NSCache, prefetching the active album first), `PhotoCardView` and `Haptics` (cached generators).
- `GlassFolder.swift`: `FolderStyle`, `FolderFrontShape` (top edge high on the left, a short step down at 55% of the width, sides tapering 6% toward the bottom), `FolderBackView`, and `GlassFolderFront` (a translucent tint gradient, top sheen and faint rim; the frost comes from the gallery's frost layer, see below).
- `FilmStrip.swift`: the curved thumbnail slider under the fullscreen photo. Thumbnails sit on a cylinder (`FilmPose` is `Animatable` on the slider position, so jumps roll round the curve).
- `FolderColorPicker.swift`: the swatch pill shown while a folder is held. It blurs in, with the swatches popping in one after another.
- `CardPose.swift`: the animation engine. `CardPose` is a `VectorArithmetic` struct (x, y, orbitRadius, orbitAngle, rotation, scale, opacity, corner). `PoseModifier` is `Animatable`, so every field interpolates together and cards travel along arcs. `castsShadow` turns the shadow off for cards buried in the deck.
- `FolderGalleryView.swift`: state, pose functions, gestures, timed sequences, and the DEBUG self-test.

## Architecture
Everything is drawn in one `ZStack` in one coordinate space. There is no ScrollView. The strip is a custom drag-driven layout, so photos always fly to and from a folder's live position.

| z | layer |
|---|---|
| 0 | folder shadows (one blurred folder shape each; per-layer shadows would show through the glass), then back plates: a narrow slab showing above the glass, plus a full-width body hidden behind it |
| 1 | photos inside a folder |
| 1.4 | pocket: an opaque folder-front shape in the back colour. It hides the sharp photos under the glass and keeps an empty folder evenly dark. |
| 1.5 | frost: a blurred copy of the folder's photos (same poses and springs as the real cards), masked to the glass. This is what makes the glass look frosted, so a card passing behind it is seen blurred. It is hidden while the photos are out in the stack or fullscreen. |
| 2 | glass fronts (translucent tint) and labels |
| 3 | fade veils: a blurred background-coloured rect per folder that fades neighbours and the strip in fullscreen. Layers are never faded individually, so translucent glass never shows the layers behind it. |
| 5 | strip touch area: one `DragGesture(minimumDistance: 0)` that decides tap vs scroll at the end |
| 10+ | photos that are out (`liftedAlbum == album`) |
| 30 | thumbnail slider (fullscreen only) |
| 50 | hold backdrop: full-screen `.ultraThinMaterial` that blurs everything under it; tapping it closes the menu |
| 50.5–53 | the held folder's layers (`menuAlbum`), lifted above the backdrop |
| 60 | colour pill |

`liftedAlbum` flips on `Tune.liftDelay` (120 ms) after the photos start popping out, so they rise from behind the glass. On close it flips off immediately.

The strip's vertical position is its own state, `stripLowered`, so it can lag the photos: it drops when they pop out and rises `stripReturnDelay` after a close, once they are home. `opened` records that the user wants photos out; it survives album switches. Folders are bottom-aligned. Neighbours are 57% scale, and the centred folder rests at 94% while closed and grows to 100% on tap.

Each album keeps its own top card in `fronts`. `frontIndex` is the active album's entry. Peeks and z order follow deck depth (`deckRel`), so a deck keeps its order going into and out of its folder.

### Phases (`GalleryPhase`)
| phase | pose | reference |
|---|---|---|
| `.closed` | `closedPose(lifted: false)`: 3 cards peek out; the rest sit hidden in the pocket below the step | image 1 (neighbours) |
| `.peek` | `closedPose(lifted: true)`: peeks grow and rise just after the tap | image 1 |
| `.bundle` | `fanPose(bundled: true)`: the fan's arc squeezed into a compact, slightly tilted bundle | video 2.6 s |
| `.fan` | `fanPose`: hand of cards on a circle around a pivot below; top card upright in the middle, the rest alternate right/left | image 2 |
| `.radial` | `radialPose`: tight pinwheel ring facing outward; `spin[album]` rotates it | ref 10 |
| `.stack` | `stackPose`: 4 visible depths (`Tune.stackSlots`); top card follows the drag; deeper cards wait opaque, shadowless, under slot 3 | images 3, 4 |
| `.fullscreen` | `fullscreenPose`: full-width paged carousel. A vertical drag tilts the photo left and shrinks it, while `showDeck` fades the rest of the deck in at its slots | refs 12, 13 |

Inactive albums always use `.closed`.

### Arcs and rotation
- `arc` (`.fan` / `.ring`) records which arc the last open used. Upright poses keep that arc's orbit angle (radius 0, so it's invisible), so cards leave and rejoin along it.
- `spin[album]` only ever grows. Every pose adds `turns()`, the whole turns made on the ring, so an interrupted spin never unwinds and nothing needs resetting.

### Flows
- **Open (odd taps):** `.peek` → (`peekHold`) `.bundle` with a 35 ms stagger while the strip drops → (`bundleHold`) `.fan` → (`fanHold`) `.stack`.
- **Open (even taps):** `.peek` → (`radialPeekHold`) `.radial` → spin +150° → `.stack` (spirals in while the spin is still settling).
- **Reduce Motion:** `.peek` → `.stack` only, with `Tune.reducedSpring` everywhere.
- **Swipe the stack:** `flingTopCard` makes the next card the top at once. The swiped card slides out a short way (`flingDistanceFraction`) under the deck, then after `tuckDelay` tucks back into the last slot. Left and right both send it to the back.
- **Close:** the deck shrinks into the folder in reverse stagger, then the strip rises back to the middle.
- **Thumbnail slider (fullscreen):** sits under the photo and always centres on `frontIndex`. Dragging it scrubs: the big photo pages as each thumbnail reaches the middle (`filmDrag` holds the fractional part), and the release snaps to the predicted end. Tapping a thumbnail jumps to it. It blurs in with fullscreen and fades out as the photo is dragged down.
- **Press and hold the centred folder** (`Tune.holdDelay`, closed or stack only): handled inside the strip gesture, so a hold never becomes a tap or a scroll. The folder lifts and grows (`holdLift`, `holdScale`), the backdrop blurs in, and the colour pill blurs in above it. While the finger is down the folder follows it 1:1 and tilts (`holdTiltDivisor`), like the swiped card. All of a folder's layers, including its peeking photos, read the lift, drag and tilt from `folderMetrics`, so they move as one. The pill rides above the folder and moves with it (clamped to the screen edges). On release both spring back. Picking a swatch recolours the folder (`colorChoice`, crossfaded) and closes the menu after `pickDismissDelay`. `menuAlbum` stays set until the backdrop has faded out, so the folder isn't blurred while it fades.
- **Tap a card:** fullscreen. A horizontal drag pages, with rubber-banding at the ends. A vertical drag past 110 pt (or a flick) goes back to the stack.
- **Strip:** drag or tap a side folder to switch albums. The old deck shrinks home first, and the new one rises into the stack `switchDelay` later. Snapping uses the predicted end. Tapping the active folder opens or closes it.

### Interruptions
- Every action starts with `interrupt()`, which cancels the `sequence` task and lands a pending fling inside an animation.
- All timed steps use `pause()`, which returns false when cancelled.
- `@GestureState` flags spring cards and the strip back if the system cancels a drag without calling `onEnded`.
- Cards in folders that aren't moving use `stripSpring` (the spring currently moving the strip) with no delay, so peeks stay glued to their folders.

## Tuning knobs (all in `Tuning.swift`)
- Card size/aspect, stack centre and corners: `cardWidthFraction`, `cardAspect`, `stackCenterY`, `stackCorner`
- Deck fan: `stackSlots`
- Pop-out fan: `fanCenterY`, `fanRadius`, `fanStep`, `fanScale`; bundle: `bundleScale`, `bundleStep`, `bundleTilt`
- Folder shape/size: `frontSize`, `backWidth`, `backRise`, plus `FolderFrontShape` for the step curve
- Strip: `stripClosedY`, `stripOpenInset`, `folderSpacingFraction`, `neighborScale`, `closedFolderScale`, `neighborOpacity`
- Peeks: `peeks`, `peekWidth`/`peekRise` (at rest), `liftedPeekWidth`/`liftedPeekRise` (after the tap), `pocketWidth`
- Swipe and dismiss: `swipeRotationDivisor`, `flingDistanceFraction`, `dismissShrink`, `dismissTiltDivisor`
- Springs: `Tune.*Spring`; timings: `peekHold`, `radialPeekHold`, `liftDelay`, `bundleHold`, `fanHold`, `radialHold`, `spinHold`, `tuckDelay`, `switchDelay`, `stripReturnDelay`
- Glass colours: the `FolderStyle` presets at the bottom of `Tuning.swift`; `FolderStyle.tinted(_:)` builds a style from one colour; `glassBlur` is the frost strength
- Thumbnail slider: `filmThumb`, `filmStep`, `filmRadius`, `filmViewDistance`, `filmPerspective`, `filmVisibleDegrees`, `filmSpacing`, `filmBottomInset`; `fullscreenYOffset` lifts the photo to make room
- Colour menu: `palette`, `swatchSize`, `swatchSpacing`, `pickerGap`, `holdDelay`, `holdScale`, `holdLift`, `holdTiltDivisor`, `holdSpring`, `menuSpring`, `recolorAnimation`, `pickDismissDelay`

## Ideas / next steps
- The reference's neighbour folders look more frosted (their photos are heavily blurred). Ours are plain smaller copies behind a light veil.
- iOS 26: try `.glassEffect(.clear, in: FolderFrontShape())` in place of the material.
- Page indicator and in-card parallax in fullscreen.
