# Complete File Migration Reference

## Purpose

This document provides a complete, machine-readable mapping of every Swift file and its destination during modularization. Use this as a checklist when moving files.

## Format

```
Original Path → New Path (Module)
```

---

## Foundation Module (5 files)

### Core Utilities
```
AppLogger.swift 
  → Modules/Foundation/Core/AppLogger.swift

CrashLogger.swift 
  → Modules/Foundation/Core/CrashLogger.swift

ReLaySettings.swift 
  → Modules/Foundation/Core/ReLaySettings.swift

Imports.swift 
  → Modules/Foundation/Core/Imports.swift
```

### Accessibility & Models
```
AccessibilityBootstrap.swift 
  → Modules/Foundation/Accessibility/AccessibilityBootstrap.swift

WindowRoleClassifier.swift 
  → Modules/Foundation/Accessibility/WindowRoleClassifier.swift

PersistenceModels.swift 
  → Modules/Foundation/Models/PersistenceModels.swift

WindowLayoutState.swift 
  → Modules/Foundation/Models/WindowLayoutState.swift

UIComponentLibrary.swift 
  → Modules/Foundation/UI/UIComponentLibrary.swift
```

---

## Input Module (8 files - moves directory)

All files stay in same relative structure, just move under Modules/:

```
Input/Capture/EventTapCapture.swift 
  → Modules/Input/Capture/EventTapCapture.swift

Input/Core/AppIntent.swift 
  → Modules/Input/Core/AppIntent.swift

Input/Core/Gesture.swift 
  → Modules/Input/Core/Gesture.swift

Input/Core/GestureState.swift 
  → Modules/Input/Core/GestureState.swift

Input/Core/InputProtocols.swift 
  → Modules/Input/Core/InputProtocols.swift

Input/Core/NormalizedEvent.swift 
  → Modules/Input/Core/NormalizedEvent.swift

Input/Core/RawInputEvent.swift 
  → Modules/Input/Core/RawInputEvent.swift

Input/Dispatch/ActionDispatcher.swift 
  → Modules/Input/Dispatch/ActionDispatcher.swift

Input/Engine/InputGestureEngine.swift 
  → Modules/Input/Engine/InputGestureEngine.swift

Input/Normalize/EventNormalizer.swift 
  → Modules/Input/Normalize/EventNormalizer.swift

Input/Pipeline/InputPipeline.swift 
  → Modules/Input/Pipeline/InputPipeline.swift

Input/Routing/GestureRouter.swift 
  → Modules/Input/Routing/GestureRouter.swift
```

---

## Gesture Module (2 files)

```
TitleBarInterceptor.swift 
  → Modules/Gesture/TitleBarInterceptor.swift

GestureEngine.swift 
  → Modules/Gesture/GestureEngine.swift
```

---

## StateManagement Module (4 files)

```
WindowStateStore.swift 
  → Modules/StateManagement/WindowStateStore.swift

LayoutHistoryStore.swift 
  → Modules/StateManagement/LayoutHistoryStore.swift

AppLibraryStore.swift 
  → Modules/StateManagement/AppLibraryStore.swift

PreviewManager.swift 
  → Modules/StateManagement/PreviewManager.swift
```

---

## Layout Module (5 files)

```
LayoutOrchestrator.swift 
  → Modules/Layout/Application/LayoutOrchestrator.swift

SpatialTransitionEngine.swift 
  → Modules/Layout/Application/SpatialTransitionEngine.swift

LayoutResolver.swift 
  → Modules/Layout/Resolver/LayoutResolver.swift

LayoutTemplate.swift 
  → Modules/Layout/Templates/LayoutTemplate.swift

LayoutSuggestionEngine.swift 
  → Modules/Layout/Templates/LayoutSuggestionEngine.swift
```

---

## SpatialEngine Module (12 files - moves directory)

All files stay in same relative structure:

