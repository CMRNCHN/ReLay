# ReLay Modularization Implementation Plan

## Executive Summary

This document outlines a detailed plan to reorganize the ReLay codebase from a monolithic ReLayCore target into 6 logical, interdependent modules while maintaining a single Swift Package target. The refactoring is a pure reorganization—no behavioral changes, no API modifications, no split into sub-targets in Package.swift.

**Key Constraint:** All modules remain within the single `ReLayCore` target. The reorganization is folder-based to establish clear ownership and improve codebase navigation.

---

## 1. Current State Analysis

### File Inventory (77 total Swift files)

**Root-level files (22):**
```
AccessibilityBootstrap.swift     → Shared/SystemIntegration
AppLibraryStore.swift            → LayoutLibrary
AppLogger.swift                  → Shared/Utilities
CrashLogger.swift                → Shared/Utilities
GestureEngine.swift              → GestureCapture
Imports.swift                    → Shared/Utilities
LayoutHistoryStore.swift         → LayoutLibrary
LayoutLibraryController.swift    → LayoutLibrary
LayoutOrchestrator.swift         → LayoutOrchestration
LayoutResolver.swift             → LayoutOrchestration
LayoutSuggestionEngine.swift     → LayoutLibrary
LayoutTemplate.swift             → LayoutLibrary
LayoutWorkspaceEditor.swift      → LayoutLibrary
PersistenceModels.swift          → Shared/Utilities
PreviewManager.swift             → LayoutOrchestration
ReLaySettings.swift              → Shared/Configuration
SpatialTransitionEngine.swift    → LayoutEngine
TitleBarInterceptor.swift        → GestureCapture
UIComponentLibrary.swift         → LayoutLibrary
WindowLayoutState.swift          → Core/Shared (Models)
WindowRoleClassifier.swift       → Core/Shared (Models)
WindowStateStore.swift           → LayoutEngine
```

**Subdirectories (already organized, some need renaming):**
- `Input/` (8 files) → `GestureCapture/Input/`
- `SpatialEngine/` (12 files) → `LayoutEngine/Spatial/`
- `SpatialMemory/` (11 files) → `LayoutEngine/Memory/`
- `SpatialState/` (8 files) → `LayoutEngine/State/`
- `SpatialStateCore/` (1 file) → `LayoutEngine/Reconciliation/`
- `WindowEngine/` (14 files) → `SystemIntegration/WindowEngine/`

**Tests (5 files remain in ReLayCoreTests)** - folder structure mirrors sources

---

## 2. Target Module Structure

### 2.1 Module: `GestureCapture`

**Responsibility:** Raw input interception and gesture detection from title bars.

**Ownership:**
```
Sources/ReLayCore/GestureCapture/
├── TitleBarInterceptor.swift        [Core gesture interceptor]
├── GestureEngine.swift              [State machine for raw gesture recognition]
└── Input/
    ├── Capture/
    │   └── EventTapCapture.swift
    ├── Core/
    │   ├── AppIntent.swift
    │   ├── Gesture.swift
    │   ├── GestureState.swift
    │   ├── InputProtocols.swift
    │   ├── NormalizedEvent.swift
    │   └── RawInputEvent.swift
    ├── Dispatch/
    │   └── ActionDispatcher.swift
    ├── Engine/
    │   └── InputGestureEngine.swift
    ├── Normalize/
    │   └── EventNormalizer.swift
    ├── Pipeline/
    │   └── InputPipeline.swift
    └── Routing/
        └── GestureRouter.swift
```

**Public API:**
- `TitleBarInterceptor` - main interceptor, delegates to `TitleBarInterceptorDelegate`
- `GestureEngine` - implements delegate, processes raw gestures
- `InputPipeline.shared` - lifecycle control (start/stop)
- `InputGesture` enum - gesture types
- `Gesture` struct - gesture data model

**Dependencies:**
- `Core/Shared` (models: `Gesture`, `GestureState`)
- `Shared/Utilities` (`AppLogger`)
- `Shared/SystemIntegration` (accessibility APIs)

**Note:** `ActionDispatcher` internally communicates with `SpatialTransitionEngine` (defined in LayoutEngine). This is acceptable as LayoutEngine depends on GestureCapture's output.

---

### 2.2 Module: `LayoutEngine`

**Responsibility:** Core layout state machine, spatial calculations, physics, and reconciliation.

**Ownership:**
```
Sources/ReLayCore/LayoutEngine/
├── LayoutOrchestrator.swift         [Low-level frame animation & AX writes]
├── SpatialTransitionEngine.swift    [Semantic state machine & preview]
├── LayoutResolver.swift             [Geometry: State ↔ Frame mapping]
├── WindowStateStore.swift           [Persistent semantic layout state]
├── PreviewManager.swift             [Overlay visualization during gesture]
├── Spatial/                         [Renamed from SpatialEngine/]
│   ├── Bridge/
│   │   └── SpatialToWindowBridge.swift
│   ├── Core/
│   │   ├── DisplaySpaceMap.swift
│   │   ├── SpatialContext.swift
│   │   ├── SpatialFrame.swift
│   │   ├── SpatialPoint.swift
│   ├── Engine/
│   │   └── SpatialEngine.swift
│   ├── Layout/
│   │   ├── CollisionResolver.swift
│   │   ├── LayoutEngine.swift
│   │   └── LayoutStabilizer.swift
│   └── Resolution/
│       ├── CoordinateResolver.swift
│       ├── DisplayNormalizer.swift
│       └── SpaceResolver.swift
├── Memory/                          [Renamed from SpatialMemory/]
│   ├── Core/
│   │   ├── LayoutPattern.swift
│   │   ├── MemoryModel.swift
│   │   ├── PredictionContext.swift
│   │   └── UsageEvent.swift
│   ├── Engine/
│   │   └── SpatialMemoryEngine.swift
│   ├── Learning/
│   │   ├── FrequencyModel.swift
│   │   ├── PatternExtractor.swift
│   │   └── TransitionGraph.swift
│   └── Prediction/
│       ├── ConfidenceScorer.swift
│       ├── LayoutPredictor.swift
│       └── WindowPlacementEngine.swift
├── State/                           [Renamed from SpatialState/]
│   ├── Core/
│   │   ├── SpatialState.swift
│   │   ├── SpatialStateSnapshot.swift
│   │   └── StateVersion.swift
│   ├── Engine/
│   │   └── SpatialStateCore.swift
│   ├── Store/
│   │   ├── SpatialStateStore.swift
│   │   └── StateReducer.swift
│   └── Sync/
│       ├── DriftDetector.swift
│       ├── ReconciliationEngine.swift
│       └── SystemStateReader.swift
└── Reconciliation/
    └── SpatialStateReconciler.swift  [Moved from SpatialStateCore/]
```

