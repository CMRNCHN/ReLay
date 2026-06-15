# ReLay Architecture: Visual Guide

## Module Organization Overview

```
                           ReLay Executable
                           (Sources/ReLay/)
                                  │
                                  ▼
                           ┌──────────────┐
                           │  ReLayCore   │
                           │   Target     │
                           │  (single)    │
                           └──────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
                    ▼                           ▼
          ┌──────────────────┐        ┌──────────────────┐
          │ Modules/         │        │ Tests/           │
          │ Foundation/      │        │ ReLayCoreTests/  │
          │ Input/           │        │                  │
          │ Gesture/         │        │ (mirrors source  │
          │ StateManagement/ │        │  structure)      │
          │ Layout/          │        │                  │
          │ SpatialEngine/   │        └──────────────────┘
          │ SpatialMemory/   │
          │ SpatialState/    │
          │ WindowEngine/    │
          │ UI/              │
          └──────────────────┘
```

---

## Dependency Hierarchy (Bottom to Top)

```
                    ╔════════════════════════════════╗
                    ║   LAYER 3: User-Facing UI      ║
                    ║   (LayoutLibrary, Workspace)   ║
                    ╚════════════════════════════════╝
                              ▲
                              │
                    ╔════════════════════════════════╗
                    ║   LAYER 2: Layout Engine        ║
                    ║   (Semantic state machine,      ║
                    ║    animation orchestration)     ║
                    ╚════════════════════════════════╝
                              ▲
              ┌───────────────┼───────────────┐
              │               │               │
      ╔═══════════════╗ ╔═══════════════╗ ╔════════════════╗
      ║ LAYER 1a:     ║ ║ LAYER 1b:     ║ ║ LAYER 1c:      ║
      ║ Input Module  ║ ║ Spatial Calc  ║ ║ State/Memory   ║
      ║ (Gesture)     ║ ║ (Geometry)    ║ ║ (Persistence) ║
      ╚═══════════════╝ ╚═══════════════╝ ╚════════════════╝
              ▲               ▲               ▲
              └───────┬───────┴───────┬───────┘
                      │               │
            ╔═════════════════════════════════╗
            ║  LAYER 0: Foundation (Core      ║
            ║  utilities, logging, settings,  ║
            ║  accessibility, models)         ║
            ╚═════════════════════════════════╝
                      ▲
                      │
         System Frameworks (Cocoa, AppKit,
         ApplicationServices, Accessibility,
         CoreGraphics, Foundation)
```

---

## Module Dependency Matrix

```
                    F  I  G  SM  S  SE  SPM  SP  WE  U
Foundation (F)      ●  —  —   —  —  —   —    —  —   —
Input (I)           ✓  ●  —   —  —  —   —    —  —   —
Gesture (G)         ✓  ✓  ●   —  —  —   —    —  —   —
StateManagement(SM) ✓  —  —   ●  —  —   —    —  —   —
Layout (L)          ✓  —  ✓   ✓  —  —   —    —  —   —
SpatialEngine(SE)   ✓  —  —   —  —  ●   —    —  —   —
SpatialMemory(SPM)  ✓  —  —   ✓  —  ✓   ●    —  —   —
SpatialState(SP)    ✓  —  —   —  —  ✓   —    ●  ✓   —
WindowEngine(WE)    ✓  —  —   —  —  —   —    ✓  ●   —
UI (U)              ✓  —  —   ✓  ✓  —   ✓    —  —   ●

Legend:
● = Self (same module)
✓ = Imports/depends on
— = No dependency
```

---

## Data Flow During Gesture

### Timeline: From Gesture Start to Layout Applied