```
SpatialEngine/Bridge/SpatialToWindowBridge.swift 
  → Modules/SpatialEngine/Bridge/SpatialToWindowBridge.swift

SpatialEngine/Core/DisplaySpaceMap.swift 
  → Modules/SpatialEngine/Core/DisplaySpaceMap.swift

SpatialEngine/Core/SpatialContext.swift 
  → Modules/SpatialEngine/Core/SpatialContext.swift

SpatialEngine/Core/SpatialFrame.swift 
  → Modules/SpatialEngine/Core/SpatialFrame.swift

SpatialEngine/Core/SpatialPoint.swift 
  → Modules/SpatialEngine/Core/SpatialPoint.swift

SpatialEngine/Engine/SpatialEngine.swift 
  → Modules/SpatialEngine/Engine/SpatialEngine.swift

SpatialEngine/Layout/CollisionResolver.swift 
  → Modules/SpatialEngine/Layout/CollisionResolver.swift

SpatialEngine/Layout/LayoutEngine.swift 
  → Modules/SpatialEngine/Layout/LayoutEngine.swift

SpatialEngine/Layout/LayoutStabilizer.swift 
  → Modules/SpatialEngine/Layout/LayoutStabilizer.swift

SpatialEngine/Resolution/CoordinateResolver.swift 
  → Modules/SpatialEngine/Resolution/CoordinateResolver.swift

SpatialEngine/Resolution/DisplayNormalizer.swift 
  → Modules/SpatialEngine/Resolution/DisplayNormalizer.swift

SpatialEngine/Resolution/SpaceResolver.swift 
  → Modules/SpatialEngine/Resolution/SpaceResolver.swift
```

---

## SpatialMemory Module (11 files - moves directory)

All files stay in same relative structure:

```
SpatialMemory/Core/LayoutPattern.swift 
  → Modules/SpatialMemory/Core/LayoutPattern.swift

SpatialMemory/Core/MemoryModel.swift 
  → Modules/SpatialMemory/Core/MemoryModel.swift

SpatialMemory/Core/PredictionContext.swift 
  → Modules/SpatialMemory/Core/PredictionContext.swift

SpatialMemory/Core/UsageEvent.swift 
  → Modules/SpatialMemory/Core/UsageEvent.swift

SpatialMemory/Engine/SpatialMemoryEngine.swift 
  → Modules/SpatialMemory/Engine/SpatialMemoryEngine.swift

SpatialMemory/Learning/FrequencyModel.swift 
  → Modules/SpatialMemory/Learning/FrequencyModel.swift

SpatialMemory/Learning/PatternExtractor.swift 
  → Modules/SpatialMemory/Learning/PatternExtractor.swift

SpatialMemory/Learning/TransitionGraph.swift 
  → Modules/SpatialMemory/Learning/TransitionGraph.swift

SpatialMemory/Prediction/ConfidenceScorer.swift 
  → Modules/SpatialMemory/Prediction/ConfidenceScorer.swift

SpatialMemory/Prediction/LayoutPredictor.swift 
  → Modules/SpatialMemory/Prediction/LayoutPredictor.swift

SpatialMemory/Prediction/WindowPlacementEngine.swift 
  → Modules/SpatialMemory/Prediction/WindowPlacementEngine.swift
```

---

## SpatialState Module (9 files - moves directory)

All files stay in same relative structure, with SpatialStateCore reorganized:

```
SpatialState/Core/SpatialState.swift 
  → Modules/SpatialState/Core/SpatialState.swift

SpatialState/Core/SpatialStateSnapshot.swift 
  → Modules/SpatialState/Core/SpatialStateSnapshot.swift

SpatialState/Core/StateVersion.swift 
  → Modules/SpatialState/Core/StateVersion.swift

SpatialState/Engine/SpatialStateCore.swift 
  → Modules/SpatialState/Engine/SpatialStateCore.swift

SpatialState/Store/SpatialStateStore.swift 
  → Modules/SpatialState/Store/SpatialStateStore.swift

SpatialState/Store/StateReducer.swift 
  → Modules/SpatialState/Store/StateReducer.swift

SpatialState/Sync/DriftDetector.swift 
  → Modules/SpatialState/Sync/DriftDetector.swift

SpatialState/Sync/ReconciliationEngine.swift 
  → Modules/SpatialState/Sync/ReconciliationEngine.swift

SpatialState/Sync/SystemStateReader.swift 
  → Modules/SpatialState/Sync/SystemStateReader.swift

SpatialStateCore/SpatialStateReconciler.swift 
  → Modules/SpatialState/Reconciler/SpatialStateReconciler.swift
```

