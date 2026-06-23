# ReLay Architecture Design Contract (v1)

**Status**: Stable. Structural changes require justification via ADR (Architectural Decision Record).

Architecture should enable evolution, not prevent it. These rules distinguish between hard constraints (immovable) and guidelines (defaults with justification).

---

## Hard Constraints (Cannot Be Overridden)

### 1. Domain Boundary (Inviolate)

There are exactly **3 domains**:

- **Core** → system + runtime primitives
- **InputPipeline** → event ingestion + normalization  
- **Layout** → layout logic + decisioning

Adding a 4th domain requires an ADR explaining why existing domains are insufficient.

### 2. Single Domain Ownership

Every file has **one primary domain**. No duplicates, no "shared" copies.

### 3. No Compatibility Layers

Don't introduce forwarding files or compatibility shims without a documented migration plan.

### 4. No Single-File Subdirectories

A directory exists only if it contains ≥3 related files or represents a true subsystem (Core/Input/Layout).

---

## Guidelines (Defaults with Justification)

### 5. Prefer Responsibility-Based Placement

Files live where their **primary responsibility executes**, not where they're used.

**Rationale**: Makes code location predictable and reduces navigation overhead.

**Override when**: A file logically belongs in multiple domains. Document the reasoning in comments.

### 6. Avoid Abstraction Inflation

Default to simple names. Avoid:
- Manager
- Coordinator
- Engine
- Service (as a default pattern)
- Provider
- Handler layers

**Rationale**: Vague names hide responsibility and accumulate over time.

**Override when**: The name accurately describes the type (e.g., `GestureInterpreter` if it truly interprets gestures).

### 7. Avoid Structural Refactors Without Purpose

Refactors should improve **correctness**, **maintainability**, or **reduce duplication**.

**Rationale**: Prevents churn and keeps architecture stable.

**Override when**: A new feature requires it, or a genuine problem emerges. Document in the commit or ADR.

---

## Architectural Decision Record (ADR) Requirement

**Any structural change beyond minor file edits requires an ADR:**

- Adding a new top-level folder
- Splitting or merging domains
- Moving files between domains
- Introducing new abstraction layers

**ADR format** (keep brief, ~100 words):
1. **Problem**: Why is the current structure insufficient?
2. **Alternatives**: What other approaches were considered?
3. **Decision**: What are we doing and why?
4. **Consequences**: What becomes easier/harder?

File as `docs/adr/NNNN-<title>.md` or add to this document as a section.

---

## Current State (Stable)

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

**Before making any structural change:**

1. **Is it a hard constraint violation?** (domains, ownership, compatibility layers, single-file dirs)
   - If yes → needs ADR or architectural review
2. **Is it a guideline override?** (placement, naming, refactor purpose)
   - If yes → document justification in commit message
3. **Is it a file-level change?** (new file in existing domain, internal refactor)
   - If yes → proceed normally
4. **When in doubt**: Write a brief ADR explaining the problem and why the change is necessary

---

## Success Metric

**Architecture is working when your commit history is dominated by feature work and bug fixes, not directory shuffles and renames.**

If six months from now this file hasn't needed updates, that's a sign the structure is doing its job.

---

**Last updated**: 2026-06-23  
**Status**: Living design contract (not immutable law)  
**Hard constraints**: Cannot be overridden without review  
**Guidelines**: Defaults that can be justified when necessary
