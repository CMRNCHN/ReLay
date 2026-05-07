# AIR_RULES.md

Operating rules for AI-assisted engineering inside Air for the Re-Lay project.
These rules are non-negotiable. Violations require explicit human approval.

---

## Session Protocol

### At Session Start — Always Load

1. `.ai/PROJECT_STATE.md` — current architecture state
2. `.ai/ARCHITECTURE_RULES.md` — structural constraints
3. `.ai/PRODUCT_PRINCIPLES.md` — product identity and philosophy
4. `.ai/NEXT_SESSION.md` — queued tasks and context
5. `.ai/AIR_RULES.md` — this file

### During a Session — Only Perform

- Scoped, explicitly-requested tasks
- Bounded refactors with clear before/after boundaries
- Deterministic improvements with verifiable outcomes
- Directly requested architecture evolution

### At Session End — Always

1. Summarize changes made and files affected
2. Summarize which architectural boundaries were touched
3. Summarize behavioral changes introduced (even if none)
4. Identify future refactor pressure created by this session
5. Note any risks introduced
6. Update `.ai/HANDOFF.md`
7. Update `.ai/PROJECT_STATE.md` if architecture changed
8. Update `.ai/NEXT_SESSION.md` with new priorities

---

## Always

- Preserve deterministic gesture behavior — every (state × direction) must map to exactly one outcome
- Preserve explicit transition logic — transitions live in `LayoutTransitionGraph`, not in callers
- Preserve semantic layout identity — `WindowLayoutState` is the source of truth, not raw CGRect
- Preserve reversible state transitions — history and floating frame capture must remain intact
- Preserve workspace topology ownership — no layer should claim ownership of another's domain
- Preserve explicit geometry resolution — `LayoutResolver` is the single site of frame math
- Preserve low abstraction depth — concrete, readable behavior over clever indirection
- Preserve native macOS conventions — extend the platform, do not fight it
- Preserve clear ownership boundaries — each file owns exactly one domain

---

## Never

- Redesign architecture without explicit human instruction
- Introduce hidden AI runtime behavior at any layer
- Add LangChain, CrewAI, or any recursive agent orchestration system
- Add Electron, React, Next.js, or any web frontend framework
- Add generalized plugin systems or hook registries
- Add unnecessary coordinator objects that own no clear state
- Add excessive protocol abstraction (protocols justified only by testability or substitutability)
- Add reactive architecture (Combine, RxSwift) without explicit instruction
- Make gestures directly own geometry or layout decisions
- Replace semantic states with raw geometry inference
- Introduce hidden side effects inside pure-function layers
- Modify `LayoutTransitionGraph` without also updating tests

---

## Prefer

- Incremental commits — one bounded change per commit
- Scoped refactors — no drive-by cleanup beyond the stated task
- Explicit ownership — clear answer to "who owns this state?"
- Concrete behavior before abstraction — ship the working case, generalize only under pressure
- Semantic states over raw geometry inference
- Deterministic transition maps over heuristic inference
- Visible orchestration — sequence is obvious from reading the code
- Low conceptual complexity — a new engineer should understand any file in 10 minutes
- Small modular improvements over large coordinated rewrites

---

## After Every Meaningful Refactor

1. Run tests (once test infrastructure exists)
2. Summarize changed boundaries
3. Summarize behavioral changes
4. Summarize risks introduced
5. Identify future refactor pressure
6. Update `.ai/HANDOFF.md`

---

## Architecture Domains — Do Not Cross Without Explicit Task

| Domain | Owner File(s) | Boundary |
|--------|--------------|---------|
| Gesture physics | GestureEngine.swift | Axis, velocity, timing — nothing else |
| Semantic states | WindowLayoutState.swift | Enum + transition graph |
| State persistence | WindowStateStore.swift | Per-window record + history |
| Geometry resolution | LayoutResolver.swift | Pure frame math, no AX, no side effects |
| Transition orchestration | SpatialTransitionEngine.swift | Routes gesture → state → frame → animation |
| AX primitives + animation | LayoutOrchestrator.swift | Window manipulation only |
| Preview overlay | PreviewManager.swift | Display only, no state |
| Event capture | TitleBarInterceptor.swift | Input interception only |

---

## Prohibited Patterns

```
// NEVER: gesture owns layout decision
func gestureDidEnd() {
    window.setFrame(CGRect(x: 0, y: 0, width: screen.width / 2, height: screen.height))
}

// NEVER: raw frame inference replaces semantic state
let state = frame.width < 700 ? .leftHalf : .floating

// NEVER: cross-layer direct call
class GestureEngine {
    func commit() { WindowStateStore.shared.updateState(.leftHalf, for: window) }
}

// NEVER: hidden side effect in resolver
class LayoutResolver {
    func frame(for state: ...) -> CGRect {
        analytics.track("frame_resolved")  // side effect — prohibited
        return ...
    }
}
```

---

## Permitted Evolution Paths

These are the expected next architectural additions, in priority order:

1. **Test infrastructure** — XCTest coverage for LayoutTransitionGraph, LayoutResolver, WindowStateStore
2. **Domain directory migration** — move files into `Sources/SwishCore/` subdirectories
3. **WorkspaceTopology struct** — introduce focal/supporting/peripheral window roles
4. **Topology-aware transition entries** — graph entries that consider workspace context
5. **Diagnostics layer** — structured logging to `storage/diagnostics/`

Each must be introduced as a discrete, bounded session task.
