# relay:verify-invariants

Mechanically verify the four architectural invariants of the ReLay system. Do not modify any files. Report pass/fail per invariant with evidence.

## Invariants to check

### INV-1: LayoutOrchestrator is the only AX position/size writer
Grep `Sources/` for `kAXPositionAttribute` and `kAXSizeAttribute` writes (`AXUIElementSetAttributeValue`).
- PASS: all writes are in `LayoutOrchestrator.swift`
- FAIL: list every violation with file and line number

### INV-2: SpatialTransitionEngine owns all gesture session state
Grep `Sources/` for `sessionWindow`, `sessionScreenFrame`, `sessionStartFrame`, `sessionFingerCount`, `currentGestureID`.
- PASS: all reads/writes are inside `SpatialTransitionEngine.swift`
- FAIL: list every external reference

### INV-3: GestureEngine never modifies layout or touches AX
Grep `GestureEngine.swift` for: `AXUIElement`, `AXUIElementSet`, `LayoutOrchestrator`, `SpatialTransitionEngine` direct calls (not via protocol), `animateWindowFrame`, `setWindowFrame`.
- PASS: none found
- FAIL: list every violation

### INV-4: isActive has a single write site per execution path
Grep `Sources/` for `isActive = true` and `isActive = false` and `.isActive =`.
- PASS: exactly one write site in the gesture path and one in the expose path
- FAIL: list every write site found

## Output format

```
INVARIANT VERIFICATION REPORT
──────────────────────────────
INV-1 LayoutOrchestrator AX exclusivity: [PASS|FAIL]
  Evidence: <findings or "clean">

INV-2 SpatialTransitionEngine session ownership: [PASS|FAIL]
  Evidence: <findings or "clean">

INV-3 GestureEngine layout isolation: [PASS|FAIL]
  Evidence: <findings or "clean">

INV-4 isActive single write site: [PASS|FAIL]
  Evidence: <findings or "clean">

ADDITIONAL AX WRITES OUTSIDE ORCHESTRATOR
──────────────────────────────────────────
(Non-position/size AX writes — informational, not invariant violations)
<file>:<line> — <attribute> — <context>
```

## Constraints
- Do NOT fix anything.
- Do NOT rename anything.
- Report only.