---

## WindowEngine Module (14 files - moves directory)

All files stay in same relative structure:

```
WindowEngine/Core/DisplayModel.swift 
  → Modules/WindowEngine/Core/DisplayModel.swift

WindowEngine/Core/WindowModel.swift 
  → Modules/WindowEngine/Core/WindowModel.swift

WindowEngine/Core/WorkspaceModel.swift 
  → Modules/WindowEngine/Core/WorkspaceModel.swift

WindowEngine/Engine/WindowEngine.swift 
  → Modules/WindowEngine/Engine/WindowEngine.swift

WindowEngine/Capture/WindowSnapshotter.swift 
  → Modules/WindowEngine/Capture/WindowSnapshotter.swift

WindowEngine/Capture/WorkspaceSnapshotter.swift 
  → Modules/WindowEngine/Capture/WorkspaceSnapshotter.swift

WindowEngine/Control/FocusController.swift 
  → Modules/WindowEngine/Control/FocusController.swift

WindowEngine/Control/WindowMover.swift 
  → Modules/WindowEngine/Control/WindowMover.swift

WindowEngine/Control/WindowResizer.swift 
  → Modules/WindowEngine/Control/WindowResizer.swift

WindowEngine/Persistence/WorkspaceStore.swift 
  → Modules/WindowEngine/Persistence/WorkspaceStore.swift
```

---

## UI Module (2 files)

```
LayoutLibraryController.swift 
  → Modules/UI/LibraryPanel/LayoutLibraryController.swift

LayoutWorkspaceEditor.swift 
  → Modules/UI/Workspace/LayoutWorkspaceEditor.swift
```

---

## NEW Files (2 files - to be created)

```
LayoutOrchestrationController.swift 
  → Modules/Layout/Application/LayoutOrchestrationController.swift
  (See IMPLEMENTATION_QUICK_START.md Phase 9 for content)

AnimationSequencer.swift 
  → Modules/Layout/Application/AnimationSequencer.swift
  (See IMPLEMENTATION_QUICK_START.md Phase 9 for content)
```

---

## Summary Statistics

| Statistic | Count |
|-----------|-------|
| Total existing files to move | 77 |
| New files to create | 2 |
| **Total files in final structure** | **79** |
| Modules | 10 |
| Root-level directories after move | 1 (Modules/) |
| Largest module | SpatialEngine (12) |
| Smallest module | Gesture (2) |
| Files requiring code changes | 0 |
| Build/Package.swift changes | 0 |

---

## Bash Commands to Execute

### Prepare: Create directory structure
```bash
cd /home/user/ReLay/Sources/ReLayCore

mkdir -p Modules/Foundation/{Core,Accessibility,Models,UI}
mkdir -p Modules/Gesture
mkdir -p Modules/StateManagement
mkdir -p Modules/Layout/{Application,Templates,Resolver}
mkdir -p Modules/Input/{Capture,Core,Dispatch,Engine,Normalize,Pipeline,Routing}
mkdir -p Modules/SpatialEngine/{Bridge,Core,Engine,Layout,Resolution}
mkdir -p Modules/SpatialMemory/{Core,Engine,Learning,Prediction}
mkdir -p Modules/SpatialState/{Core,Engine,Store,Sync,Reconciler}
mkdir -p Modules/WindowEngine/{Core,Engine,Capture,Control,Persistence}
mkdir -p Modules/UI/{LibraryPanel,Workspace}
```