```
┌─────────────────────────────────────────────────────────────────┐
│ USER ACTION: Click title bar and drag                           │
└────────────┬────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│ 1. Input Capture (Input Module)                                 │
│    ├─ EventTapCapture → raw CGEvent                             │
│    ├─ EventNormalizer → NormalizedEvent (swipe/pinch/scroll)    │
│    ├─ InputGestureEngine → InputGesture enum                    │
│    ├─ GestureRouter → determines routing                        │
│    └─ ActionDispatcher → sends to SpatialTransitionEngine       │
└────────────┬────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Gesture Semantics (Gesture + Layout Modules)                 │
│    ├─ TitleBarInterceptor → hit detection on title bar          │
│    ├─ GestureEngine → accumulates deltas, locks axis            │
│    ├─ SpatialTransitionEngine → state machine                   │
│    │  ├─ beginSession(window, fingerCount, location)            │
│    │  ├─ updatePreview(deltaX, deltaY, velocity)                │
│    │  └─ Determines candidate layout states                     │
│    └─ LayoutTransitionGraph → queries valid state transitions   │
└────────────┬────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Layout Resolution (Layout + SpatialEngine)                   │
│    ├─ LayoutResolver → maps state enum to CGRect frame          │
│    ├─ SpatialEngine → resolves multi-window layout              │
│    ├─ CollisionResolver → prevents window overlaps              │
│    └─ LayoutStabilizer → prevents flutter/jitter               │
└────────────┬────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. Preview Visualization (StateManagement Module)               │
│    ├─ PreviewManager → creates overlay windows                  │
│    ├─ Shows interpolated frame during drag                      │
│    └─ Updates in real-time as gesture changes                   │
└────────────┬────────────────────────────────────────────────────┘
             │
             ▼ (Gesture released)
┌─────────────────────────────────────────────────────────────────┐
│ 5. Commit & Apply (Layout Module)                               │
│    ├─ SpatialTransitionEngine → commitSession()                 │
│    ├─ LayoutOrchestrator → animateWindowFrame()                 │
│    │  ├─ Uses AXUIElementSetAttributeValue() for frame writes   │
│    │  └─ Coordinate transformation for position/size            │
│    ├─ WindowStateStore → updates semantic state                 │
│    └─ LayoutHistoryStore → records layout in history            │
└────────────┬────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. State Reconciliation (SpatialState Module)                   │
│    ├─ SystemStateReader → polls actual window frames            │
│    ├─ DriftDetector → checks for discrepancies                  │
│    ├─ ReconciliationEngine → corrects drift                     │
│    └─ SpatialStateCore → continuously monitors & corrects       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Module Public APIs

### Foundation Module
```
📦 Modules/Foundation/
├── Core/
│   ├── AppLogger.log(message, subsystem, sessionID)
│   ├── CrashLogger.setup()
│   ├── ReLaySettings.{property} → UserDefaults
│   └── Imports.swift → re-exports system frameworks
├── Accessibility/
│   ├── AccessibilityBootstrap.isGranted() → Bool
│   ├── AccessibilityBootstrap.registerSilently()
│   └── WindowRoleClassifier.inferRole(element) → WindowRole
├── Models/
│   ├── WindowLayoutState enum (fullscreen, leftHalf, center, etc.)
│   └── PersistenceModels (Codable types for storage)
└── UI/
    └── UIComponentLibrary (reusable UI components)
```

### Input Module
```
📦 Modules/Input/
├── Capture/
│   └── EventTapCapture(delegate)
├── Core/
│   ├── RawInputEvent struct
│   ├── NormalizedEvent enum (swipe, pinch, scroll)
│   ├── InputGesture enum
│   └── InputProtocols (delegates)
├── Normalize/
│   └── EventNormalizer → normalizes raw events
├── Engine/
│   └── InputGestureEngine → state machine for gestures
├── Routing/
│   └── GestureRouter → routes to action dispatcher
└── Pipeline/
    └── InputPipeline.shared.start()/stop()
```

### Gesture Module
```
📦 Modules/Gesture/
├── TitleBarInterceptor (main interceptor)
│   ├── start() → begins monitoring title bars
│   ├── stop() → stops monitoring
│   └── delegate property → receives gesture events
└── GestureEngine (delegate implementation)
    ├── Tracks accumulated deltas
    ├── Locks to primary axis (H/V)
    └── Delegates to SpatialTransitionEngine
