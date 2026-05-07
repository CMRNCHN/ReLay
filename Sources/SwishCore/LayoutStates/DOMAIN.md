# Domain: LayoutStates

**Owner:** `WindowLayoutState.swift`

## Responsibility
The complete declarative definition of semantic layout positions and the transition rules between them.

## What Belongs Here
- `WindowLayoutState` enum (all semantic positions)
- `GestureDirection` enum
- `LayoutTransitionGraph` (declarative transition table)
- `TransitionKey` struct

## What Does NOT Belong Here
- Frame math (that's Relayout)
- State persistence (that's Workspace)
- AX or AppKit imports

## Boundary Rule
Pure Swift value types and classes only. Must compile without Cocoa or Accessibility imports.