**Public API:**
- `SpatialTransitionEngine.shared` - main orchestrator for layout transitions
- `LayoutOrchestrator.shared` - low-level frame animation
- `WindowStateStore.shared` - state query & update
- `LayoutResolver.shared` - geometric calculations
- `PreviewManager.shared` - preview overlays
- `SpatialStateCore.shared` - system state reconciliation

**Internal API (used by LayoutOrchestration):**
- `LayoutTransitionGraph` - state machine graph
- All spatial, memory, and state calculation engines

**Dependencies:**
- `GestureCapture` (receives gesture input via `ActionDispatcher`)
- `Core/Shared` (models: `WindowLayoutState`, `WindowID`, etc.)
- `Shared/Utilities` (`AppLogger`, `ReLaySettings`)
- `SystemIntegration/WindowEngine` (for window queries, frame application)

---

### 2.3 Module: `LayoutOrchestration`

**Responsibility:** High-level animation sequencing and multi-window layout application.

**Note:** The current `LayoutOrchestrator` class is LOW-level (pure frame animation, no semantics).
This module wraps semantic operations that use `LayoutOrchestrator` + `SpatialTransitionEngine`.

**Ownership:**
```
Sources/ReLayCore/LayoutOrchestration/
├── LayoutOrchestrationController.swift  [NEW: high-level orchestration]
├── AnimationSequencer.swift             [NEW: animation composition]
└── README.md                            [Module documentation]
```

**Current Status:** The codebase doesn't yet have high-level orchestration separable from `SpatialTransitionEngine`. This module will be **light** initially—primarily providing a single controller that coordinates `SpatialTransitionEngine` + `LayoutOrchestrator` for external callers.

**Public API:**
- `LayoutOrchestrationController.shared` - primary interface for top-level layout operations

**Dependencies:**
- `LayoutEngine` (`SpatialTransitionEngine`, `LayoutOrchestrator`)
- `GestureCapture` (gesture types)
- `Core/Shared` (models)
- `Shared/Utilities`

---

### 2.4 Module: `LayoutLibrary`

**Responsibility:** Template library UI, suggestion engine, history, and persistence.

**Ownership:**
```
Sources/ReLayCore/LayoutLibrary/
├── LayoutLibraryController.swift     [Main library UI controller]
├── LayoutTemplate.swift              [Template definitions & slots]
├── LayoutSuggestionEngine.swift      [Ranking & recommendation]
├── LayoutHistoryStore.swift          [Recent layouts & analytics]
├── AppLibraryStore.swift             [App library & metadata]
├── LayoutWorkspaceEditor.swift       [Workspace layout editing UI]
├── UIComponentLibrary.swift          [Reusable UI components]
└── README.md                         [Module documentation]
```

**Public API:**
- `LayoutLibraryController.shared` - present/dismiss library UI
- `LayoutTemplate.all` - available templates
- `LayoutLibraryController.recentMenuItems()` - menu bar integration
- `LayoutLibraryController.quickApply()` - template application
- `LayoutSuggestionEngine.rank()` - template ranking

**Dependencies:**
- `LayoutEngine` (`LayoutOrchestrator`, `LayoutSuggestionEngine` results)
- `LayoutOrchestration` (high-level layout application)
- `Core/Shared` (models: `WindowRole`, `LayoutTemplate`)
- `Shared/Utilities` (`AppLogger`)
- `SystemIntegration/WindowEngine` (window enumeration)

---

### 2.5 Module: `Core/Shared`

**Responsibility:** Data models, enums, and type definitions used across all modules.

**Ownership:**
```
Sources/ReLayCore/Core/Shared/
├── Models/
│   ├── WindowLayoutState.swift       [Semantic layout state enum]
│   ├── WindowStateStore.swift        [Generic state record struct]
│   ├── WindowRole.swift              [Window role classification]
│   └── WindowRoleClassifier.swift    [Role inference logic]
├── Types/
│   ├── WindowID.swift                [Window identity wrapper]
│   └── SpatialTypes.swift            [NEW: spatial primitives exported]
└── README.md
```

**Public API:**
- `WindowLayoutState` enum - `.fullscreen`, `.leftHalf`, `.center`, etc.
- `WindowRole` enum - `.editor`, `.browser`, `.terminal`, etc.
- `WindowID` struct - hashable window identity
- `WindowRecord` struct - state + history for a window
- `Gesture` & `GestureState` types (re-exported from GestureCapture)

**Dependencies:** None (leaf module)

---

### 2.6 Module: `SystemIntegration`

**Responsibility:** Accessibility APIs, system window management, display detection.

**Ownership:**
```
Sources/ReLayCore/SystemIntegration/
├── AccessibilityBootstrap.swift      [AX permission & conflict detection]
├── WindowEngine/
│   ├── Core/
│   │   ├── DisplayModel.swift
│   │   ├── WindowModel.swift
│   │   └── WorkspaceModel.swift
│   ├── Engine/
│   │   └── WindowEngine.swift
│   ├── Capture/
│   │   ├── WindowSnapshotter.swift
│   │   └── WorkspaceSnapshotter.swift
│   ├── Control/
│   │   ├── FocusController.swift
│   │   ├── WindowMover.swift
│   │   └── WindowResizer.swift
│   └── Persistence/
│       └── WorkspaceStore.swift
└── README.md
```

**Public API:**
- `AccessibilityBootstrap.isGranted()` - check AX permissions
- `AccessibilityBootstrap.registerSilently()` - trigger permission
- `AccessibilityBootstrap.checkForConflictingApps()` - detect conflicts
- `WindowEngine.shared` - query/enumerate windows
- `WindowSnapshotter`, `WorkspaceSnapshotter` - capture current state
- `WindowMover`, `WindowResizer`, `FocusController` - window control

**Dependencies:**
- `Core/Shared` (models)
- `Shared/Utilities` (`AppLogger`)

---

### 2.7 Module: `Shared/Utilities`

**Responsibility:** Logging, settings, persistence, and common utilities.

**Ownership:**
```
Sources/ReLayCore/Shared/Utilities/
├── AppLogger.swift                   [Unified logging]
├── CrashLogger.swift                 [Crash reporting]
├── ReLaySettings.swift               [User defaults wrapper]
├── PersistenceModels.swift           [Codable structs for storage]
├── Imports.swift                     [Common framework imports]
└── README.md
```

**Public API:**
- `AppLogger.log()` - logging interface
- `CrashLogger.setup()` - crash reporter initialization
- `ReLaySettings` - user preferences access
- Codable model types for persistence

**Dependencies:** None (leaf module)

---

## 3. Module Responsibility Matrix