```

### StateManagement Module
```
📦 Modules/StateManagement/
├── WindowStateStore.shared
│   ├── record(for: AXUIElement) → WindowRecord?
│   ├── updateState(_ state: WindowLayoutState, for window)
│   └── currentState(for window) → WindowLayoutState?
├── LayoutHistoryStore.shared
│   ├── getRecentTemplateIDs() → [String]
│   └── recordApply(event: AppliedLayoutEvent)
├── AppLibraryStore.shared
│   ├── getAppRole(bundleID) → WindowRole
│   └── cacheAppMetadata(bundleID, role, icon)
└── PreviewManager.shared
    ├── updateOverlay(currentFrame, targetFrame, progress)
    ├── commitOverlay(finalFrame)
    └── dismiss(animated)
```

### Layout Module
```
📦 Modules/Layout/
├── Application/
│   ├── SpatialTransitionEngine.shared
│   │   ├── beginSession(window, fingerCount, location, gestureID)
│   │   ├── updatePreview(deltaX, deltaY, velocity)
│   │   ├── commitSession()
│   │   └── cancelSession()
│   └── LayoutOrchestrator.shared (LOW-LEVEL)
│       ├── animateWindowFrame(window, to: frame)
│       ├── tileWindows([windows], in: screen)
│       └── getAllVisibleWindows() → [AXUIElement]
├── Resolver/
│   └── LayoutResolver.shared
│       ├── frame(for state, on screen) → CGRect
│       ├── inferState(from frame) → WindowLayoutState
│       └── interpolate(from, to, progress) → CGRect
└── Templates/
    ├── LayoutTemplate.all → [LayoutTemplate]
    │   ├── .id → String
    │   ├── .slots → [Slot]
    │   └── .scoringHints → [ScoringHint]
    └── LayoutSuggestionEngine.rank(context) → [RankedTemplate]
```

### SpatialEngine Module
```
📦 Modules/SpatialEngine/
├── Engine/
│   └── SpatialEngine → geometric calculations
├── Core/
│   ├── SpatialPoint → x, y coordinates
│   ├── SpatialFrame → origin, width, height
│   └── DisplaySpaceMap → resolution awareness
├── Layout/
│   ├── LayoutEngine → multi-window layout algorithm
│   ├── CollisionResolver → prevents overlaps
│   └── LayoutStabilizer → prevents jitter
└── Resolution/
    ├── CoordinateResolver → coordinate transformation
    ├── DisplayNormalizer → multi-display handling
    └── SpaceResolver → screen space to display space
```

### SpatialMemory Module
```
📦 Modules/SpatialMemory/
├── Engine/
│   └── SpatialMemoryEngine → learns patterns
├── Core/
│   ├── MemoryModel → in-memory storage
│   ├── LayoutPattern → abstract layout patterns
│   └── UsageEvent → layout usage log
├── Learning/
│   ├── FrequencyModel → usage frequency tracking
│   ├── PatternExtractor → identifies patterns
│   └── TransitionGraph → state transition analysis
└── Prediction/
    ├── LayoutPredictor → predicts next layout
    ├── ConfidenceScorer → confidence in predictions
    └── WindowPlacementEngine → smart window placement
```

### SpatialState Module
```
📦 Modules/SpatialState/
├── Engine/
│   └── SpatialStateCore.shared
│       ├── startReconciliation()
│       └── stopReconciliation()
├── Core/
│   ├── SpatialState → complete state snapshot
│   ├── SpatialStateSnapshot → frozen state
│   └── StateVersion → versioning for consistency
├── Store/
│   └── SpatialStateStore → persistent state storage
├── Sync/
│   ├── SystemStateReader → reads actual system state
│   ├── DriftDetector → detects state divergence
│   └── ReconciliationEngine → corrects discrepancies
└── Reconciler/
    └── SpatialStateReconciler → reconciliation logic
```

### WindowEngine Module
```
📦 Modules/WindowEngine/
├── Engine/
│   └── WindowEngine.shared
│       ├── getAllVisibleWindows() → [AXUIElement]
│       ├── getFrontmostWindow() → AXUIElement?
│       └── queryWindowProperties(element) → WindowModel
├── Capture/
│   ├── WindowSnapshotter → snapshot single window
│   └── WorkspaceSnapshotter → snapshot all windows
├── Control/
│   ├── WindowMover → moves window to position
│   ├── WindowResizer → resizes window
│   └── FocusController → brings window to focus
├── Core/
│   ├── WindowModel → window properties (position, size, title)
│   ├── DisplayModel → display properties
│   └── WorkspaceModel → workspace layout
└── Persistence/
    └── WorkspaceStore → saves/loads workspace layouts
