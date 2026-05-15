# ARCHITECTURE_RULES.md

Structural constraints for ReLay. Each layer owns one domain and must not leak across boundaries.

---

## Layer Map

```text
GestureEngine
    -> (direction, velocity, fingerCount, progress)
SpatialTransitionEngine <- WindowStateStore (state read/write)
    -> (next state)      <- LayoutTransitionGraph (transition lookup)
LayoutResolver          <- WindowStateStore
    -> (target CGRect)
LayoutOrchestrator      <- PreviewManager (overlay tracking)
    -> (AX frame writes)
```

---

## Layer Contracts

### GestureEngine

Owns axis locking, threshold detection, velocity measurement, session lifecycle, and finger count.
Must not know layout states, frames, workspace topology, or state storage.

### WindowLayoutState + LayoutTransitionGraph

Own semantic positions and transition rules.
Every transition must be declared in `buildTable()`.
Must remain pure Swift value types without AppKit, Cocoa, or AX imports.

### WindowStateStore

Owns per-window `WindowRecord` state, history, and floating frame capture.
Must not resolve frames, trigger animations, or perform transition lookup.

### LayoutResolver

Owns `(WindowLayoutState x screen CGRect) -> CGRect`.
Must remain pure: no mutable state, no AX, no side effects.

### SpatialTransitionEngine

Owns runtime sequencing from gesture commit to semantic transition to frame resolution.
Must keep this order:

1. state update
2. frame resolution
3. animation / application

### LayoutOrchestrator

Owns AX frame writes, animation primitives, window enumeration, and screen geometry access.
Must not decide semantic layout state.

### PreviewManager

Owns preview overlay display only.
Must not infer or own transition state.

### TitleBarInterceptor

Owns raw event interception and initial target qualification.
Must not own gesture semantics beyond input capture.

---

## Absolute Prohibitions

- No runtime AI or heuristic routing in production behavior
- No plugin system or hook registry
- No cross-layer state mutation
- No geometry logic in the gesture layer
- No semantic logic in the AX layer
- No extra indirection on the gesture-to-frame path

---

## Abstraction Depth Limit

Maximum call depth for a user gesture to frame write path:

`GestureEngine -> SpatialTransitionEngine -> LayoutResolver -> LayoutOrchestrator`

Do not add middleware or event-bus layers between these.

---

## Planned Future Layer

When `WorkspaceTopology` is introduced it must:

- live under `Sources/ReLayCore/Workspace/`
- own focal, supporting, and peripheral workspace roles
- be consumed by `SpatialTransitionEngine`
- not replace `WindowStateStore`
- not touch `LayoutOrchestrator` or `GestureEngine`
