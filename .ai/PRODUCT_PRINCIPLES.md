# Product Principles

## Core Identity

**Re-Lay is a semantic workspace relayout engine.**

It is not a snapping utility.
It is not a window positioning tool.
It is not a keyboard shortcut manager.
It is not an automation framework.

---

## The Fundamental Question

Traditional window managers ask:
> "Where should this window go?"

Re-Lay asks:
> "What should this workspace become?"

Protect this distinction in every architecture decision.

---

## Principles

### 1. Semantic Over Geometric

Layout states carry meaning. `leftThird` is not "x=0, width=W/3" — it is a semantic position that persists across screen sizes, display configurations, and resolution changes. The name is the contract. The frame is the implementation.

### 2. Workspace-Centric (Direction of Travel)

Today: window-centric. One gesture, one window.
Tomorrow: workspace-centric. One gesture, a coherent workspace reorganization.

The focal window, supporting windows, and peripheral windows have distinct roles. A gesture on the focal window should be able to promote, demote, or reorganize the entire workspace. This is the core product bet.

### 3. Deterministic Transitions

Every (state × gesture direction) pair resolves to exactly one next state. No probabilistic routing. No inferred intent. No hidden heuristics. The transition graph is visible, auditable, and testable. If the transition table does not have an entry, the gesture snaps back — never guesses.

### 4. Spatial Intelligence Without Complexity

Re-Lay should feel intelligent because the spatial model is coherent — not because the codebase is overabstracted. A new contributor should be able to read any single file and understand its entire responsibility. Low conceptual complexity is a design goal, not a compromise.

### 5. Native macOS Behavior

Re-Lay extends macOS spatial conventions. It does not fight them. Stage Manager, Mission Control, Spaces, and tiling are allies. The system should feel like a premium extension of the platform — not a replacement for it.

### 6. Reversibility

Every transition must be undoable. State history exists for this reason. Floating frame capture before first managed placement is a hard invariant, not an optimization.

### 7. Gesture as Intent Signal

A gesture is an expression of intent — not a direct instruction. `swipe left` means "move this workspace toward a left-oriented configuration." The transition engine interprets the intent given current context. The gesture layer is ignorant of what that means.

---

## Anti-Patterns to Reject at Architecture Review

| Anti-Pattern | Why It's Wrong |
|---|---|
| Turning Re-Lay into a general automation tool | Dilutes the spatial identity |
| "Smart" geometry inference replacing semantic states | Non-deterministic, untestable |
| Workspace topology as an opaque AI/ML system | Unpredictable behavior, violates principle 3 |
| Adding plugin systems or hook registries | Complexity explosion without clear benefit |
| Web or cross-platform layers | Against native macOS identity |
| Gestures that directly compute frames | Violates layer separation; makes testing impossible |
| Per-window feature flags or A/B behavior | Every window must behave identically |

---

## Success Looks Like

A user picks up a cluttered desktop, makes three deliberate two-finger swipes, and their workspace is coherently reorganized — focal window prominent, supporting windows in place, peripherals tucked — without the user thinking about coordinates once.
