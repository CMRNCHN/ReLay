# PROJECT_STATE.md

**As of:** 2026-05-15

---

## Identity

| | |
| --- | --- |
| Product name | ReLay |
| Repository root | `/Users/cameroncohen/dev/projects/ReLay` |
| Build system | Swift Package Manager (`Package.swift`) |
| Stage | Build recovery plus runtime validation |
| Governance system | `.ai/GOVERNANCE` + `.ai/REPODOCK` |

---

## Current Reality

- ReLay is a standalone SwiftPM repository.
- The executable target `ReLay` exists in `Sources/ReLay`.
- The core module `ReLayCore` exists in `Sources/ReLayCore`.
- Bootstrap, accessibility instrumentation, and deterministic logging scaffolding are present.
- The AI workspace uses the `GOVERNANCE` + `REPODOCK` layout.
- The current worktree does **not** build cleanly: `swift build` and `swift test` both fail on a string interpolation syntax error in `Sources/ReLayCore/TitleBarInterceptor.swift`.

---

## What Is Built

### Package Shape

- one executable target: `ReLay`
- one core target: `ReLayCore`
- one test target: `ReLayCoreTests`

### Core Runtime Layers Present

- `GestureEngine.swift` owns gesture physics.
- `SpatialTransitionEngine.swift` owns semantic transition orchestration.
- `LayoutResolver.swift` owns geometry resolution.
- `LayoutOrchestrator.swift` owns AX frame application and animation primitives.
- `WindowStateStore.swift` owns per-window semantic state persistence.
- `PreviewManager.swift` owns preview display.
- `TitleBarInterceptor.swift` owns event capture and title-bar qualification.

### Governance + Process

- governance rules live in `.ai/GOVERNANCE/`
- task, handoff, plan, log, and context records live in `.ai/REPODOCK/`
- `CURRENT_TASK.md` is the required start-of-task review and end-of-task update surface

---

## Current Verification Status

- `swift build`: failing
- `swift test`: failing
- only test present today is a bootstrap placeholder
- no current evidence of a passing automated semantic-core verification layer
- no current evidence of a repeatable human-test workflow

---

## Active Architectural Risks

- buildability is currently broken in `TitleBarInterceptor.swift`
- live gesture ingress is still app- and chrome-dependent
- runtime observability is still shallow outside the current trace points
- no automated tests cover transition, resolver, or store invariants
- topology vocabulary is still planned rather than formalized
- hidden coupling may remain across gesture capture, transition orchestration, and AX side effects

---

## Intended Runtime Chain

```text
GestureEngine
-> SpatialTransitionEngine
-> LayoutResolver
-> LayoutOrchestrator
-> WindowStateStore
```

---

## Ownership Snapshot

| File | Ownership |
| --- | --- |
| `Sources/ReLay/main.swift` | App bootstrap and runtime startup |
| `Sources/ReLayCore/GestureEngine.swift` | Gesture physics and commit / cancel thresholds |
| `Sources/ReLayCore/SpatialTransitionEngine.swift` | Semantic transition routing |
| `Sources/ReLayCore/LayoutResolver.swift` | Pure layout-state to frame mapping |
| `Sources/ReLayCore/LayoutOrchestrator.swift` | AX window mutation and animation |
| `Sources/ReLayCore/WindowStateStore.swift` | Per-window semantic state and history |
| `Sources/ReLayCore/PreviewManager.swift` | Preview overlay display |
| `Sources/ReLayCore/TitleBarInterceptor.swift` | Event interception and title-bar hit testing |

---

## Not Yet Stabilized

- build and test baseline
- accessibility bootstrap validation across more host conditions
- end-to-end gesture capture repeatability across app chrome variants
- transition observability and trace correlation
- workspace topology vocabulary
- replay / inspection tooling
- meaningful automated tests
- tester-facing install and validation workflow

---

## Near-Term Direction

1. restore a clean build and test baseline
2. add focused tests for transition graph, resolver, and state store
3. improve gesture ingress reliability and trace quality
4. define a repeatable human-test checklist and entry criteria