| Module | Files | Responsibility | Public API (Key Types) | Dependencies |
|--------|-------|-----------------|------------------------|--------------|
| **GestureCapture** | 16 | Raw input interception & gesture detection | `TitleBarInterceptor`, `GestureEngine`, `InputPipeline.shared`, `InputGesture` | Core/Shared, Shared/Utilities, SystemIntegration |
| **LayoutEngine** | 44 | Layout state machine, physics, spatial calc | `SpatialTransitionEngine.shared`, `LayoutOrchestrator.shared`, `WindowStateStore.shared`, `LayoutResolver.shared` | GestureCapture, Core/Shared, Shared/Utilities, SystemIntegration |
| **LayoutOrchestration** | 2 | High-level animation sequencing | `LayoutOrchestrationController.shared` | LayoutEngine, GestureCapture, Core/Shared, Shared/Utilities |
| **LayoutLibrary** | 7 | Template UI, suggestion, history | `LayoutLibraryController.shared`, `LayoutTemplate.all`, `LayoutSuggestionEngine.rank()` | LayoutEngine, LayoutOrchestration, Core/Shared, Shared/Utilities, SystemIntegration |
| **Core/Shared** | 4 | Data models & types | `WindowLayoutState`, `WindowRole`, `WindowID`, `WindowRecord` | None |
| **SystemIntegration** | 20 | AX APIs, window management, displays | `AccessibilityBootstrap.*`, `WindowEngine.shared` | Core/Shared, Shared/Utilities |
| **Shared/Utilities** | 4 | Logging, settings, persistence | `AppLogger`, `CrashLogger`, `ReLaySettings` | None |

---

## 4. Dependency Diagram

```
External (AppKit, Accessibility, CoreGraphics)
         ↑
         |
    ┌────┴─────────┬──────────────────┬──────────────────┐
    |              |                  |                  |
[Shared/Utilities]  [Core/Shared]  [SystemIntegration]  [GestureCapture]
    └────┬─────────┘      ↑              ↑                  ↑
         |                |              |                  |
         └────────┬───────┘──────────────┴──────┬───────────┘
                  |                             |
              [LayoutEngine] ◄─────────────────┘
                  ↑
                  |
         [LayoutOrchestration]
                  ↑
                  |
          [LayoutLibrary]
                  |
                  ↓
               main.swift (ReLay executable)
```

**Hierarchy (dependency flow):**
1. **Leaf modules** (no dependencies on other ReLay modules):
   - `Shared/Utilities`
   - `Core/Shared`

2. **Foundation modules** (depend on leaf only):
   - `SystemIntegration`
   - `GestureCapture`

3. **Core engine** (depends on foundation):
   - `LayoutEngine` (depends on: GestureCapture, Core/Shared, Shared/Utilities, SystemIntegration)

4. **Orchestration** (depends on engine):
   - `LayoutOrchestration` (depends on: LayoutEngine, GestureCapture, Core/Shared, Shared/Utilities)

5. **UI/Features** (depend on orchestration):
   - `LayoutLibrary` (depends on: LayoutEngine, LayoutOrchestration, Core/Shared, Shared/Utilities, SystemIntegration)

**Circular dependency check:** ✓ None detected. Flow is acyclic.

---

## 5. File Migration Plan

### Complete File Mapping (Current Path → New Path)

#### 5.1 GestureCapture Module
```
TitleBarInterceptor.swift
  → GestureCapture/TitleBarInterceptor.swift

GestureEngine.swift
  → GestureCapture/GestureEngine.swift

Input/Capture/EventTapCapture.swift
  → GestureCapture/Input/Capture/EventTapCapture.swift

Input/Core/AppIntent.swift
  → GestureCapture/Input/Core/AppIntent.swift

Input/Core/Gesture.swift
  → GestureCapture/Input/Core/Gesture.swift

Input/Core/GestureState.swift
  → GestureCapture/Input/Core/GestureState.swift

Input/Core/InputProtocols.swift
  → GestureCapture/Input/Core/InputProtocols.swift

Input/Core/NormalizedEvent.swift
  → GestureCapture/Input/Core/NormalizedEvent.swift

Input/Core/RawInputEvent.swift
  → GestureCapture/Input/Core/RawInputEvent.swift

Input/Dispatch/ActionDispatcher.swift
  → GestureCapture/Input/Dispatch/ActionDispatcher.swift

Input/Engine/InputGestureEngine.swift
  → GestureCapture/Input/Engine/InputGestureEngine.swift

Input/Normalize/EventNormalizer.swift
  → GestureCapture/Input/Normalize/EventNormalizer.swift

Input/Pipeline/InputPipeline.swift
  → GestureCapture/Input/Pipeline/InputPipeline.swift

Input/Routing/GestureRouter.swift
  → GestureCapture/Input/Routing/GestureRouter.swift
```

