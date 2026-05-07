# Architecture Rules

Structural constraints for Re-Lay. These define what each layer owns and what it must never touch.
Violations require explicit human approval in a discrete session.

---

## Layer Map

```
GestureEngine
    ↓ (direction, velocity, fingerCount, progress)
SpatialTransitionEngine        ← WindowStateStore (state read/write)
    ↓ (next state)                 LayoutTransitionGraph (transition lookup)
LayoutResolver                     WindowStateStore
    ↓ (target CGRect)
LayoutOrchestrator             ← PreviewManager (overlay tracking)
    ↓ (AX frame writes)
```

---

## Layer Contracts

### GestureEngine
**Owns:** Axis locking, threshold detection, velocity measurement, session lifecycle, finger count
**Emits:** Gesture events via delegate (begin, change, commit, cancel)
**Must NOT:** Know about layout states, frames, workspace topology, or the state store
**Must NOT:** Call LayoutResolver, WindowStateStore, or SpatialTransitionEngine directly

### WindowLayoutState + LayoutTransitionGraph
**Owns:** The complete set of named semantic positions, transition rules
**Invariant:** Every transition is declared in `buildTable()` — no implicit transitions anywhere else
**Must NOT:** Import Cocoa, AppKit, or Accessibility — pure Swift value types only

### WindowStateStore
**Owns:** Per-window `WindowRecord` (currentState, history, floatingFrame)
**Invariant:** History is bounded (12 entries max); floatingFrame captured before first managed placement
**Must NOT:** Resolve frames, trigger animations, or know about the transition graph

### LayoutResolver
**Owns:** The mapping (WindowLayoutState × screen CGRect) → CGRect
**Invariant:** Pure function — no mutable state, no AX, no side effects, no imports of Cocoa/AppKit
**Must NOT:** Update the state store, trigger animations, or make decisions about which state to use

### SpatialTransitionEngine
**Owns:** The session lifecycle — one session at a time; routes gesture commit to state machine or multi-window op
**Invariant:** State update → frame resolution → animation must happen in that order
**Must NOT:** Embed gesture physics or AX primitives; must delegate both upward and downward

### LayoutOrchestrator
**Owns:** AX frame writes, spring animation, window enumeration, screen geometry, stage manager toggle
**Invariant:** No layout semantics — it receives frames, it does not decide them
**Must NOT:** Know about WindowLayoutState, LayoutTransitionGraph, or WindowStateStore

### PreviewManager
**Owns:** The preview overlay NSWindow — position, alpha, visibility
**Invariant:** Display only — receives frames, never produces them
**Must NOT:** Own any state about what transition is occurring

### TitleBarInterceptor
**Owns:** NSEvent interception, gesture input parsing, delegate dispatch
**Must NOT:** Implement any gesture semantics beyond raw event capture

---

## Absolute Prohibitions

No framework: React, Electron, Next.js, LangChain, CrewAI, any web or AI orchestration framework
No runtime AI: no ML models, no probabilistic routing, no learned heuristics embedded in production paths
No plugin systems: no hook registries, no observer-of-observers, no generic coordinators
No cross-layer state mutation: callers must not mutate state they do not own
No geometry in gesture layer: pixels never appear in GestureEngine
No semantic logic in AX layer: layout states never appear in LayoutOrchestrator

---

## Abstraction Depth Limit

Maximum call depth for any user-initiated gesture → frame write path: **4 hops**

```
GestureEngine → SpatialTransitionEngine → LayoutResolver → LayoutOrchestrator
```

No middleware, no event bus, no indirection layers between these.

---

## Future Layer: WorkspaceTopology

When introduced, WorkspaceTopology must:
- Live in `Sources/SwishCore/Workspace/`
- Own: focal window, supporting windows, peripheral windows, layout style
- Be consumed by: SpatialTransitionEngine (multi-finger operations)
- NOT replace: WindowStateStore (per-window state stays there)
- NOT touch: LayoutOrchestrator, GestureEngine

---

## Naming Conventions

- Semantic positions: `WindowLayoutState` enum cases (camelCase, readable English)
- Transitions: `LayoutTransitionGraph.buildTable()` — one `add()` call per transition
- Sessions: single active session in SpatialTransitionEngine — `sessionWindow`, `sessionStartFrame`
- Identities: `WindowID` wraps `AXUIElement` for Hashable conformance
