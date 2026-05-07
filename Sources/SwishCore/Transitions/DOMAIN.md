# Domain: Transitions

**Owner:** `SpatialTransitionEngine.swift`

## Responsibility
Semantic orchestration. Routes committed gestures through the state machine, coordinates preview updates, and dispatches multi-window operations.

## What Belongs Here
- `SpatialTransitionEngine`
- Multi-window operation logic (three-column, stage manager, exit-layout)
- Session lifecycle management

## What Does NOT Belong Here
- Gesture physics (that's Gesture)
- Frame math (that's Relayout)
- AX frame writes (that's Animation)
- UI/overlay rendering (that's Preview)

## Boundary Rule
This domain is the conductor — it calls into Relayout, Workspace, Animation, and Preview. It must not contain physics or AX primitives.
