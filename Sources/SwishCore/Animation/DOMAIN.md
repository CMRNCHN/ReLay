# Domain: Animation

**Owner:** `LayoutOrchestrator.swift`

## Responsibility
Low-level AX window manipulation, spring animation, window enumeration, and screen geometry resolution.

## What Belongs Here
- `LayoutOrchestrator`
- Spring animation engine
- AX frame read/write primitives
- Window enumeration (getAllVisibleWindows)
- Stage Manager toggle
- Display coordinate conversion

## What Does NOT Belong Here
- Layout states or semantic positions
- Transition logic or state machine
- Preview overlay rendering

## Boundary Rule
This domain receives CGRect frames and applies them. It never decides which frame to use.
