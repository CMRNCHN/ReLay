# READY_FOR_HUMAN_TESTING.md

## Goal

Reach a state where a human tester can install or run ReLay, grant permissions, exercise its core gestures across a known set of apps, and produce reliable feedback without first debugging the build, the environment, or the semantic model.

## Ready-For-Human-Testing Definition

ReLay is ready for human testing when all of the following are true:

1. the repo builds and tests cleanly from a documented local setup
2. the semantic core has focused automated coverage
3. the runtime can start, request permissions, and surface failure states clearly
4. two-finger gesture transitions work repeatably in a defined set of target apps
5. multi-window actions are either stable enough to test or explicitly disabled from the test scope
6. a tester can follow a short checklist and report issues in a structured way

---

## Phase 0 - Recover A Trustworthy Baseline

### Objective

Get the repo back to a state where current source compiles and tests can run.

### Work

- fix the current `TitleBarInterceptor.swift` syntax break
- re-run `swift build` and `swift test`
- remove any stale project-state claims that no longer match runtime reality

### Exit Criteria

- `swift build` passes
- `swift test` runs to completion
- `PROJECT_STATE.md` reflects actual verification status

### Why This Comes First

Human testing is blocked if contributors cannot produce a runnable app from the current branch.

---

## Phase 1 - Harden The Semantic Core

### Objective

Make the deterministic model trustworthy before relying on live UI behavior.

### Work

- add table-driven tests for `LayoutTransitionGraph`
- add geometry tests for `LayoutResolver.frame(for:on:)`
- add inference tests for `LayoutResolver.inferState(from:on:)`
- add state-history tests for `WindowStateStore` and `WindowRecord`

### Exit Criteria

- semantic transition coverage exists for all supported states and directions
- resolver coverage exists for each named layout state
- state-store history and floating-frame invariants are tested

### Notes

This is the lowest-cost confidence layer and should absorb many regressions before manual testing.

---

## Phase 2 - Stabilize Gesture Ingress

### Objective

Make title-bar qualification and gesture session start predictable enough for a tester to trust what they are seeing.

### Work

- finish the current `TitleBarInterceptor` stabilization work
- characterize ingress across Finder, Safari, Terminal, Xcode, and Settings
- separate geometric misses from semantic AX misses in logs
- tighten start-point rules so failures are explainable and consistent

### Exit Criteria

- a defined matrix of target apps has repeatable two-finger ingress behavior
- misses are diagnosable from logs without adding ad hoc debug code
- no known compile-time or immediate startup regressions remain in the interceptor path

---

## Phase 3 - Improve Runtime Observability And Safety

### Objective

Make failures visible and limit tester confusion when behavior does not engage.

### Work

- add per-gesture correlation IDs across interceptor, gesture, transition, resolver, and state-store logs
- ensure startup logs clearly report accessibility trust and interceptor startup outcome
- define safe behavior when permissions are missing or runtime hooks fail
- consider temporarily gating unstable multi-window gestures behind explicit test scope rules

### Exit Criteria

- one gesture session can be traced end to end from logs
- startup failure modes are explicit
- unstable features are either stabilized or removed from the first human-test pass

---

## Phase 4 - Define The Human Test Surface

### Objective

Reduce the first test pass to a small, high-value scope.

### Work

- decide the exact feature set for first human testing:
  - likely include 2-finger semantic transitions
  - likely exclude or tightly limit 3-finger and 4-finger multi-window actions until stabilized
- define supported apps and window styles for the first pass
- define expected behaviors for each gesture and state transition
- document known non-goals and unstable areas

### Exit Criteria

- test scope fits on one page
- each included behavior has a clear expected result
- excluded behaviors are explicit, not ambiguous

---

## Phase 5 - Package A Tester Workflow

### Objective

Make the app runnable by a human without developer interpretation.

### Work

- write a short setup checklist:
  - macOS version
  - accessibility permission steps
  - how to launch the app
  - how to confirm the interceptor is active
- write a manual test checklist covering:
  - app launch
  - permission handling
  - baseline gesture activation
  - left / right / up / down transitions
  - cancel and snap-back behavior
- write a bug report template for:
  - app under test
  - start-point region
  - gesture direction
  - expected result
  - actual result
  - relevant log excerpt

### Exit Criteria

- a tester can follow the checklist without pairing with an engineer
- issue reports arrive with enough structure to reproduce failures

---

## Phase 6 - Human Test Gate

### Launch Criteria

- build passes
- tests pass
- semantic core tests exist
- startup path is explicit and understandable
- two-finger gesture path is repeatable in the agreed app matrix
- tester checklist and bug template exist

### Success Criteria For The First Human Pass

- testers can complete the checklist
- failures cluster into a manageable set of reproducible issues
- no catastrophic behaviors appear, such as broken startup, invisible failure states, or uncontrolled window moves

---

## Recommended Task Sequence

1. fix the current compile break
2. replace the placeholder test target with semantic-core tests
3. finish title-bar ingress stabilization with a target-app matrix
4. add end-to-end trace correlation
5. document the first human-test scope and checklist
