# NEXT_SESSION.md

**Prepared:** 2026-05-15

---

## Priority 1 - Restore Build Baseline

Why:
The repo currently fails both `swift build` and `swift test`, which blocks every later readiness step.

- fix the `TitleBarInterceptor.swift` string interpolation syntax error
- verify `swift build`
- verify `swift test`

## Priority 2 - Add Semantic-Core Tests

Why:
Once buildability is restored, the semantic model needs automated protection before more runtime experimentation.

- add focused tests for `LayoutTransitionGraph`
- add focused tests for `LayoutResolver`
- add focused tests for `WindowStateStore`

## Priority 3 - Resume Gesture Ingress Stabilization

Why:
Human testing depends on repeatable gesture activation in a small supported app matrix.

- characterize Finder, Safari, Terminal, Xcode, and Settings
- separate geometric misses from AX semantic misses
- keep fixes scoped to `TitleBarInterceptor` unless deeper evidence appears

## Constraints

- do not redesign architecture
- do not increase abstraction depth
- do not broaden the task beyond observed evidence
- update `CURRENT_TASK.md` at task start and task end
