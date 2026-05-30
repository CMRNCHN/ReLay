# GESTURE_INGRESS_MATRIX.md

**Purpose:** Reference for characterizing two-finger gesture ingress per target app.
Each row describes the expected AX signals, variant classification, and topBandHeight
that TitleBarInterceptor should apply. Use this alongside live logs to confirm or
diagnose each app.

---

## How to read log output

Every hit, semantic miss, and geometric miss now emits:

```
[interceptor] <outcome> app=<name> bundle=<id> variant=<v> topBand=<px>
              hitRole=<role> [subrole=<sub>] [reason=<detail>]
```

- **outcome**: `title bar hit` | `semantic miss` | `geometric miss`
- **variant**: the chrome shape detected — see table below
- **topBand**: the pixel height used for geometric fallback
- **reason**: for misses, the specific guard that failed

---

## Target App Matrix

| App | Bundle ID | Expected Variant | Expected topBand | Notes |
|-----|-----------|-----------------|-----------------|-------|
| Finder | com.apple.finder | unified-toolbar | 80 | Standard toolbar + title. Should hit reliably. |
| Safari | com.apple.Safari | tabbed-toolbar | 80 | Tab strip + address bar combined. Pre-fix used 44px; now 80px. |
| Terminal | com.apple.Terminal | tabbed | 44 | Tab bar only; no nav toolbar. 44px is correct. |
| Xcode | com.apple.dt.Xcode | tabbed-toolbar | 80 | Editor tabs + run toolbar. Combines both signals. |
| System Settings | com.apple.systempreferences | standard-titlebar | 40 | Standard title bar. Content ownership may fire if gesture lands on sidebar. |

---

## Known Risk Points

### Safari (tabbed-toolbar → 80px)
- Pre-2026-05-20 the code returned 44px for any app with AXTabGroup, which was less
  than Safari's combined tab-strip + address-bar height (~78px). Gestures in the lower
  portion of the toolbar region triggered geometric misses.
- Fix: `hasTabGroup && hasToolbar` now maps to 80px.
- Confirm in logs: `variant=tabbed-toolbar topBand=80`.

### Xcode (tabbed-toolbar → 80px)
- Xcode may render its run toolbar at or above 80px on some configurations.
- If geometric misses appear, check `reason=` for the actual point/band values and
  adjust `topBandHeight` for the `tabbed-toolbar` case.

### System Settings (standard-titlebar → 40px)
- Settings uses a full-size content view; the sidebar (AXOutline) reaches near the top.
- If the gesture lands over the sidebar column, `hasContentOwnership = true` triggers a
  semantic miss with `reason=content-ownership`.
- This is correct behavior — the gesture is not on the title bar chrome.
- Tester should start the gesture clearly on the top-left title bar chrome (traffic light area).

### Apps with blended content (Maps, Music, Photos)
- Not in the primary test matrix but may appear as `content-owned` misses.
- Expected behavior: these apps intentionally blend content under the title bar and
  should not accept gestures — semantic miss is correct.

---

## How to characterize a new app

1. Run ReLay and focus the target app window.
2. Start a two-finger vertical scroll gesture in the title bar area.
3. Check logs: `log stream --predicate 'subsystem == "interceptor"'`
4. Record: app name, bundle ID, variant, topBand, outcome.
5. If geometric miss: compare `pointY` against `titleBarMaxY` — the gap indicates
   whether `topBandHeight` needs adjustment.
6. If semantic miss with `content-ownership`: the gesture landed on a content element.
   Check whether the hit was in the actual title bar region or in content chrome.
7. Update this table with findings.

---

## Verification Status

| App | Characterized | Code Fix Applied | Status |
|-----|--------------|-----------------|--------|
| Finder | code-only | — | Pending live verification |
| Safari | code-only | tabbed-toolbar height 44→80 | Pending live verification |
| Terminal | code-only | — | Pending live verification |
| Xcode | code-only | tabbed-toolbar height benefit | Pending live verification |
| System Settings | code-only | — | Pending live verification |
