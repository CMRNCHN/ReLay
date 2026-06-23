# ReLay Architecture Freeze Rules (v1)

**Status**: FROZEN. Structural changes require explicit justification.

---

## 1. Domain Integrity (Hard Rule)

There are exactly **3 domains only**:

- **Core** → system + runtime primitives
- **InputPipeline** → event ingestion + normalization  
- **Layout** → layout logic + decisioning

### ❌ Forbidden:
- Adding new top-level folders under `ReLayCore/`
- Creating "cross-cutting" domains (e.g., Shared, Common, Services)

---

## 2. File Placement Rule (Strict)

A file must live where its **primary responsibility executes**, not where it is used.

### Examples:
- Window state logic → Core
- Event capture → InputPipeline
- Layout decisions → Layout

### ❌ Forbidden:
- Duplicating files across domains
- "Helper" folders inside domains unless they contain ≥3 files

---

## 3. Naming Rule (Minimal Constraint)

- Names must describe **what it is**, not architecture role
- No structural prefixes (no `System_`, `Runtime_`, `Policy_`)

### ❌ Forbidden:
- Encoding architecture in filenames
- Renaming unless responsibility changes

---

## 4. No Abstraction Inflation

### ❌ Do not introduce:
- Manager
- Coordinator
- Engine
- Service (as a default pattern)
- Provider
- Handler layers unless strictly necessary

**If a file does multiple roles** → split by responsibility, not abstraction naming.

---

## 5. Directory Rule (Anti-Over-Nesting)

A directory is valid only if:

- It contains ≥3 related files, **OR**
- It represents a true subsystem boundary (Core/Input/Layout only)

### ❌ Forbidden:
- Single-file folders
- Deep nesting beyond 2 levels inside domains

---

## 6. Refactor Rule (Hard Gate)

Refactoring is allowed **only** if it:

- Reduces duplication, **OR**
- Fixes incorrect responsibility placement

### ❌ Not allowed:
- "Clarity refactors" that only rename or reshuffle
- Structural optimization without functional change

---

## 7. Stability Rule (Critical)

**Once committed: No structural changes unless a new domain emerges.**

A "new domain" means:

- It has independent lifecycle
- It contains ≥3 stable files
- It is not derivable from existing domains

---

## Enforcement Mindset

**Structure must become harder to change over time, not easier to rearrange.**

---

## Current State (Frozen)

```
ReLayCore/
├── Core/ (9 files)
│   ├── Logger.swift
│   ├── AccessibilityBootstrap.swift
│   ├── AXWindowOps.swift
│   ├── WindowRuntime.swift
│   ├── WindowMutabilityPolicy.swift
│   ├── SystemReducer.swift
│   ├── ReLaySettings.swift
│   ├── Imports.swift
│   └── PersistenceModels.swift
│
├── InputPipeline/ (1 file)
│   └── EventTapCapture.swift
│
└── Layout/ (5 files)
    ├── LayoutLibrary.swift
    ├── LayoutTemplate.swift
    ├── LayoutHistoryStore.swift
    ├── LayoutSuggestionEngine.swift
    └── AppLibraryStore.swift
```

✅ This structure complies with all rules above.

---

## What These Rules Prevent

- Endless architecture cycling
- Over-optimization of file layout
- Premature abstraction layers
- "Cleanup-driven rewrites"
- Naming wars inside Core

---

## Decision Gate for Future Changes

**Before making any structural change, ask:**

1. Does this violate rule 1-7?
2. If yes → reject the change
3. If no → does it add a new domain?
4. If yes → justify why it's independent and necessary
5. If no → proceed as a file-level change (allowed)

---

**Last updated**: 2026-06-23  
**Frozen by**: Architecture review  
**Next review**: Only if a new domain becomes necessary
