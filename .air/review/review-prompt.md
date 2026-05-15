## ReLay Review Tasks

This review is for ReLay — a deterministic macOS spatial workspace choreography engine currently in architecture stabilization/runtime bootstrap phase.

The project is NOT a generic window manager and NOT a snapping utility.

Core architectural direction:

GestureEngine
→ SpatialTransitionEngine
→ LayoutResolver
→ LayoutOrchestrator
→ WindowStateStore

Primary architectural constraint:
preserve low abstraction depth and deterministic runtime behavior.

==================================================
YOUR REVIEW TASKS

1. Architecture Safety
Assess whether changes preserve:

* shallow call depth
* explicit ownership boundaries
* deterministic transitions
* semantic transition model
* workspace topology identity
* debuggability
* inspectability

Flag:
* abstraction creep
* hidden coupling
* speculative systems
* unnecessary indirection
* architecture inflation

==================================================
2. Runtime Correctness
Verify implementation correctness for:

* gesture handling
* AXUIElement usage
* Accessibility API interaction
* frame calculation
* transition sequencing
* workspace state persistence
* relayout behavior
* preview coordination
* fullscreen handling
* window restoration

Identify:
* race conditions
* inconsistent state transitions
* stale workspace state
* invalid frame application
* transition ordering problems

==================================================
3. Semantic Transition Integrity
Verify the system continues moving toward:

gesture
→ semantic intent
→ spatial transition
→ topology resolution
→ orchestration

NOT:
gesture
→ direct snap action

Identify all remaining:

* edge-oriented assumptions
* direct gesture→action coupling
* snapLeft/snapRight style logic
* geometry-first behavior
* topology-blind transitions

==================================================
4. Determinism & Runtime Stability
Assess whether changes preserve:

* deterministic workspace evolution
* bounded runtime behavior
* predictable transitions
* explicit state ownership
* stable relayout behavior
* reproducible gesture outcomes

Flag:
* hidden side effects
* implicit runtime mutation
* non-deterministic layout selection
* unstable state mutation
* transition ambiguity

==================================================
5. macOS Runtime Safety
Review:

* AppKit usage
* Accessibility API correctness
* AX observer lifecycle
* coordinate-space correctness
* window ownership assumptions
* fullscreen behavior
* multi-monitor assumptions
* titlebar interception safety

Flag:
* invalid AX assumptions
* permission-flow issues
* unsafe UI-thread behavior
* AppKit threading violations
* unsafe polling behavior

==================================================
6. Workspace Choreography Quality
Assess whether implementation supports the intended product identity:

ReLay should feel like:
“the workspace reorganizes itself around intent.”

NOT:
“windows snap to edges.”

Evaluate:
* adjacency preservation
* prominence balancing
* relayout continuity
* workspace coherence
* spatial memory consistency
* transition fluidity

==================================================
7. Tests
Recommend tests for:

* transition graph correctness
* relayout determinism
* state restoration
* fullscreen transitions
* gesture routing
* topology evolution
* multi-window scenarios
* workspace persistence
* Accessibility failure handling
* coordinate-space edge cases

Prefer:
* deterministic tests
* topology/state validation
* transition correctness tests

Avoid:
* over-mocked architecture
* giant integration abstractions

==================================================
8. Documentation & Governance
Verify changes remain aligned with:

* .ai/AIR_RULES.md
* .ai/ARCHITECTURE_RULES.md
* .ai/PRODUCT_PRINCIPLES.md
* semantic domain boundaries
* runtime stabilization phase

Flag:
* stale governance state
* terminology drift
* inconsistent architectural language
* ownership ambiguity

Canonical terminology should remain consistent:

* focal window
* adjacent windows
* workspace topology
* transition
* relayout
* transient state
* workspace snapshot

==================================================
9. MOST IMPORTANT REVIEW PRINCIPLE

Protect:

LOW ABSTRACTION DEPTH
+
DETERMINISTIC SPATIAL BEHAVIOR

Do NOT recommend:
* framework migrations
* generalized engines
* reactive rewrites
* speculative abstractions
* architecture redesigns

Prefer:
* bounded improvements
* explicit state machines
* concrete runtime behavior
* incremental evolution
* small deterministic refactors