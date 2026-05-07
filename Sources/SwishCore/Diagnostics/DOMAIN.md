# Domain: Diagnostics

**Purpose:** Structured event logging for gesture, transition, and layout events.

## What Belongs Here
- Future: DiagnosticsLogger (writes to storage/diagnostics/)
- Future: GestureEventLog, TransitionEventLog value types
- Future: LayoutSnapshotRecorder

## Design Constraints
- Must be opt-in (no logging in production paths by default)
- Must write to `storage/diagnostics/` only
- Must never block the main thread
- Must not import gesture or layout logic — receives structured log events via protocol

## Status
Not yet implemented. Directory established for Air indexing.