#### 5.2 LayoutEngine Module
```
LayoutOrchestrator.swift
  → LayoutEngine/LayoutOrchestrator.swift

SpatialTransitionEngine.swift
  → LayoutEngine/SpatialTransitionEngine.swift

LayoutResolver.swift
  → LayoutEngine/LayoutResolver.swift

WindowStateStore.swift
  → LayoutEngine/WindowStateStore.swift

PreviewManager.swift
  → LayoutEngine/PreviewManager.swift

SpatialEngine/Bridge/SpatialToWindowBridge.swift
  → LayoutEngine/Spatial/Bridge/SpatialToWindowBridge.swift

SpatialEngine/Core/DisplaySpaceMap.swift
  → LayoutEngine/Spatial/Core/DisplaySpaceMap.swift

SpatialEngine/Core/SpatialContext.swift
  → LayoutEngine/Spatial/Core/SpatialContext.swift

SpatialEngine/Core/SpatialFrame.swift
  → LayoutEngine/Spatial/Core/SpatialFrame.swift

SpatialEngine/Core/SpatialPoint.swift
  → LayoutEngine/Spatial/Core/SpatialPoint.swift

SpatialEngine/Engine/SpatialEngine.swift
  → LayoutEngine/Spatial/Engine/SpatialEngine.swift

SpatialEngine/Layout/CollisionResolver.swift
  → LayoutEngine/Spatial/Layout/CollisionResolver.swift

SpatialEngine/Layout/LayoutEngine.swift
  → LayoutEngine/Spatial/Layout/LayoutEngine.swift

SpatialEngine/Layout/LayoutStabilizer.swift
  → LayoutEngine/Spatial/Layout/LayoutStabilizer.swift

SpatialEngine/Resolution/CoordinateResolver.swift
  → LayoutEngine/Spatial/Resolution/CoordinateResolver.swift

SpatialEngine/Resolution/DisplayNormalizer.swift
  → LayoutEngine/Spatial/Resolution/DisplayNormalizer.swift

SpatialEngine/Resolution/SpaceResolver.swift
  → LayoutEngine/Spatial/Resolution/SpaceResolver.swift

SpatialMemory/Core/LayoutPattern.swift
  → LayoutEngine/Memory/Core/LayoutPattern.swift

SpatialMemory/Core/MemoryModel.swift
  → LayoutEngine/Memory/Core/MemoryModel.swift

SpatialMemory/Core/PredictionContext.swift
  → LayoutEngine/Memory/Core/PredictionContext.swift

SpatialMemory/Core/UsageEvent.swift
  → LayoutEngine/Memory/Core/UsageEvent.swift

SpatialMemory/Engine/SpatialMemoryEngine.swift
  → LayoutEngine/Memory/Engine/SpatialMemoryEngine.swift

SpatialMemory/Learning/FrequencyModel.swift
  → LayoutEngine/Memory/Learning/FrequencyModel.swift

SpatialMemory/Learning/PatternExtractor.swift
  → LayoutEngine/Memory/Learning/PatternExtractor.swift

SpatialMemory/Learning/TransitionGraph.swift
  → LayoutEngine/Memory/Learning/TransitionGraph.swift

SpatialMemory/Prediction/ConfidenceScorer.swift
  → LayoutEngine/Memory/Prediction/ConfidenceScorer.swift

SpatialMemory/Prediction/LayoutPredictor.swift
  → LayoutEngine/Memory/Prediction/LayoutPredictor.swift

SpatialMemory/Prediction/WindowPlacementEngine.swift
  → LayoutEngine/Memory/Prediction/WindowPlacementEngine.swift

SpatialState/Core/SpatialState.swift
  → LayoutEngine/State/Core/SpatialState.swift

SpatialState/Core/SpatialStateSnapshot.swift
  → LayoutEngine/State/Core/SpatialStateSnapshot.swift

SpatialState/Core/StateVersion.swift
  → LayoutEngine/State/Core/StateVersion.swift

SpatialState/Engine/SpatialStateCore.swift
  → LayoutEngine/State/Engine/SpatialStateCore.swift

SpatialState/Store/SpatialStateStore.swift
  → LayoutEngine/State/Store/SpatialStateStore.swift

SpatialState/Store/StateReducer.swift
  → LayoutEngine/State/Store/StateReducer.swift

SpatialState/Sync/DriftDetector.swift
  → LayoutEngine/State/Sync/DriftDetector.swift

SpatialState/Sync/ReconciliationEngine.swift
  → LayoutEngine/State/Sync/ReconciliationEngine.swift

SpatialState/Sync/SystemStateReader.swift
  → LayoutEngine/State/Sync/SystemStateReader.swift

SpatialStateCore/SpatialStateReconciler.swift
  → LayoutEngine/Reconciliation/SpatialStateReconciler.swift
```

#### 5.3 LayoutOrchestration Module
```
[NEW] LayoutOrchestrationController.swift
  → LayoutOrchestration/LayoutOrchestrationController.swift

[NEW] AnimationSequencer.swift
  → LayoutOrchestration/AnimationSequencer.swift
```

#### 5.4 LayoutLibrary Module
```
LayoutLibraryController.swift
  → LayoutLibrary/LayoutLibraryController.swift

LayoutTemplate.swift
  → LayoutLibrary/LayoutTemplate.swift

LayoutSuggestionEngine.swift
  → LayoutLibrary/LayoutSuggestionEngine.swift

LayoutHistoryStore.swift
  → LayoutLibrary/LayoutHistoryStore.swift

AppLibraryStore.swift
  → LayoutLibrary/AppLibraryStore.swift

LayoutWorkspaceEditor.swift
  → LayoutLibrary/LayoutWorkspaceEditor.swift

UIComponentLibrary.swift
  → LayoutLibrary/UIComponentLibrary.swift
```

#### 5.5 Core/Shared Module
```
WindowLayoutState.swift
  → Core/Shared/Models/WindowLayoutState.swift

WindowStateStore.swift (MOVE, not copy)
  → Core/Shared/Models/WindowStateStore.swift

WindowRoleClassifier.swift
  → Core/Shared/Models/WindowRoleClassifier.swift

[NEW] WindowRole.swift
  → Core/Shared/Models/WindowRole.swift

[NEW] WindowID.swift
  → Core/Shared/Models/WindowID.swift
```

**Note:** `WindowStateStore.swift` is currently in root but should move to Core/Shared since it's a generic data model. It will be imported by LayoutEngine but lives in Core/Shared.

#### 5.6 SystemIntegration Module
```
AccessibilityBootstrap.swift
  → SystemIntegration/AccessibilityBootstrap.swift

WindowEngine/Core/DisplayModel.swift
  → SystemIntegration/WindowEngine/Core/DisplayModel.swift

WindowEngine/Core/WindowModel.swift
  → SystemIntegration/WindowEngine/Core/WindowModel.swift

WindowEngine/Core/WorkspaceModel.swift
  → SystemIntegration/WindowEngine/Core/WorkspaceModel.swift

WindowEngine/Engine/WindowEngine.swift
  → SystemIntegration/WindowEngine/Engine/WindowEngine.swift

WindowEngine/Capture/WindowSnapshotter.swift
  → SystemIntegration/WindowEngine/Capture/WindowSnapshotter.swift

WindowEngine/Capture/WorkspaceSnapshotter.swift
  → SystemIntegration/WindowEngine/Capture/WorkspaceSnapshotter.swift

WindowEngine/Control/FocusController.swift
  → SystemIntegration/WindowEngine/Control/FocusController.swift

WindowEngine/Control/WindowMover.swift
  → SystemIntegration/WindowEngine/Control/WindowMover.swift

WindowEngine/Control/WindowResizer.swift
  → SystemIntegration/WindowEngine/Control/WindowResizer.swift

WindowEngine/Persistence/WorkspaceStore.swift
  → SystemIntegration/WindowEngine/Persistence/WorkspaceStore.swift
```

#### 5.7 Shared/Utilities Module
```
AppLogger.swift
  → Shared/Utilities/AppLogger.swift

CrashLogger.swift
  → Shared/Utilities/CrashLogger.swift

ReLaySettings.swift
  → Shared/Utilities/ReLaySettings.swift

PersistenceModels.swift
  → Shared/Utilities/PersistenceModels.swift

Imports.swift
  → Shared/Utilities/Imports.swift
```

---

## 6. Step-by-Step Implementation Guide

### Phase 1: Directory Structure Creation

**Goal:** Create all target directories and prepare for file moves.

**Commands:**

