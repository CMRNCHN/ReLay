# relay:trace-pipeline

Trace the full execution path from a given entry symbol to `AXUIElementSetAttributeValue`. Do not modify any files.

## Usage
```
/relay:trace-pipeline <symbol>
```

Example: `/relay:trace-pipeline gestureDidBegin`

## Steps

1. Locate the definition of `$ARGUMENTS` in `Sources/ReLayCore/*.swift`.
2. Find all direct call sites of that symbol.
3. For each call site, recursively follow: delegate calls, direct method calls, protocol dispatches.
4. Continue until reaching `AXUIElementSetAttributeValue` or a dead end.
5. Also identify any **branches** where the chain splits (e.g. expose path vs gesture path).
6. Note any steps where the gestureID is passed, dropped, or not forwarded.

## Output format

```
PIPELINE TRACE: <symbol>
────────────────────────
PATH 1 (gesture path):
  <File>:<line> <symbol>
    → <File>:<line> <next symbol>
      → <File>:<line> <next symbol>
        → AXUIElementSetAttributeValue [TERMINAL]

PATH 2 (expose path, if exists):
  <File>:<line> <symbol>
    → ...

GESTUREIDS:
  Minted at: <file>:<line>
  Forwarded through: <list of call sites>
  Dropped at: <file>:<line> (if applicable)

DEAD ENDS:
  <symbol> at <file>:<line> — no further calls found

BRANCHES:
  <description of where the pipeline forks and why>
```

## Constraints
- Do NOT fix anything.
- Do NOT rename anything.
- Report only.
