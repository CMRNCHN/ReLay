# Domain: Workspace

**Owner:** `WindowStateStore.swift`

## Responsibility
Per-window semantic state persistence. The source of truth for "what layout state is this window currently in."

## What Belongs Here
- `WindowID` (AXUIElement wrapper with Hashable)
- `WindowRecord` (currentState, history, floatingFrame)
- `WindowStateStore` (the shared registry)
- `WorkspaceTopology` (future: focal/supporting/peripheral roles)

## What Does NOT Belong Here
- Frame math
- Gesture logic
- Animation

## Boundary Rule
This domain owns state. Nothing outside this domain should mutate WindowRecord directly.
