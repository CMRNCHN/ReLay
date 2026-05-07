# Domain: Configuration

**Purpose:** User-facing behavior tuning and persistent preferences.

## What Belongs Here
- Future: GestureThresholds (user-overridable lockThreshold, actionThreshold, flickVelocity)
- Future: LayoutPreferences (preferred snap grid, center width fraction)
- Future: Persistence layer for preferences (UserDefaults wrapper)

## Design Constraints
- Configuration values must be injected into layers — no layer reads UserDefaults directly
- Defaults must be compile-time constants matching current hardcoded values
- Must not depend on any other SwishCore domain (no circular dependencies)

## Status
Not yet implemented. Directory established for Air indexing.
