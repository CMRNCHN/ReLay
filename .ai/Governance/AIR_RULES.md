# AIR_RULES.md

Operating rules for AI-assisted engineering inside Air for the ReLay project.
These rules are mandatory unless a human explicitly overrides them.

---

## Required Session Start Review

Before starting any task, review these files in order:

1. `.ai/GOVERNANCE/AIR_RULES.md`
2. `.ai/GOVERNANCE/AI_AGENT_RULES.md`
3. `.ai/GOVERNANCE/ARCHITECTURE_RULES.md`
4. `.ai/REPODOCK/CURRENT/PROJECT_STATE.md`
5. `.ai/REPODOCK/CONTEXT/PRODUCT_PRINCIPLES.md`
6. `.ai/REPODOCK/TASKS/CURRENT_TASK.md`
7. `.ai/REPODOCK/TASKS/NEXT_SESSION.md`
8. `.ai/REPODOCK/PLANS/ACTIVE_PLAN.md`

Do not skip the task record review. `CURRENT_TASK.md` is the active handoff surface for the next task.

---

## Required Session End Updates

At the end of every meaningful task:

1. Update `.ai/REPODOCK/TASKS/CURRENT_TASK.md`
2. Update `.ai/REPODOCK/HANDOFFS/LATEST_HANDOFF.md`
3. Update `.ai/REPODOCK/CURRENT/PROJECT_STATE.md` if architecture or runtime reality changed
4. Update `.ai/REPODOCK/TASKS/NEXT_SESSION.md` if priorities changed
5. Add a dated file under `.ai/REPODOCK/LOGS/` when the task materially changes process, architecture, or runtime understanding

Every end-of-task update must record:

- objective
- files touched
- boundaries touched
- behavioral impact
- risks introduced
- follow-up pressure
- next recommended task

---

## Always

- Preserve deterministic gesture behavior: every `(state x direction)` maps to exactly one outcome
- Preserve explicit transition logic in `LayoutTransitionGraph`
- Preserve semantic layout identity in `WindowLayoutState`
- Preserve reversible transitions and floating-frame capture
- Preserve workspace topology ownership boundaries
- Preserve explicit geometry resolution in `LayoutResolver`
- Preserve low abstraction depth and readable control flow
- Preserve native macOS conventions
- Preserve clear ownership boundaries per file and layer

---

## Never

- Redesign the architecture without explicit human instruction
- Introduce hidden AI runtime behavior
- Add LangChain, CrewAI, or recursive agent orchestration
- Add Electron, React, Next.js, or web frontend frameworks
- Add generalized plugin systems or hook registries
- Add unnecessary coordinator objects with no clear state ownership
- Add excessive protocol abstraction unless justified by testability or substitutability
- Add reactive architecture without explicit instruction
- Let gestures own geometry or layout decisions
- Replace semantic states with raw geometry inference
- Introduce hidden side effects inside pure-function layers
- Modify `LayoutTransitionGraph` without updating tests once tests exist

---

## Prefer

- Incremental, bounded changes
- Scoped refactors
- Explicit state ownership
- Concrete behavior before abstraction
- Semantic states over inferred geometry
- Deterministic transition maps over heuristics
- Visible orchestration
- Low conceptual complexity
- Small modular improvements over coordinated rewrites

---

## Architecture Domains

| Domain | Owner File(s) | Boundary |
| --- | --- | --- |
| Gesture physics | `GestureEngine.swift` | Axis, velocity, timing only |
| Semantic states | `WindowLayoutState.swift` | Enum plus transition graph |
| State persistence | `WindowStateStore.swift` | Per-window record, history, floating frame |
| Geometry resolution | `LayoutResolver.swift` | Pure frame math only |
| Transition orchestration | `SpatialTransitionEngine.swift` | Gesture to state to frame routing |
| AX primitives + animation | `LayoutOrchestrator.swift` | Window manipulation only |
| Preview overlay | `PreviewManager.swift` | Display only |
| Event capture | `TitleBarInterceptor.swift` | Input interception only |

---

## Permitted Evolution Paths

1. Test infrastructure for transition graph, resolver, and state store
2. Domain directory migration under `Sources/ReLayCore/`
3. `WorkspaceTopology` introduction
4. Topology-aware transition entries
5. Structured diagnostics under `storage/diagnostics/`

Each must be introduced as a discrete, bounded task and reflected in `CURRENT_TASK.md` and `LATEST_HANDOFF.md`.
