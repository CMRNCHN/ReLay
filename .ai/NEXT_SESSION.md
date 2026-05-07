# Next Session

**Prepared:** 2026-05-07

---

## Priority 1 — Test Infrastructure

**Why:** Zero test coverage means refactors are unconstrained. Tests are the safety net for architecture preservation.

Create `Tests/SwishCoreTests/` with:

### LayoutTransitionGraphTests
- Verify every declared transition resolves correctly
- Verify edge states return `nil` (snap-back behavior)
- Verify cross-column sixths work bidirectionally
- Verify no duplicate keys in the table

### LayoutResolverTests
- For each `WindowLayoutState`, verify frame math on a known 2560×1440 screen
- Verify `inferState` round-trips (frame → infer → verify it matches original state)
- Verify `approximatelyEquals` tolerance behavior
- Verify `interpolate` at 0, 0.5, 1.0

### WindowStateStoreTests
- Verify history cap at 12 entries
- Verify `rewind()` returns correct state and removes from history
- Verify `floatingFrame` is preserved across transitions
- Verify `transition()` then `rewind()` round-trip

---

## Priority 2 — Establish Build System

**Why:** Without a build system, file migration and test running are not possible.

Determine current build system:
- Check if there's an Xcode project outside `/Applications/Swish.app/`
- If none: create `Package.swift` defining Swish + SwishCore targets

A minimal Package.swift would be:
```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Relay",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SwishCore", path: "Sources/SwishCore"),
        .target(name: "Swish", dependencies: ["SwishCore"], path: "Sources/Swish"),
        .testTarget(name: "SwishCoreTests", dependencies: ["SwishCore"], path: "Tests/SwishCoreTests")
    ]
)
```

---

## Priority 3 — Migrate Source Files to Domain Directories

**Prerequisite:** Build system established (Priority 2)

Move each file to its domain:

| File | Target |
|------|--------|
| GestureEngine.swift | Sources/SwishCore/Gesture/ |
| WindowLayoutState.swift | Sources/SwishCore/LayoutStates/ |
| WindowStateStore.swift | Sources/SwishCore/Workspace/ |
| LayoutResolver.swift | Sources/SwishCore/Relayout/ |
| SpatialTransitionEngine.swift | Sources/SwishCore/Transitions/ |
| LayoutOrchestrator.swift | Sources/SwishCore/Animation/ |
| PreviewManager.swift | Sources/SwishCore/Preview/ |
| TitleBarInterceptor.swift | Sources/Swish/ |

Run tests after migration. Verify behavior unchanged.

---

## Priority 4 — WorkspaceTopology Design

**When to start:** After tests pass on migrated structure

Design the `WorkspaceTopology` struct:

```swift
struct WorkspaceTopology {
    var focalWindow: WindowID
    var supportingWindows: [WindowID]
    var peripheralWindows: [WindowID]
    var layoutStyle: WorkspaceStyle
}

enum WorkspaceStyle {
    case singleFocus
    case splitFocus
    case threeColumn
    case grid
}
```

Open questions to answer before implementation:
- Where is topology created? (SpatialTransitionEngine on first 3/4-finger gesture?)
- How does topology interact with WindowStateStore? (separate store? same store?)
- Does topology persist across gestures? (yes — it's workspace state, not session state)
- How does tileWindows integrate with topology? (it should populate tiledEntries from topology)

---

## Do NOT Do This Session

- Do not redesign gesture detection (it's working)
- Do not replace LayoutTransitionGraph with inference or ML
- Do not add external frameworks
- Do not add Combine or reactive architecture
- Do not refactor SpatialTransitionEngine until tests exist
