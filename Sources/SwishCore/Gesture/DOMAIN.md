# Domain: Gesture

**Owner:** `GestureEngine.swift`

## Responsibility
Raw gesture physics only: axis locking, velocity measurement, threshold detection, finger count, session lifecycle.

## What Belongs Here
- GestureEngine
- GestureAxis, GestureDirection (value types only)
- Threshold constants
- Delegate protocol (TitleBarInterceptorDelegate or equivalent)

## What Does NOT Belong Here
- Layout states or semantic positions
- Frame or coordinate math
- Workspace topology
- Any import of Accessibility or AppKit for layout purposes

## Boundary Rule
This domain emits only: direction, velocity, fingerCount, progress. It receives nothing back.
