# relay:audit-dead-code

Scan `Sources/ReLayCore` for dead code. Do not modify any files. Report only.

## Steps

1. Find all `func`, `var`, `let`, `class`, `struct`, `enum`, `protocol` definitions in `Sources/ReLayCore/*.swift`.
2. For each symbol, grep the entire `Sources/` tree for references **outside** the defining file.
3. A symbol is dead if it has zero external references AND is not `@objc`, `public`, `open`, or part of a protocol conformance.
4. Additionally flag: variables that are assigned but never read (written-only state).
5. Flag duplicate implementations: two functions that enumerate AX windows, two that compute screen frames, etc.

## Output format

```
DEAD CODE REPORT
────────────────
[CRITICAL] <file>:<line> — <symbol> — <reason>
[HIGH]     <file>:<line> — <symbol> — <reason>
[MEDIUM]   <file>:<line> — <symbol> — <reason>
[LOW]      <file>:<line> — <symbol> — <reason>

DUPLICATE IMPLEMENTATIONS
─────────────────────────
<description> — found in <file1> and <file2>

WRITTEN-ONLY STATE
──────────────────
<file>:<line> — <var> — assigned at lines X,Y — never read
```

## Constraints
- Do NOT fix anything.
- Do NOT rename anything.
- Do NOT open PRs.
- Report only.
