# CURRENT_TASK.md

## Task Title

Phase 1 + Phase 2 (partial): semantic-core tests + gesture ingress improvements

## Request Date

2026-05-20

## Status

Completed

## Objective

Harden the semantic core with automated test coverage and advance gesture ingress
stabilization toward the five-app target matrix.

## Work Done

### Phase 1 — Semantic Core Tests (complete)

Added `Tests/ReLayCoreTests/SemanticCoreTests.swift` with three suites:

- `TransitionGraphTests` — 34 tests covering every edge in `LayoutTransitionGraph`,
  including cross-column sixth jumps, vertical subdivision, and edge-resistance nil cases.
- `LayoutResolverTests` — 21 tests covering geometry for all named states, inference
  round-trips, unknown/zero-frame fallback to `.floating`, and interpolation clamping.
- `WindowRecordTests` — 7 tests covering state transitions, rewind, history cap at 12,
  and floatingFrame preservation across transitions.

Total test count: 10 → 72. All passing.

### Phase 2 — TitleBarInterceptor ingress fixes (partial)

Fixed `ChromeSignals` in `TitleBarInterceptor.swift`:

- Added `tabbed-toolbar` variant for apps that expose both AXTabGroup and AXToolbar
  (Safari, Chrome, Xcode). Previous code returned 44px topBandHeight for any app with
  tabs regardless of whether a toolbar was also present; now returns 80px for the
  combined case.
- `tabbed`-only variant (Terminal) still uses 44px.
- Added `bundleID(for:)` helper.
- All miss log lines now include `bundle=<id>` and `topBand=<px>` for per-app calibration.

Created `.ai/REPODOCK/CONTEXT/GESTURE_INGRESS_MATRIX.md` — reference table documenting
expected variant, topBandHeight, and risk points for each target app, plus a live-log
characterization guide.

## Architecture Boundaries Touched

- `TitleBarInterceptor` — chrome signal classification and diagnostic logging
- test target only (new file)
- REPODOCK context docs

## Behavior Changes

- Two-finger gestures in the combined tab+toolbar region of Safari and Xcode will now
  be accepted where they previously triggered geometric misses.
- Logs now emit `bundle=` and `topBand=` on every outcome, enabling per-app diagnostics.

## Risks / Follow-Ups

- Live verification still needed across all five target apps.
- Xcode's toolbar height on large displays may exceed 80px — check logs if misses persist.
- System Settings content-ownership behavior is correct but should be confirmed on device.

## Next Task Recommendation

Run ReLay against the five-app matrix (Finder, Safari, Terminal, Xcode, Settings),
collect logs, and fill in the verification-status table in GESTURE_INGRESS_MATRIX.md.
Then proceed to Phase 3 (runtime observability — per-gesture correlation IDs).