### Execute: Move files (use commands from IMPLEMENTATION_QUICK_START.md)

### Verify: Check completion
```bash
# Count files in Modules/
find /home/user/ReLay/Sources/ReLayCore/Modules -name "*.swift" | wc -l
# Expected: 77

# Check no files remain at root
ls /home/user/ReLay/Sources/ReLayCore/*.swift 2>&1
# Expected: ls: cannot access (no Swift files at root)

# Verify structure
tree /home/user/ReLay/Sources/ReLayCore/Modules
```

---

## Cross-Reference by Original Location

Useful for finding where a file moved to, starting from original location:

### Root-level files
- All "thing.swift" files at root → Move to appropriate module based on responsibility
- Check FOUNDATION MODULE section if in doubt

### Input/ directory
- All files under Input/ → Modules/Input/ (same relative structure)

### SpatialEngine/ directory
- All files under SpatialEngine/ → Modules/SpatialEngine/ (same relative structure)

### SpatialMemory/ directory
- All files under SpatialMemory/ → Modules/SpatialMemory/ (same relative structure)

### SpatialState/ directory
- Most files under SpatialState/ → Modules/SpatialState/ (same relative structure)
- SPECIAL: SpatialStateCore/SpatialStateReconciler.swift → Modules/SpatialState/Reconciler/

### WindowEngine/ directory
- All files under WindowEngine/ → Modules/WindowEngine/ (same relative structure)

---

## Verification Checklist by Module

Use this checklist after moving each module group:

### ✓ Foundation Module
- [ ] AppLogger.swift exists in Modules/Foundation/Core/
- [ ] CrashLogger.swift exists in Modules/Foundation/Core/
- [ ] ReLaySettings.swift exists in Modules/Foundation/Core/
- [ ] Imports.swift exists in Modules/Foundation/Core/
- [ ] AccessibilityBootstrap.swift exists in Modules/Foundation/Accessibility/
- [ ] WindowRoleClassifier.swift exists in Modules/Foundation/Accessibility/
- [ ] PersistenceModels.swift exists in Modules/Foundation/Models/
- [ ] WindowLayoutState.swift exists in Modules/Foundation/Models/
- [ ] UIComponentLibrary.swift exists in Modules/Foundation/UI/

