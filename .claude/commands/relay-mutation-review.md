# relay:mutation-review

Classify and gate-check the current git diff before any code changes are applied. Run this before committing architectural changes.

## Steps

1. Run `git diff HEAD` and `git diff --staged`.
2. For each changed file, classify the change type:
   - **behavior**: changes observable output or user-facing behavior
   - **logging**: adds/removes/modifies log calls only
   - **refactor**: restructures code without changing behavior
   - **dead-code-removal**: deletes unreachable symbols
   - **invariant-enforcement**: adds guards, assertions, source tags
   - **test**: test files only
3. For each behavior or refactor change, check:
   - Does it introduce a new AX write outside `LayoutOrchestrator`?
   - Does it add a new caller of `animateWindowFrame` or `setWindowFrame`?
   - Does it move session state (`sessionWindow`, `sessionScreenFrame`, etc.) out of `SpatialTransitionEngine`?
   - Does it add a second write site for `isActive`?
   - Does it bypass the gesture pipeline (calls `LayoutOrchestrator` directly without going through `SpatialTransitionEngine`)?
4. Flag any violation as [BLOCK] — changes that violate architectural invariants.
5. Flag risks as [WARN] — changes that are suspicious but not definitively wrong.
6. Approve as [OK] — changes that are safe.

## Output format

```
MUTATION REVIEW
───────────────
<file> — <change type> — [OK|WARN|BLOCK]
  Reason: <one line>

ARCHITECTURAL VIOLATIONS (must fix before commit)
──────────────────────────────────────────────────
[BLOCK] <description>

WARNINGS (review before commit)
────────────────────────────────
[WARN] <description>

VERDICT: [APPROVED|BLOCKED]
```

## Constraints
- Do NOT fix anything automatically.
- Do NOT commit anything.
- If verdict is BLOCKED, list exactly what must change before approval.
- Report only.
