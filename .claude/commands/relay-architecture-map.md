# relay:architecture-map

Generate a full topology map of the ReLay system. Do not modify any files. Report only.

## Steps

1. Read every file in `Sources/ReLayCore/*.swift`.
2. For each file, identify:
   - Layer (input / decision / execution / state / UI)
   - Owned state (instance vars)
   - Outbound dependencies (types it imports or holds references to)
   - Entry points (public/internal methods called from outside the file)
   - AX access (read-only enumeration vs write)
3. Build the layer graph: which layer calls which.
4. Identify cross-layer violations: a lower layer calling up into a higher layer.
5. List all ownership boundaries: which file owns each piece of shared state.
6. Identify responsibilities shared by more than one file.

## Layer definitions
- **input**: receives raw system events (NSEvent, AX notifications)
- **decision**: interprets intent, selects layout, resolves state transitions
- **execution**: writes AX attributes, moves windows
- **state**: persists or caches derived state across gestures
- **ui**: renders overlay windows, previews, editors

## Output format

```
ARCHITECTURE MAP
────────────────

LAYER ASSIGNMENTS
  input:     <files>
  decision:  <files>
  execution: <files>
  state:     <files>
  ui:        <files>
  mixed:     <files with reason>

DEPENDENCY GRAPH
  <FileA> → <FileB> [reason]
  ...

CROSS-LAYER VIOLATIONS
  [CRITICAL] <file> (<layer>) → <file> (<layer>) — <description>
  [HIGH]     ...

SHARED RESPONSIBILITIES
  <responsibility> — owned by <file1>, also present in <file2>

EXECUTION PATHS (summary)
  Gesture path:  <A → B → C → D>
  Expose path:   <A → B → C → D>

TOP 5 SYSTEM RISKS
  1. ...
  2. ...
  3. ...
  4. ...
  5. ...
```

## Constraints
- Do NOT fix anything.
- Do NOT rename anything.
- Do NOT create new abstraction layers.
- Report only.