### ✓ Input Module
- [ ] Input/Capture/EventTapCapture.swift → Modules/Input/Capture/
- [ ] Input/Core/*.swift → Modules/Input/Core/ (7 files)
- [ ] Input/Dispatch/ActionDispatcher.swift → Modules/Input/Dispatch/
- [ ] Input/Engine/InputGestureEngine.swift → Modules/Input/Engine/
- [ ] Input/Normalize/EventNormalizer.swift → Modules/Input/Normalize/
- [ ] Input/Pipeline/InputPipeline.swift → Modules/Input/Pipeline/
- [ ] Input/Routing/GestureRouter.swift → Modules/Input/Routing/

### ✓ Gesture Module
- [ ] TitleBarInterceptor.swift → Modules/Gesture/
- [ ] GestureEngine.swift → Modules/Gesture/

### ✓ StateManagement Module
- [ ] WindowStateStore.swift → Modules/StateManagement/
- [ ] LayoutHistoryStore.swift → Modules/StateManagement/
- [ ] AppLibraryStore.swift → Modules/StateManagement/
- [ ] PreviewManager.swift → Modules/StateManagement/

### ✓ Layout Module
- [ ] LayoutOrchestrator.swift → Modules/Layout/Application/
- [ ] SpatialTransitionEngine.swift → Modules/Layout/Application/
- [ ] LayoutResolver.swift → Modules/Layout/Resolver/
- [ ] LayoutTemplate.swift → Modules/Layout/Templates/
- [ ] LayoutSuggestionEngine.swift → Modules/Layout/Templates/

### ✓ SpatialEngine Module
- [ ] SpatialEngine/Bridge/ → Modules/SpatialEngine/Bridge/
- [ ] SpatialEngine/Core/ → Modules/SpatialEngine/Core/ (4 files)
- [ ] SpatialEngine/Engine/ → Modules/SpatialEngine/Engine/
- [ ] SpatialEngine/Layout/ → Modules/SpatialEngine/Layout/ (3 files)
- [ ] SpatialEngine/Resolution/ → Modules/SpatialEngine/Resolution/ (3 files)

### ✓ SpatialMemory Module
- [ ] SpatialMemory/Core/ → Modules/SpatialMemory/Core/ (4 files)
- [ ] SpatialMemory/Engine/ → Modules/SpatialMemory/Engine/
- [ ] SpatialMemory/Learning/ → Modules/SpatialMemory/Learning/ (3 files)
- [ ] SpatialMemory/Prediction/ → Modules/SpatialMemory/Prediction/ (3 files)

### ✓ SpatialState Module
- [ ] SpatialState/Core/ → Modules/SpatialState/Core/ (3 files)
- [ ] SpatialState/Engine/ → Modules/SpatialState/Engine/
- [ ] SpatialState/Store/ → Modules/SpatialState/Store/ (2 files)
- [ ] SpatialState/Sync/ → Modules/SpatialState/Sync/ (3 files)
- [ ] SpatialStateCore/SpatialStateReconciler.swift → Modules/SpatialState/Reconciler/

### ✓ WindowEngine Module
- [ ] WindowEngine/Core/ → Modules/WindowEngine/Core/ (3 files)
- [ ] WindowEngine/Engine/ → Modules/WindowEngine/Engine/
- [ ] WindowEngine/Capture/ → Modules/WindowEngine/Capture/ (2 files)
- [ ] WindowEngine/Control/ → Modules/WindowEngine/Control/ (3 files)
- [ ] WindowEngine/Persistence/ → Modules/WindowEngine/Persistence/

### ✓ UI Module
- [ ] LayoutLibraryController.swift → Modules/UI/LibraryPanel/
- [ ] LayoutWorkspaceEditor.swift → Modules/UI/Workspace/

### ✓ Cleanup
- [ ] No .swift files remain at Sources/ReLayCore/ root
- [ ] Old Input/ directory removed
- [ ] Old SpatialEngine/ directory removed
- [ ] Old SpatialMemory/ directory removed
- [ ] Old SpatialState/ directory removed
- [ ] Old SpatialStateCore/ directory removed
- [ ] Old WindowEngine/ directory removed

---

## If Something Goes Wrong

**File not found during move:**
```bash
# Search for the file
find /home/user/ReLay/Sources/ReLayCore -name "FileName.swift"
# If found elsewhere, update this reference
```

**File duplicated:**
```bash
# Check for duplicates
find /home/user/ReLay/Sources/ReLayCore -name "*.swift" | sort | uniq -d
# If found, remove duplicate and keep only new location version
```

**Accidentally moved to wrong directory:**
```bash
# Move it to correct location
mv /home/user/ReLay/Sources/ReLayCore/WrongPath/File.swift \
   /home/user/ReLay/Sources/ReLayCore/CorrectPath/File.swift
```

**Need to restore from git:**
```bash
# Revert last commit (before moves)
git reset --hard HEAD~1
# Then retry carefully
```

---

## Files by Line Count (for planning parallel moves)

Helpful to know which moves are fast/slow:

**Large files (likely to move carefully):**
- LayoutLibraryController.swift (~900 lines)
- LayoutWorkspaceEditor.swift (~600 lines)
- SpatialTransitionEngine.swift (~500 lines)
- TitleBarInterceptor.swift (~400 lines)

**Medium files (majority):**
- Most other files: 50-250 lines

**Small files:**
- Many Core/* files: 20-80 lines

---

This reference is complete and machine-readable. Use it alongside IMPLEMENTATION_QUICK_START.md for execution.