```bash
cd /home/user/ReLay/Sources/ReLayCore

# Create module root directories
mkdir -p GestureCapture/{Input/{Capture,Core,Dispatch,Engine,Normalize,Pipeline,Routing}}
mkdir -p LayoutEngine/{Spatial/{Bridge,Core,Engine,Layout,Resolution},Memory/{Core,Engine,Learning,Prediction},State/{Core,Engine,Store,Sync},Reconciliation}
mkdir -p LayoutOrchestration
mkdir -p LayoutLibrary
mkdir -p Core/Shared/{Models,Types}
mkdir -p SystemIntegration/WindowEngine/{Core,Engine,Capture,Control,Persistence}
mkdir -p Shared/Utilities
```

**Verification:**
```bash
# Check structure created
find . -type d -name "GestureCapture" -o -name "LayoutEngine" -o -name "LayoutOrchestration" \
  -o -name "LayoutLibrary" -o -name "Core" -o -name "SystemIntegration" -o -name "Shared" | sort
```

### Phase 2: Move GestureCapture Files

**Rationale:** GestureCapture is a leaf module (minimal dependencies). Move it first.

```bash
cd /home/user/ReLay/Sources/ReLayCore

# Move root gesture files
mv TitleBarInterceptor.swift GestureCapture/
mv GestureEngine.swift GestureCapture/

# Move Input subdirectory
mv Input/* GestureCapture/Input/
rmdir Input
```

**Git tracking:**
```bash
git add -A && git commit -m "refactor: move GestureCapture files to module directory"
```

**Verification:**
```bash
# Verify Input subdirs moved
find GestureCapture/Input -name "*.swift" | wc -l  # Should be 14
# Verify no Input/ at root
ls -d Input 2>/dev/null && echo "ERROR: Input still exists" || echo "OK"
```

### Phase 3: Create Core/Shared Models

**Rationale:** Core/Shared models are leaf—other modules depend on them.

```bash
cd /home/user/ReLay/Sources/ReLayCore

# Move existing model files
mv WindowLayoutState.swift Core/Shared/Models/
mv WindowRoleClassifier.swift Core/Shared/Models/

# Extract WindowID from WindowStateStore (it's currently defined there)
# Will do this after moving WindowStateStore to LayoutEngine
```

**New files to create:**

`Core/Shared/Models/WindowRole.swift`
```swift
import Foundation

public enum WindowRole: String, Codable, CaseIterable {
    case editor
    case browser
    case terminal
    case meeting
    case notes
    case chat
    case mail
    case ai
    case other
}
```

`Core/Shared/Models/WindowID.swift`
```swift
import ApplicationServices
import Accessibility

public struct WindowID: Hashable {
    let element: AXUIElement
    
    public static func == (lhs: WindowID, rhs: WindowID) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}
```

### Phase 4: Move SystemIntegration Files

**Rationale:** SystemIntegration depends only on Core/Shared and Shared/Utilities.

```bash
cd /home/user/ReLay/Sources/ReLayCore

# Move accessibility bootstrap
mv AccessibilityBootstrap.swift SystemIntegration/

# Move window engine
mv WindowEngine/* SystemIntegration/WindowEngine/
rmdir WindowEngine
```

**Verification:**
```bash
find SystemIntegration -name "*.swift" | wc -l  # Should be 20
```

### Phase 5: Move LayoutEngine Files

**Rationale:** LayoutEngine depends on GestureCapture and Core/Shared (now in place).

```bash
cd /home/user/ReLay/Sources/ReLayCore

# Move root layout files
mv LayoutOrchestrator.swift LayoutEngine/
mv SpatialTransitionEngine.swift LayoutEngine/
mv LayoutResolver.swift LayoutEngine/
mv WindowStateStore.swift LayoutEngine/  # Will move to Core/Shared AFTER fixing imports
mv PreviewManager.swift LayoutEngine/

# Move spatial modules with renames
mv SpatialEngine/* LayoutEngine/Spatial/
mv SpatialMemory/* LayoutEngine/Memory/
mv SpatialState/* LayoutEngine/State/
mv SpatialStateCore/* LayoutEngine/Reconciliation/

rmdir SpatialEngine SpatialMemory SpatialState SpatialStateCore
```

**Verification:**
```bash
find LayoutEngine -name "*.swift" | wc -l  # Should be 44
```

### Phase 6: Move LayoutLibrary Files

```bash
cd /home/user/ReLay/Sources/ReLayCore

mv LayoutLibraryController.swift LayoutLibrary/
mv LayoutTemplate.swift LayoutLibrary/
mv LayoutSuggestionEngine.swift LayoutLibrary/
mv LayoutHistoryStore.swift LayoutLibrary/
mv AppLibraryStore.swift LayoutLibrary/
mv LayoutWorkspaceEditor.swift LayoutLibrary/
mv UIComponentLibrary.swift LayoutLibrary/
```

**Verification:**
```bash
find LayoutLibrary -name "*.swift" | wc -l  # Should be 7
```

### Phase 7: Move Shared/Utilities Files

```bash
cd /home/user/ReLay/Sources/ReLayCore

mv AppLogger.swift Shared/Utilities/
mv CrashLogger.swift Shared/Utilities/
mv ReLaySettings.swift Shared/Utilities/
mv PersistenceModels.swift Shared/Utilities/
mv Imports.swift Shared/Utilities/
```

**Verification:**
```bash
find Shared/Utilities -name "*.swift" | wc -l  # Should be 5
```

### Phase 8: Fix Imports (Reverse Dependency Order)

**Order:** Leaf modules first, then those that depend on them.

#### 8.1 Shared/Utilities
No changes needed (no internal imports).

#### 8.2 Core/Shared
No changes needed (no internal imports).

#### 8.3 SystemIntegration
Update relative imports to absolute module imports:

**File:** `SystemIntegration/AccessibilityBootstrap.swift`
```swift
// Before (if any internal imports)
// After: No changes needed (uses AppKit, Accessibility only)
```

**File:** `SystemIntegration/WindowEngine/**/*.swift`
Search and update all imports:
```bash
grep -r "import AppKit\|import ApplicationServices" SystemIntegration/ | head

# No module imports to update (only system frameworks)
```

#### 8.4 GestureCapture
Update imports from `Core/Shared`:

**Command:**
```bash
cd GestureCapture
# No GestureCapture-internal cross-imports; Input/* are all contained within Input/
# Check for any imports of other ReLayCore modules
grep -r "^import" . | grep -v "import Foundation" | grep -v "import Cocoa" \
  | grep -v "import AppKit" | grep -v "import ApplicationServices" \
  | grep -v "import Accessibility" | grep -v "import CoreGraphics"
```

#### 8.5 LayoutEngine
Update imports in 44 files. Most critical:

**File:** `LayoutEngine/SpatialTransitionEngine.swift`
- Imports `GestureEngine` (moved to GestureCapture)
- Need to verify it still resolves correctly

