# PRODUCT_PRINCIPLES.md

## Core Identity

ReLay is a semantic workspace relayout engine.

It is not a snapping utility.
It is not a window positioning tool.
It is not a keyboard shortcut manager.
It is not an automation framework.

---

## Fundamental Question

Traditional window managers ask:
"Where should this window go?"

ReLay asks:
"What should this workspace become?"

Protect this distinction in architecture and behavior.

---

## Principles

### 1. Semantic Over Geometric

Layout states carry meaning. `leftThird` is not a coordinate recipe; it is a semantic contract.

### 2. Workspace-Centric Direction

Today the product is window-centric.
The target product direction is workspace-centric.

### 3. Deterministic Transitions

Every `(state x gesture direction)` resolves to exactly one next state. If no entry exists, the gesture snaps back.

### 4. Spatial Intelligence Without Complexity

The system should feel intelligent because its model is coherent, not because the code is overabstracted.

### 5. Native macOS Behavior

ReLay should extend platform conventions rather than replace them.

### 6. Reversibility

Every transition must be undoable. History and floating-frame capture are invariants.

### 7. Gesture As Intent Signal

The gesture expresses intent. The transition engine interprets that intent against current semantic context.
