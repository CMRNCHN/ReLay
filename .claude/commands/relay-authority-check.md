# relay:authority-check

Detect ownership conflicts, circular dependencies, authority violations, and
competing sources of truth inside ReLayCore. READ ONLY — do not modify any files.

## Authority Rules

### RULE 1 — AX MUTATION AUTHORITY
Canonical owner: `LayoutOrchestrator`

Scan all `Sources/ReLayCore/*.swift` for `AXUIElementSetAttributeValue` and
`AXUIElementCopyAttributeValue`. Any call outside `LayoutOrchestrator.swift`
is a potential violation.

Classify each external call:
- **write** (`AXUIElementSetAttributeValue`) — always flag
- **read** (`AXUIElementCopyAttributeValue`) — flag if it duplicates a read
  already performed by `LayoutOrchestrator` (e.g. getWindowFrame, getAllVisibleWindows)

For each flagged call record: file, line number, attribute name, write vs read.

### RULE 2 — ACTIVE WINDOW AUTHORITY
Canonical owner: `LayoutExposeController` (snapshot at present-time)

Scan all `Sources/` for:
- `NSWorkspace.shared.frontmostApplication`
- `frontmostPID`
- `isActive = true` / `isActive = false` / `.isActive =` on `LayoutWindowItem`
- Any other derivation of "which window is currently active"

Flag every site that is NOT inside `LayoutExposeController.makeWindowItems()`.
Multiple derivation sites = authority conflict.

### RULE 3 — SESSION AUTHORITY
Canonical owner: `SpatialTransitionEngine`

Scan all `Sources/` for:
- `sessionWindow`, `sessionScreenFrame`, `sessionStartFrame`, `sessionFingerCount`
- `currentGestureID`, `gestureID`
- Any variable named `session*` outside `SpatialTransitionEngine.swift`

Flag every external read or write. A variable that holds a *copy* of a session
identifier (even for logging only) is a dual-ownership signal — flag it and
note whether it is a mirror (read-only use) or a competing owner (read+write).

### RULE 4 — DECISION AUTHORITY
Canonical owner: `SpatialTransitionEngine`

Scan all `Sources/` for:
- Direct calls to `LayoutTransitionGraph` outside `SpatialTransitionEngine.swift`
- Direct calls to `LayoutResolver` outside `SpatialTransitionEngine.swift`
- `animateWindowFrame` or `setWindowFrame` called from outside `SpatialTransitionEngine`
  or `LayoutExposeController` (the two approved callers)
- Any file that computes a target `CGRect` for a window and passes it to
  `LayoutOrchestrator` without going through `SpatialTransitionEngine`

Flag each site with file, line, and what decision is being made.

### RULE 5 — CIRCULAR DEPENDENCY DETECTION
For each pair of files (A, B) in `Sources/ReLayCore/`, check whether A calls
into B AND B calls into A (by scanning for type references, method calls, and
`.shared` singleton access).

Pay particular attention to cycles involving:
- `SpatialTransitionEngine` ↔ `LayoutExposeController`
- `SpatialTransitionEngine` ↔ `LayoutSuggestionEngine`
- `LayoutExposeController` ↔ `LayoutOrchestrator`
- `LayoutExposeController` ↔ `LayoutSuggestionEngine`

For each detected cycle, show the full call path:
```
FileA:line → FileB:line → FileA:line
```

## Output Format

```
AUTHORITY CHECK REPORT
──────────────────────

SECTION 1 — AUTHORITY MAP
Canonical owners and their current enforcement status:

  AX mutation      → LayoutOrchestrator          [ENFORCED|PARTIAL|VIOLATED]
  Active window    → LayoutExposeController       [ENFORCED|PARTIAL|VIOLATED]
  Session state    → SpatialTransitionEngine      [ENFORCED|PARTIAL|VIOLATED]
  Layout decisions → SpatialTransitionEngine      [ENFORCED|PARTIAL|VIOLATED]

SECTION 2 — VIOLATIONS
[CRITICAL] <file>:<line> — <rule> — <description>
[HIGH]     <file>:<line> — <rule> — <description>
[MEDIUM]   <file>:<line> — <rule> — <description>
[LOW]      <file>:<line> — <rule> — <description>

SECTION 3 — CIRCULAR DEPENDENCIES
  CYCLE: <FileA> → <FileB> → <FileA>
    <FileA>:<line> calls <symbol> in <FileB>
    <FileB>:<line> calls <symbol> in <FileA>

  (none) if no cycles detected

SECTION 4 — RECOMMENDED CANONICAL OWNERS
For each violation or conflict, state only the recommended owner — no fix.
  <conflict description> → canonical owner: <file>

SECTION 5 — PASS / FAIL
  RULE 1 AX mutation authority:      [PASS|FAIL]
  RULE 2 Active window authority:    [PASS|FAIL]
  RULE 3 Session authority:          [PASS|FAIL]
  RULE 4 Decision authority:         [PASS|FAIL]
  RULE 5 No circular dependencies:   [PASS|FAIL]

  OVERALL: [PASS|FAIL]
```

## Constraints
- Do NOT modify any source files.
- Do NOT rename anything.
- Do NOT propose fixes in this report — violations only.
- If a violation is ambiguous (e.g. a read that may or may not duplicate
  LayoutOrchestrator's read), flag it as [MEDIUM] with the ambiguity noted.
- Report only.
