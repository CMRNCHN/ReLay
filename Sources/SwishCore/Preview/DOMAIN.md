# Domain: Preview

**Owner:** `PreviewManager.swift`

## Responsibility
The gesture-tracking visual overlay. Shows the user where a window will land before they commit the gesture.

## What Belongs Here
- `PreviewManager`
- Overlay NSWindow configuration
- Alpha/frame animation for the overlay

## What Does NOT Belong Here
- Layout state logic
- Frame computation
- Any state about which transition is occurring

## Boundary Rule
This domain receives frames and displays them. It never produces frames or makes layout decisions.