**File:** `LayoutEngine/LayoutResolver.swift`
- Uses `WindowLayoutState` (in Core/Shared)
- Update: `import WindowLayoutState` → references will auto-resolve

**Command to identify all cross-module imports in LayoutEngine:**
```bash
cd LayoutEngine
grep -r "SpatialTransitionEngine\|LayoutOrchestrator\|WindowStateStore\|LayoutResolver" . \
  | grep "^[^:]*\.swift:" | cut -d: -f1 | sort | uniq
```

All imports within LayoutEngine should work fine since entire module is together. The key is ensuring external imports are correct.

#### 8.6 LayoutLibrary
Update imports:

**File:** `LayoutLibrary/LayoutLibraryController.swift`
- Uses `LayoutOrchestrator.shared` (in LayoutEngine)
- Uses `WindowRole` (in Core/Shared)
- Uses `LayoutTemplate` (in same module)
- Uses `LayoutSuggestionEngine` (in same module)

**Command:**
```bash
cd LayoutLibrary
grep -r "^import\|LayoutOrchestrator\|WindowRole\|LayoutSuggestionEngine" . \
  | head -20
```

Update cross-module references (LayoutOrchestrator, etc.) — but these are runtime references, not import statements. They're already using singletons so should work.

#### 8.7 LayoutOrchestration
Create new controller file (Phase 9).

---

### Phase 9: Create LayoutOrchestration Module

**File:** `LayoutOrchestration/LayoutOrchestrationController.swift`
```swift
import Foundation
import Accessibility
import ApplicationServices

/// High-level orchestrator for multi-window layout operations.
/// Wraps SpatialTransitionEngine (semantic state) + LayoutOrchestrator (animation).
public final class LayoutOrchestrationController {
    public static let shared = LayoutOrchestrationController()
    
    private let engine = SpatialTransitionEngine.shared
    private let animator = LayoutOrchestrator.shared
    
    private init() {
        // Initialization if needed
    }
    
    // MARK: - Public Interface
    
    /// Begins a gesture session for window layout manipulation.
    public func beginGestureSession(
        window: AXUIElement,
        fingerCount: Int,
        at location: CGPoint,
        gestureID: UUID
    ) {
        engine.beginSession(window: window, fingerCount: fingerCount, at: location, gestureID: gestureID)
    }
    
    /// Updates preview overlay during gesture.
    public func updateGesturePreview(deltaX: CGFloat, deltaY: CGFloat, velocity: CGFloat) {
        engine.updatePreview(deltaX: deltaX, deltaY: deltaY, velocity: velocity)
    }
    
    /// Commits the gesture session and applies final layout.
    public func commitGestureSession() {
        engine.commitSession()
    }
    
    /// Cancels the gesture session without applying changes.
    public func cancelGestureSession() {
        engine.cancelSession()
    }
}
```

**File:** `LayoutOrchestration/AnimationSequencer.swift`
```swift
import Foundation

/// Manages animation timing and sequencing for multi-window operations.
public final class AnimationSequencer {
    public static let shared = AnimationSequencer()
    
    private init() {}
    
    // Placeholder for future animation composition logic
    // Currently, LayoutOrchestrator handles animations directly
}
```

---

### Phase 10: Build Verification at Each Step

After each phase, verify the build succeeds:

```bash
cd /home/user/ReLay

# Full build
swift build 2>&1 | head -50

# If errors, inspect
swift build -v 2>&1 | grep "error:" | head -10
```

**Expected errors during imports fixing:**
- Module not found (if imports are incomplete)
- Use of undeclared identifier (if cross-module references are broken)

**Build checklist after Phase 8 (imports fixed):**
```bash
swift build && echo "✓ Build succeeded"
```

---

## 7. Import/Reference Fix Details

### 7.1 Files That Reference Cross-Module Types

**LayoutEngine files that reference GestureCapture:**
- `SpatialTransitionEngine.swift` uses `ActionDispatcher` indirectly through `TitleBarInterceptorDelegate`

**Resolution:** Verify that ActionDispatcher can still reach SpatialTransitionEngine for dispatch. Currently:
```swift
// In ActionDispatcher.swift (in GestureCapture/Input/Dispatch/)
SpatialTransitionEngine.shared.method()  // ← depends on SpatialTransitionEngine
```

This is OK because:
1. Both are defined in ReLayCore single target
2. At compile time, all modules in same target can reference each other
3. No actual "import" statement needed—just qualified names work

### 7.2 Files That Need "Re-export" or public visibility

Make key types public:

**Core/Shared/Models/WindowLayoutState.swift:**
```swift
public enum WindowLayoutState: CaseIterable {
    case floating
    case fullscreen
    case center
    case leftHalf
    case rightHalf
    // ... etc
}
```

**LayoutEngine/SpatialTransitionEngine.swift:**
```swift
public final class SpatialTransitionEngine {
    public static let shared = SpatialTransitionEngine()
    // ... public methods
}
```

**SystemIntegration/WindowEngine/Engine/WindowEngine.swift:**
```swift
public final class WindowEngine {
    public static let shared = WindowEngine()
    // ... public methods
}
```

### 7.3 Test File Structure

Update `Tests/ReLayCoreTests/` to mirror source structure:

```bash
mkdir -p Tests/ReLayCoreTests/{GestureCapture,LayoutEngine,LayoutLibrary,Core,SystemIntegration,Shared}

# Move test files to match module structure
# (Identify which tests go with which modules by examining test names)
```

---

## 8. Build Verification Checklist

Run this after each phase and again at the end:

```bash
cd /home/user/ReLay

# 1. Clean build
rm -rf .build
swift build --configuration debug 2>&1 | tee build.log

# 2. Check for errors
grep -c "error:" build.log && echo "ERRORS FOUND" || echo "No errors"

# 3. Run tests
swift test 2>&1 | tee test.log
grep -c "FAILED\|error:" test.log && echo "TESTS FAILED" || echo "Tests passed"

# 4. Verify no behavioral changes (smoke test)
# Run the app and verify gesture recognition works

# 5. Check file count
echo "Total Swift files:"
find Sources/ReLayCore -name "*.swift" | wc -l  # Should be 77

echo "Files in each module:"
for dir in GestureCapture LayoutEngine LayoutLibrary Core SystemIntegration Shared; do
  count=$(find Sources/ReLayCore/$dir -name "*.swift" 2>/dev/null | wc -l)
  [ $count -gt 0 ] && echo "  $dir: $count"
done
```

---

## 9. Git Commit Strategy

Perform migrations in atomic commits to maintain bisectability:

