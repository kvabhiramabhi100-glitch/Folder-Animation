# FolderStack

A glass-folder photo gallery for iOS 17+, built in SwiftUI. A row of frosted folders sits in the middle of the screen. Tap one and its photos pop out as a fan, then collapse into a swipeable stack.

## Features
- **Open / close:** photos lift in the pocket, pop out as a bundle, fan out and collapse into a stack while the folder strip drops to the bottom. Every second open uses a radial spin instead.
- **Stack:** swipe left or right to send the top card to the back.
- **Fullscreen:** tap a card to view it fullscreen. Swipe to page between photos, or use the curved thumbnail slider underneath (drag to scrub, tap to jump). Drag the photo down to put it back on the stack.
- **Album strip:** drag or tap a side folder to switch albums. The old deck goes home and the new one rises.
- **Recolour:** press and hold the centred folder. The background blurs, the folder lifts and can be dragged around, and a colour pill appears.
- Interruptible animations, haptics, Reduce Motion support and image caching.

## Setup
1. Open `FolderStack.xcodeproj` in Xcode. Every `.swift` file in `FolderStack/` is picked up automatically.
2. Run it on an iOS 17+ simulator or device. The demo photos load from picsum.photos, so it needs internet.
3. To use your own photos, add images to `Assets.xcassets` and pass `Album.assetSamples` (or your own albums) in `FolderStackApp.swift`.

All sizes, springs, timings and colours are in `FolderStack/Tuning.swift`. `CLAUDE.md` explains how the code is organised.

In Debug builds, launch with `-Demo` to replay the whole flow automatically, or with `-SelfTest` to replay interrupted animations.
