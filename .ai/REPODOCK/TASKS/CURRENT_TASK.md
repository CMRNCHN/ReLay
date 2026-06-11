# CURRENT_TASK.md

## Task Title

Settings rework + new settings + Phase 3 runtime observability

## Request Date

2026-05-28

## Status

PHASE_1_COMPLETE (8/8 steps) - Ready for Phase 2 Integration Verification

## Objective

Rework the Settings UI to be understandable by non-technical users, add new behavior
settings (snap speed, haptics, center snap, configurable swipe actions), and add
per-gesture correlation IDs to all log lines (Phase 3 observability).

## Work Done

### Settings Rework — `Sources/ReLay/SettingsWindow.swift`

Complete rewrite of the settings UI:

- Renamed all four existing settings to plain-English titles with human-readable
  descriptions. Removed raw unit labels ("pt", "pt/s"). Added semantic endpoint labels
  below each slider track (e.g. `Responsive ←→ Deliberate`).
- Added "Feel" preset strip (Careful / Balanced / Snappy) as a segmented control at the
  top of the panel — sets all five sliders at once.
- Added **Snap Speed** slider (0.08–0.45s, `snapDuration` key, Instant ←→ Smooth).
- Added **Snap Haptics** toggle (`snapHapticsEnabled` Bool, on by default).
- Added **Center Snap** toggle (`centerSnapEnabled` Bool, off by default) — routes
  floating-window horizontal swipes to center before halves.
- Added **Swipe Actions** row with two `NSPopUpButton`s for configuring up-swipe and
  down-swipe behavior independently (Fullscreen/Minimize/Center/Nothing).
- Window height expanded to 620px with `NSScrollView` wrapper.

### Core Settings Wiring

- Added `Sources/ReLayCore/ReLaySettings.swift` — centralized UserDefaults accessors.
- `LayoutOrchestrator.swift` — animation duration reads from `snapDuration` UserDefault.
- `GestureEngine.swift` — all 3 haptic sites gated on `ReLaySettings.hapticsEnabled`.
- `SpatialTransitionEngine.swift` — all 2 haptic sites gated; up/down swipe dispatched
  to `executeUpSwipeAction`/`executeDownSwipeAction` which read UserDefaults; added
  `executeTransitionTo(_:window:)` for direct-state snaps; graph re-instantiated on
  `ReLaySettingsChanged` to pick up `centerSnapEnabled`.
- `WindowLayoutState.swift` — `LayoutTransitionGraph.init(centerSnap:)` parameter added;
  when `centerSnap == true`, `floating → center` replaces `floating → leftHalf/rightHalf`.

### Phase 3 — Per-gesture Correlation IDs

Every log line for a single gesture now shares an 8-char prefix of a `UUID`:

- `TitleBarInterceptor.swift` — UUID created at hit-accept (`pendingGestureID`), logged
  on the `title bar hit` line, passed to the delegate via the updated protocol signature
  `gestureDidBegin(on:at:fingerCount:shiftHeld:gestureID:)`.
- `GestureEngine.swift` — stores `currentGestureID` from the protocol callback; passes
  it to `SpatialTransitionEngine.beginSession(window:fingerCount:at:gestureID:)`; logs
  it on begin and commit.
- `SpatialTransitionEngine.swift` — stores `currentGestureID`; logs `gesture=` prefix
  on all key lines: begin, commit, cancel, state transitions, enlarge, minimize, and
  direct-state transitions.

Log format example for one gesture:
```
[interceptor] title bar hit gesture=a3f82c1b ...
[gesture]     gesture began gesture=a3f82c1b ...
[gesture]     gesture committed gesture=a3f82c1b ...
[transition]  transition request gesture=a3f82c1b ...
[transition]  state transition gesture=a3f82c1b floating -> leftHalf
[transition]  layout resolution gesture=a3f82c1b state=leftHalf
```

## Architecture Boundaries Touched

- `Sources/ReLay/SettingsWindow.swift`
- `Sources/ReLayCore/ReLaySettings.swift` (new file)
- `Sources/ReLayCore/LayoutOrchestrator.swift`
- `Sources/ReLayCore/GestureEngine.swift`
- `Sources/ReLayCore/SpatialTransitionEngine.swift`
- `Sources/ReLayCore/TitleBarInterceptor.swift`
- `Sources/ReLayCore/WindowLayoutState.swift`

## Build / Test Status

- `swift build`: passing
- `swift test`: 70 passing, 0 failures

## Risks / Follow-Ups

- Live gesture matrix verification (Finder, Safari, Terminal, Xcode, System Settings)
  still pending — run ReLay and collect logs per GESTURE_INGRESS_MATRIX.md.
- Xcode topBand may still need a bump to 96px if geometric misses appear on large displays.
- Scenario tests reference `testNeutralStatesGoLeftToLeftHalf` and
  `testNeutralStatesGoRightToRightHalf` — these test the default (centerSnap=false) path
  and continue to pass. A matching `centerSnap=true` test suite would be a good addition.

## Next Task Recommendation

1. Run ReLay on device and verify gesture matrix against GESTURE_INGRESS_MATRIX.md.
2. Add scenario tests for `centerSnap=true` graph behavior.