```

### UI Module
```
📦 Modules/UI/
├── LibraryPanel/
│   ├── LayoutLibraryController.shared
│   │   ├── present(triggerWindow)
│   │   ├── dismiss()
│   │   ├── quickApply(templateID, triggerWindow)
│   │   └── recentMenuItems() → [(id, name)]
│   └── LayoutLibraryPanel UI components
└── Workspace/
    └── LayoutWorkspaceEditor (edit custom layouts)
```

---

## Adding a New Feature: Example Flow

### Scenario: Add a "Snap to Quarter" Layout

```
1. Define new state in Foundation module:
   ┌─────────────────────────────────────┐
   │ Modules/Foundation/Models/          │
   │ WindowLayoutState.swift             │
   │                                     │
   │ enum WindowLayoutState {            │
   │   case leftQuarter      // NEW      │
   │   case rightQuarter     // NEW      │
   │   ...                               │
   │ }                                   │
   └─────────────────────────────────────┘

2. Add template to Layout module:
   ┌─────────────────────────────────────┐
   │ Modules/Layout/Templates/           │
   │ LayoutTemplate.swift                │
   │                                     │
   │ static let all = [                  │
   │   LayoutTemplate(...),              │
   │   LayoutTemplate(                   │
   │     id: "quarters",                 │
   │     slots: [                         │
   │       leftQuarter, rightQuarter, ... │
   │     ]                                │
   │   ) // NEW                           │
   │ ]                                   │
   └─────────────────────────────────────┘

3. Add frame resolution:
   ┌─────────────────────────────────────┐
   │ Modules/Layout/Resolver/            │
   │ LayoutResolver.swift                │
   │                                     │
   │ func frame(for state, on screen) {  │
   │   case .leftQuarter:                │
   │     return CGRect(x, y,             │
   │       width: W/4, height: H)        │
   │ }                                   │
   └─────────────────────────────────────┘

4. Add to suggestion engine:
   ┌──────────────────────────────────────┐
   │ Modules/Layout/Templates/            │
   │ LayoutSuggestionEngine.swift         │
   │                                      │
   │ static func rank(context) {          │
   │   // Add scoring for quarter layouts │
   │ }                                    │
   └──────────────────────────────────────┘

5. LayoutOrchestrator applies without changes:
   ┌──────────────────────────────────────┐
   │ Modules/Layout/Application/          │
   │ LayoutOrchestrator.swift             │
   │                                      │
   │ func animateWindowFrame(...) { }     │
   │ // Works for ANY CGRect              │
   │ // No quarter-specific logic needed  │
   └──────────────────────────────────────┘

6. Feature complete! Gesture flow:
   Gesture → Layout State → Frame → Animation
     (unchanged path, new state added)
```

---

## Circular Dependency Prevention

### Rule: All imports flow DOWNWARD

```
UI
 │ imports Layout, StateManagement, SpatialMemory
 ▼
Layout ◄────── Can NEVER import UI (would be circular)
 │ imports SpatialEngine, SpatialState, StateManagement, WindowEngine
 ▼
SpatialState, SpatialEngine, StateManagement, WindowEngine
 │ imports Foundation only
 ▼
Foundation (LEAF - imports nothing from Modules/)
```

**Enforcement:**
```bash
# Verify no circular imports exist
grep -r "import.*Layout" Sources/ReLayCore/Modules/Foundation/
grep -r "import.*UI" Sources/ReLayCore/Modules/Layout/
# Both should return NOTHING
```

---

## Build System Organization

```
Package.swift
├── products:
│   ├── executable "ReLay"
│   └── executable "ReLayMVP"
│
└── targets:
    ├── "ReLay" (depends: ReLayCore)
    │   └── Sources/ReLay/main.swift
    │       └── imports: GestureEngine, SpatialTransitionEngine, etc.
    │           (all from ReLayCore, no sub-target awareness)
    │
    ├── "ReLayCore" (single target for ALL modules)
    │   └── Sources/ReLayCore/
    │       ├── Modules/Foundation/
    │       ├── Modules/Input/
    │       ├── Modules/Gesture/
    │       ├── Modules/StateManagement/
    │       ├── Modules/Layout/
    │       ├── Modules/SpatialEngine/
    │       ├── Modules/SpatialMemory/
    │       ├── Modules/SpatialState/
    │       ├── Modules/WindowEngine/
    │       └── Modules/UI/
    │           (all compiled together, cross-module imports work)
    │
    ├── "ReLayV2"
    │   └── Sources/ReLayV2/
    │
    ├── "ReLayMVP" (depends: ReLayV2)
    │   └── Sources/ReLayMVP/
    │
    └── "ReLayCoreTests" (depends: ReLayCore)
        └── Tests/ReLayCoreTests/
            ├── GestureCapture/
            ├── Layout/
            ├── SpatialEngine/
            └── ... (mirrors source module structure)