```bash
# Phase 1: Directory structure
git add -A && git commit -m "refactor: create module directory structure (no file moves yet)"

# Phase 2: GestureCapture move
git add -A && git commit -m "refactor: move GestureCapture module files"

# Phase 3: Core/Shared
git add -A && git commit -m "refactor: create Core/Shared models module"

# Phase 4: SystemIntegration
git add -A && git commit -m "refactor: move SystemIntegration module files"

# Phase 5: LayoutEngine
git add -A && git commit -m "refactor: move LayoutEngine module files"

# Phase 6: LayoutLibrary
git add -A && git commit -m "refactor: move LayoutLibrary module files"

# Phase 7: Shared/Utilities
git add -A && git commit -m "refactor: move Shared/Utilities module files"

# Phase 8: Import fixes
git add -A && git commit -m "refactor: update imports after module reorganization"

# Phase 9: LayoutOrchestration
git add -A && git commit -m "refactor: create LayoutOrchestration controller module"

# Phase 10: Final verification
git add -A && git commit -m "refactor: verify build and tests after full modularization"
```

---

## 10. README Templates for Each Module

Create README.md in each module directory explaining purpose and ownership.

### 10.1 GestureCapture/README.md
```markdown
# GestureCapture Module

**Ownership:** Input interception & raw gesture detection

## Responsibility

Captures raw input events from macOS title bars and normalizes them into discrete gesture types 
(swipe, pinch, scroll). Provides the input pipeline that feeds the layout engine.

## Public API

- `TitleBarInterceptor` — Main interceptor class
- `GestureEngine` — State machine for gesture recognition
- `InputPipeline.shared` — Start/stop the input pipeline
- `InputGesture` enum — Gesture types
- `Gesture` struct — Gesture event data

## Dependencies

- Core/Shared (models)
- Shared/Utilities (logging)
- SystemIntegration (accessibility APIs)

## Internal Structure

```
GestureCapture/
├── TitleBarInterceptor.swift  — Entry point for title bar events
├── GestureEngine.swift         — Gesture state machine
└── Input/                      — Pipeline stages
    ├── Capture/    — Raw event capture via event taps
    ├── Core/       — Data models (Gesture, GestureState, etc.)
    ├── Normalize/  — Event normalization
    ├── Engine/     — Gesture recognition logic
    ├── Routing/    — Dispatch routing
    └── Pipeline/   — Pipeline orchestration
```

## Testing

See `Tests/ReLayCoreTests/GestureCapture/` for unit tests.

## Design Notes

- TitleBarInterceptor delegates to GestureEngine (implements TitleBarInterceptorDelegate)
- InputPipeline wires all stages together with dependency injection for testability
- All gesture processing is synchronous and runs on the main RunLoop thread
```

### 10.2 LayoutEngine/README.md
```markdown
# LayoutEngine Module

**Ownership:** Layout state machine, spatial calculations, physics

## Responsibility

The core engine responsible for:
- Semantic layout state (fullscreen, split, thirds, etc.)
- State transitions and history management
- Spatial calculations (collision detection, resolution, stabilization)
- Memory/learning about user layout preferences
- System state reconciliation

## Public API

- `SpatialTransitionEngine.shared` — Main semantic orchestrator
- `LayoutOrchestrator.shared` — Low-level frame animation & AX writes
- `WindowStateStore.shared` — Semantic state storage per window
- `LayoutResolver.shared` — Geometric calculations
- `PreviewManager.shared` — Preview overlays during gestures
- `SpatialStateCore.shared` — System state reconciliation

## Dependencies

- GestureCapture (receives gesture input)
- Core/Shared (models: WindowLayoutState, WindowID, etc.)
- Shared/Utilities (logging, settings)
- SystemIntegration (window queries, frame application)

## Internal Structure

```
LayoutEngine/
├── SpatialTransitionEngine.swift  — Semantic state machine
├── LayoutOrchestrator.swift       — Low-level animation
├── LayoutResolver.swift           — Geometry calculations
├── WindowStateStore.swift         — State persistence
├── PreviewManager.swift           — Preview overlays
├── Spatial/                       — Spatial calculations
│   ├── Engine/     — Core spatial engine
│   ├── Core/       — Spatial types & models
│   ├── Layout/     — Layout algorithms (collision, stabilization)
│   ├── Bridge/     — Spatial↔Window conversion
│   └── Resolution/ — Coordinate/display resolution
├── Memory/                        — Layout learning & prediction
│   ├── Engine/     — Memory engine
│   ├── Core/       — Models (LayoutPattern, MemoryModel, etc.)
│   ├── Learning/   — Pattern extraction & learning
│   └── Prediction/ — Layout prediction & scoring
├── State/                         — System state tracking
│   ├── Core/       — State models (SpatialState, StateVersion, etc.)
│   ├── Engine/     — State core logic
│   ├── Store/      — State store & reducer
│   └── Sync/       — Drift detection & reconciliation
└── Reconciliation/ — System state reconciliation
```

## Key Classes

- **SpatialTransitionEngine** — The semantic orchestrator; owns the state graph
- **LayoutOrchestrator** — Pure animation layer; handles all AX frame writes
- **SpatialEngine** — Spatial calculations and frame resolution
- **SpatialMemoryEngine** — Learns layout patterns and predicts next layout
- **SpatialStateCore** — Reconciles system state with internal model

## Testing

See `Tests/ReLayCoreTests/LayoutEngine/` for unit tests.

## Design Notes

- No side effects in calculation layers (Spatial, Memory, State)
- SpatialTransitionEngine owns the state machine; drives preview & animation
- LayoutOrchestrator is the ONLY place where AX frame writes occur
- System reconciliation is asynchronous to prevent blocking the main loop
```

### 10.3 LayoutOrchestration/README.md
```markdown
# LayoutOrchestration Module

**Ownership:** High-level animation sequencing & multi-window layout operations

## Responsibility

Provides high-level coordination for layout operations. Wraps the low-level SpatialTransitionEngine 
and LayoutOrchestrator for external callers (LayoutLibrary, main app).

## Public API

- `LayoutOrchestrationController.shared` — Main controller for layout operations
- `AnimationSequencer.shared` — Animation timing & sequencing (future expansion)

## Dependencies

- LayoutEngine (SpatialTransitionEngine, LayoutOrchestrator)
- GestureCapture (gesture types)
- Core/Shared (models)
- Shared/Utilities (logging)

## Design Notes

- Currently light—primary role is providing a single public entry point
- In future, can expand to handle complex multi-step animation sequences
- Delegates actual state management to LayoutEngine
```

