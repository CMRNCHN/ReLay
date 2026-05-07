# Project State

**As of:** 2026-05-07

---

## Identity

| | |
|---|---|
| Product name | Re-Lay |
| Codebase | Swish (transition in progress) |
| Stage | Architecture governance established; foundational primitives complete |
| Build system | Unknown — no Package.swift or .xcodeproj found |

---

## What Is Built and Working

### Gesture Layer — `GestureEngine.swift`
- Two-finger swipe with axis locking (20px lock threshold, 1.5× dominance ratio)
- Cancel on diagonal ambiguity (25px cancel threshold)
- Velocity flick commit at 800pt/s
- Delegates all semantic decisions to `SpatialTransitionEngine`

### Semantic Layout State Layer — `WindowLayoutState.swift`
- 11-state `WindowLayoutState` enum: floating, fullscreen, center, leftHalf/rightHalf, leftThird/rightThird, leftTopSixth/leftBottomSixth/rightTopSixth/rightBottomSixth
- Declarative `LayoutTransitionGraph` — (state × direction) → state lookup table
- `GestureDirection` with natural scroll convention (positive Y = swipe up)

### State Persistence — `WindowStateStore.swift`
- `WindowRecord` per window: currentState, 12-step history, floatingFrame
- Rewind (undo) support
- FloatingFrame captured before first managed placement

### Geometry Resolution — `LayoutResolver.swift`
- Pure state → frame mapping for all 11 states
- Frame → state inference for first-touch window bootstrapping (20px tolerance)
- Preview interpolation helper (linear, 0→1 progress)

### Transition Orchestration — `SpatialTransitionEngine.swift`
- Single session lifecycle (one gesture at a time)
- 2-finger path: state machine through graph
- 3-finger path: auto-layout (fullscreen) or three-column tiling
- 4-finger path: stage manager layout or exit-layout restore
- Floating frame preservation on first transition

### AX Primitive + Animation Layer — `LayoutOrchestrator.swift`
- Critically-damped spring animation (220ms default, 120ms cancel)
- AX frame writes (size → position → size to avoid macOS clamping)
- Window enumeration (all visible, excluding minimized/fullscreen)
- Stage Manager toggle via CFPreferences
- Screen geometry with display coordinate conversion

### Preview Overlay — `PreviewManager.swift`
- NSVisualEffectView overlay, `.popUpMenu` level
- 1:1 gesture-tracking interpolation with 50ms smoothing
- Alpha eases to 25% at full progress, commits at 220ms spring, dismisses at 120ms

---

## What Is NOT Yet Built

| | Status |
|---|---|
| WorkspaceTopology layer | Not designed |
| Test infrastructure | None |
| Domain migration (Sources/SwishCore/) | Directories created, code not moved |
| Build system (Package.swift/.xcodeproj) | Not found |
| Multi-window semantic state participation | Not implemented |
| Diagnostics logging | Not implemented |
| Multi-display topology tracking | Not implemented |

---

## File → Domain Map

| File | Domain |
|------|--------|
| GestureEngine.swift | Gesture |
| WindowLayoutState.swift | LayoutStates |
| WindowStateStore.swift | Workspace |
| LayoutResolver.swift | Relayout |
| SpatialTransitionEngine.swift | Transitions |
| LayoutOrchestrator.swift | Animation |
| PreviewManager.swift | Preview |
| TitleBarInterceptor.swift | WindowAccess (App layer) |

---

## Directory Structure

```
/Applications/Swish.app/
├── [Swift source files — root level, pending migration]
├── .ai/                    ← AI governance (this session)
├── .gitignore
├── storage/                ← Runtime artifacts (gitignored)
├── Sources/                ← Target structure (boundaries only, code not moved)
│   ├── Swish/
│   └── SwishCore/
│       ├── Gesture/
│       ├── LayoutStates/
│       ├── Transitions/
│       ├── Workspace/
│       ├── Relayout/
│       ├── Preview/
│       ├── Animation/
│       ├── WindowAccess/
│       ├── Diagnostics/
│       ├── Configuration/
│       └── Shared/
└── Contents/               ← Built app bundle
```
