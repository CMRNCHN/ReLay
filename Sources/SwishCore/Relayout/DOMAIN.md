# Domain: Relayout

**Owner:** `LayoutResolver.swift`

## Responsibility
Pure geometric mapping. Converts semantic layout states into concrete CGRect frames for a given screen.

## What Belongs Here
- `LayoutResolver` (state → frame, frame → state inference, interpolation)
- `CGRect` extensions used for layout math
- Future: multi-display frame resolution

## What Does NOT Belong Here
- AX frame writes (that's Animation)
- State persistence (that's Workspace)
- Any mutable state or side effects

## Boundary Rule
Every function in this domain must be a pure function. No imports of Accessibility or Cocoa. CGRect and CoreGraphics only.