### 10.4 LayoutLibrary/README.md
```markdown
# LayoutLibrary Module

**Ownership:** Template library UI, suggestion engine, history, persistence

## Responsibility

Manages the layout template library UI and provides:
- Template definitions and library presentation
- Layout suggestions based on usage patterns
- Recent layout history
- App classification and library metadata
- Workspace layout editing

## Public API

- `LayoutLibraryController.shared` — Main library UI controller
- `LayoutLibraryController.present()` — Show library UI
- `LayoutLibraryController.quickApply()` — Apply template directly
- `LayoutTemplate.all` — Available templates
- `LayoutSuggestionEngine.rank()` — Suggest best template

## Dependencies

- LayoutEngine (for applying layouts)
- LayoutOrchestration (high-level operations)
- Core/Shared (WindowRole, models)
- Shared/Utilities (logging, persistence)
- SystemIntegration (window enumeration)

## Internal Structure

```
LayoutLibrary/
├── LayoutLibraryController.swift   — Main UI controller
├── LayoutTemplate.swift            — Template definitions
├── LayoutSuggestionEngine.swift    — Template ranking
├── LayoutHistoryStore.swift        — Recent layouts & analytics
├── AppLibraryStore.swift           — App metadata & classification
├── LayoutWorkspaceEditor.swift     — Workspace layout UI
└── UIComponentLibrary.swift        — Reusable UI components
```

## Testing

See `Tests/ReLayCoreTests/LayoutLibrary/` for unit tests.

## Design Notes

- Templates are defined as data, not UI code
- Suggestion engine ranks templates based on window roles & history
- Library UI is optional; templates can be applied directly via quickApply()
```

### 10.5 Core/Shared/README.md
```markdown
# Core/Shared Module

**Ownership:** Data models and type definitions

## Responsibility

Defines all fundamental types and enums used across ReLay:
- Window layout states (fullscreen, split, thirds, etc.)
- Window roles (editor, browser, terminal, etc.)
- Window identity & state storage
- Shared data structures

## Public API

- `WindowLayoutState` enum — Semantic layout states
- `WindowRole` enum — Window role classification
- `WindowID` struct — Hashable window identity
- `WindowRecord` struct — State + history for a window
- `WindowRoleClassifier` — Role inference logic

## Dependencies

None (leaf module).

## Design Notes

- All types are public and fully documented
- Enums use standard Swift conventions (CaseIterable, Codable where needed)
- No logic beyond data definition
```

### 10.6 SystemIntegration/README.md
```markdown
# SystemIntegration Module

**Ownership:** Accessibility APIs, system window management, display detection

## Responsibility

Provides all integration with macOS system APIs:
- Accessibility permission checking
- Window enumeration and state capture
- Window control (move, resize, focus)
- Display/space detection and resolution
- Workspace management

## Public API

- `AccessibilityBootstrap` — AX permission & conflict detection
- `WindowEngine.shared` — Window enumeration and query
- `WindowSnapshotter` — Capture current window state
- `WindowMover`, `WindowResizer`, `FocusController` — Window control
- `DisplayModel`, `WindowModel`, `WorkspaceModel` — System models

## Dependencies

- Core/Shared (models)
- Shared/Utilities (logging)

## Internal Structure

```
SystemIntegration/
├── AccessibilityBootstrap.swift    — AX permission handling
└── WindowEngine/
    ├── Core/       — System models (DisplayModel, WindowModel, etc.)
    ├── Engine/     — Main window engine
    ├── Capture/    — State snapshotting
    ├── Control/    — Window manipulation
    └── Persistence/ — Workspace persistence
```

## Testing

See `Tests/ReLayCoreTests/SystemIntegration/` for integration tests.

## Design Notes

- All AX calls are isolated here
- WindowEngine provides a unified interface for all system queries
- Thread safety is ensured for background AX operations
- Window models are immutable snapshots
```

### 10.7 Shared/Utilities/README.md
```markdown
# Shared/Utilities Module

**Ownership:** Logging, settings, persistence, common utilities

## Responsibility

Provides utilities used across all modules:
- Unified logging interface
- Crash reporting
- User settings and defaults
- Persistence models for codable types

## Public API

- `AppLogger.log()` — Log messages with subsystem and session ID
- `CrashLogger.setup()` — Initialize crash reporter
- `ReLaySettings` — User defaults wrapper
- `Imports` — Re-exported common framework imports

## Dependencies

None (leaf module).

## Design Notes

- AppLogger is used across all modules
- Settings are read-only; mutations go through UserDefaults
- Persistence models are simple Codable structs
```

---

## 11. Validation Checklist (Final)

After completing all phases, verify:

```bash
cd /home/user/ReLay

# 1. All files accounted for
echo "Expected 77 files total:"
find Sources/ReLayCore -name "*.swift" | wc -l

# 2. Build succeeds
swift build 2>&1 | tail -1

# 3. Tests pass
swift test 2>&1 | grep -E "Test Suite|PASSED|FAILED" | tail -5

# 4. No files left in root (except README-like files if added)
ls Sources/ReLayCore/*.swift 2>&1 | grep -v "No such file" && echo "ERROR: Files in root" || echo "OK"

# 5. Module structure correct
for mod in GestureCapture LayoutEngine LayoutLibrary Core SystemIntegration Shared; do
  [ -d "Sources/ReLayCore/$mod" ] && echo "✓ $mod" || echo "✗ $mod"
done

# 6. Old directories removed
for old in Input SpatialEngine SpatialMemory SpatialState SpatialStateCore WindowEngine; do
  [ -d "Sources/ReLayCore/$old" ] && echo "✗ $old still exists" || echo "✓ $old removed"
done

# 7. README files created
for mod in GestureCapture LayoutEngine LayoutOrchestration LayoutLibrary Core SystemIntegration Shared; do
  [ -f "Sources/ReLayCore/$mod/README.md" ] && echo "✓ $mod/README.md" || echo "✗ $mod/README.md missing"
done

# 8. Git log shows commits
echo "Recent commits:"
git log --oneline -10 | head -5
```

---

## 12. Future Considerations

Once this refactoring is complete, future enhancements become easier:

1. **Sub-targets in Package.swift** — Can split into separate targets if needed (e.g., LayoutLibrary as separate framework)
2. **Feature toggles** — Each module can have enable/disable flags
3. **Testing** — Each module can have its own test target
4. **Documentation** — Module READMEs form the basis for architectural docs
5. **Dependency injection** — Can inject mock modules for testing complex flows

---

## Summary

This plan provides:

✓ **Folder Structure Plan** — Detailed mapping of all 77 files to 7 modules  
✓ **Module Responsibility Matrix** — Clear ownership & API surface  
✓ **Dependency Diagram** — Acyclic graph showing module relationships  
✓ **Step-by-Step Implementation** — Executable bash commands for each phase  
✓ **Build Verification Checklist** — How to validate at each step  
✓ **README Templates** — Documentation for each module  

**Estimated time:** 2-4 hours including import fixes and verification.

**Next step:** Execute Phase 1 (directory structure creation) and commit.