```

**Key Point:** Package.swift does NOT define sub-targets for each module. The modularization is **structural only** (folder organization), not **package system** modularization. This maintains simplicity while establishing clear ownership.

---

## Testing Strategy by Module

```
Modules/Foundation/         → Unit tests (no mocks)
  ├─ AppLogger              → Verify logging output
  ├─ ReLaySettings          → Verify UserDefaults access
  └─ WindowRoleClassifier   → Verify role inference rules

Modules/Input/              → Unit tests (mock EventTap)
  ├─ EventNormalizer        → Test event normalization
  ├─ InputGestureEngine     → Test state machine
  └─ GestureRouter          → Test routing logic

Modules/Gesture/            → Integration tests
  ├─ TitleBarInterceptor    → Test title bar detection
  └─ GestureEngine          → Test gesture accumulation + state

Modules/Layout/             → Unit + Integration tests
  ├─ LayoutResolver         → Test frame calculations
  ├─ SpatialTransitionEngine → Test state transitions
  └─ LayoutOrchestrator      → Test animation sequencing

Modules/SpatialEngine/      → Unit tests (geometry)
  ├─ CollisionResolver      → Test overlap detection
  └─ LayoutStabilizer       → Test jitter prevention

Modules/SpatialMemory/      → Unit tests (learning)
  ├─ PatternExtractor       → Test pattern identification
  └─ LayoutPredictor        → Test prediction accuracy

Modules/SpatialState/       → Integration tests
  ├─ DriftDetector          → Test drift detection
  └─ ReconciliationEngine   → Test state correction

Modules/WindowEngine/       → System integration tests
  ├─ WindowMover            → Test frame application (requires AX)
  └─ WindowSnapshotter      → Test state capture

Modules/UI/                 → UI tests
  ├─ LayoutLibraryController → Test UI presentation
  └─ LayoutLibraryPanel     → Test user interactions
```

---

## Summary: Module Relationships

```
┌─────────────────────────────────────────────────────────────┐
│ ENTRY POINT: ReLay Executable (Sources/ReLay/main.swift)   │
│                                                             │
│ AppDelegate initializes:                                   │
│  ├─ GestureEngine (from Gesture module)                    │
│  ├─ TitleBarInterceptor (from Gesture module)              │
│  ├─ SpatialTransitionEngine.shared (from Layout)           │
│  ├─ WindowStateStore.shared (from StateManagement)         │
│  └─ SpatialStateCore.shared (from SpatialState)            │
│                                                             │
│ User interaction:                                          │
│  ├─ Gesture detected → delegates to SpatialTransitionEngine│
│  ├─ Layout state updated → LayoutOrchestrator applies     │
│  ├─ Preview shown → PreviewManager updates overlays        │
│  └─ History recorded → LayoutHistoryStore logs event       │
│                                                             │
│ Background (continuous):                                   │
│  └─ SpatialStateCore reconciles actual vs. expected state  │
│                                                             │
│ User request (menu):                                       │
│  ├─ Present library → LayoutLibraryController.present()    │
│  ├─ Suggest template → LayoutSuggestionEngine.rank()       │
│  └─ Apply layout → LayoutOrchestrator.animateWindowFrame() │
└─────────────────────────────────────────────────────────────┘
```

---

This visual guide complements the detailed MODULARIZATION_PLAN.md. Reference both when implementing changes.
