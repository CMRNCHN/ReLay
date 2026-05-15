# Phase 1 Analysis: Gesture→Action Coupling & Migration Seams

## Context

ReLay's current pipeline routes gestures directly to layout actions: pixel deltas become cardinal directions, cardinal directions index a state transition table keyed by screen-edge names, and multi-finger operations are dispatched by raw `(fingerCount, direction, location)` tuples. This works, but it embeds edge/directional semantics at every layer, blocking evolution toward the target model where "the workspace reorganizes itself around intent." This analysis maps every coupling site, identifies migration seams, and proposes bounded incremental refactors that introduce semantic intent without abstraction explosion.

---

## 1. Architecture Pressure Map

### A. The Central Bottleneck: `commitSession()`
**File:** `Sources/ReLayCore/SpatialTransitionEngine.swift:80-101`

This is the single dispatch point where raw gesture physics select layout operations. The if/else tree routes on `(fingerCount, direction, location)`:

```
fingerCount >= 4 + up       → executeExitLayout
fingerCount >= 4 + other    → executeStageManagerLayout
fingerCount == 3 + down + center → executeThreeColumnLayout
fingerCount == 3 + other    → executeAutoLayout
fingerCount == 2             → executeStateTransition(direction:)
```

**Pressure:** Every new workspace operation requires another branch in this tree. There is no vocabulary for what the user *intends* — only what their fingers *did*.

### B. Direction-Keyed Transition Graph
**File:** `Sources/ReLayCore/WindowLayoutState.swift:44-112`

`LayoutTransitionGraph` maps `(WindowLayoutState × GestureDirection) → WindowLayoutState`. The graph is keyed by cardinal directions, not by semantic operations like "narrow focus" or "widen prominence."

**Pressure:** The graph can only express transitions that map to a single directional swipe. Intent-level operations like "distribute workspace" or "compress workspace" have no representation.

### C. Edge-Named State Enum
**File:** `Sources/ReLayCore/WindowLayoutState.swift:21-40`

All 11 states are named by screen position: `leftHalf`, `rightThird`, `leftTopSixth`, etc.

**Pressure:** Low urgency — these names are internal and the `LayoutResolver` correctly treats them as abstract tokens. Renaming is cosmetic and risky. Leave for later.

### D. GestureDirection as Semantic Proxy
**File:** `Sources/ReLayCore/WindowLayoutState.swift:5-16`

`GestureDirection` (left/right/up/down) is the *only* vocabulary between gesture physics and the state machine. Downstream code treats it as semantic intent rather than raw input.

### E. Location-Based Routing Heuristic
**File:** `Sources/ReLayCore/SpatialTransitionEngine.swift:228-233`

`isNearScreenCenter()` (160px threshold) gates 3-finger behavior. A proto-intent signal expressed as a pixel test.

### F. Preview Coupling to Direction
**File:** `Sources/ReLayCore/SpatialTransitionEngine.swift:56-76`

Preview only works for 2-finger gestures. 3-finger and 4-finger have no preview. Intent-driven preview would fix this.

### G. Multi-Window Operations as Special Cases
**Files:** `SpatialTransitionEngine.swift:143-215`

Four separate execute methods share patterns but aren't unified. `executeThreeColumnLayout` and `executeStageManagerLayout` both do "distribute workspace into grid" with different column counts.

---

## 2. Migration Seams

### Seam 1 (Primary): Between gesture-parameter dispatch and execute methods
**Location:** `SpatialTransitionEngine.swift:80-101` → `execute*()` methods

Extract `resolveIntent()` that converts `(fingerCount, direction, location, currentState)` → `SpatialIntent`, then `dispatchIntent()` that routes to execute methods. Internal to SpatialTransitionEngine — no other file changes.

### Seam 2 (Secondary): Between intent resolution and state graph
**Location:** `LayoutTransitionGraph.nextState(from:moving:)` at `WindowLayoutState.swift:58-60`

Once intents exist, some bypass the graph entirely (distribute/restore) while others still need direction (transitionWindow).

### Seam 3 (Future): Between intent and WorkspaceTopology
Does not exist yet. The intent layer is the natural integration point for topology-aware transitions.

---

## 3. Proposed Incremental Refactors

### Refactor 0: Test Infrastructure (Prerequisite)
- Create `Tests/ReLayCoreTests/LayoutTransitionGraphTests.swift`
- Create `Tests/ReLayCoreTests/LayoutResolverTests.swift`
- Create `Tests/ReLayCoreTests/WindowStateStoreTests.swift`

**Files created:** 3 | **Files modified:** 0 | **Risk:** None

### Refactor 1: Introduce `SpatialIntent` Enum
Create `Sources/ReLayCore/SpatialIntent.swift`:

```swift
enum SpatialIntent {
    case transitionWindow(direction: GestureDirection)
    case focusWindow
    case distributeWorkspace(columns: Int?)
    case restoreWorkspace
}
```

**Files created:** 1 | **Files modified:** 0 | **Risk:** None

### Refactor 2: Extract `resolveIntent()` and `dispatchIntent()`
Mechanical extraction in `SpatialTransitionEngine.swift`. `commitSession()` becomes: resolve intent → dispatch intent. Identical behavior.

**Files modified:** 1 | **Lines changed:** ~30 | **Risk:** Low

### Refactor 3: Intent-Driven Preview
Modify `updatePreview()` to resolve intent before querying graph. Opens door to 3-finger/4-finger previews.

**Files modified:** 1 | **Risk:** Medium (changes user-visible preview behavior)

### Refactor 4: Unify Distribute Operations
Merge `executeThreeColumnLayout` and `executeStageManagerLayout` into `executeDistributeWorkspace(columns:)`.

**Files modified:** 1 | **Lines changed:** ~25 | **Risk:** Low

### Refactor 5 (Deferred): Semantic Role Aliases
Add computed properties to `WindowLayoutState` (isFocal, isProminent, isDense, column). Useful for future WorkspaceTopology.

---

## 4. Dependency Graph

```
Refactor 0 (Tests)
    ├──→ Refactor 1 (SpatialIntent enum)
    │        └──→ Refactor 2 (resolveIntent + dispatchIntent)
    │                 ├──→ Refactor 3 (intent-driven preview)
    │                 └──→ Refactor 4 (unify distribute)
    └──→ Refactor 5 (semantic aliases — independent, deferred)
```

## 5. Recommended First Move

**Refactor 0 → 1 → 2**, in order. Tests first, then vocabulary, then the seam.

## 6. What NOT to Do Yet

- Rename `WindowLayoutState` cases (touches every file)
- Replace `GestureDirection` at gesture layer (should stay physics-only)
- Introduce `WorkspaceTopology` (needs intent layer first)
- Make `LayoutTransitionGraph` intent-aware (not needed until topology exists)
- Add reactive/observable patterns (architecture rule violation)

## 7. Verification

After each refactor: `swift build`, `swift test`, manual test all gesture paths (2/3/4-finger), preview overlay, snap-back, undo.