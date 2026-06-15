# ReLay Modularization - Quick Start Execution Guide

## Overview

This is a quick reference guide to execute the modularization plan. For detailed information, see `MODULARIZATION_PLAN.md`.

---

## Pre-Flight Checklist

```bash
# Verify you're in the right directory
cd /home/user/ReLay
pwd  # Should output /home/user/ReLay

# Check git status is clean
git status  # Should show "nothing to commit"

# Verify Swift build works before starting
swift build 2>&1 | tail -3
# Expected: "Build complete!" or similar

# Count files (baseline)
find Sources/ReLayCore -name "*.swift" | wc -l  # Should be 77
```

---

## Phase-by-Phase Execution

### Phase 1: Create Directory Structure (5 min)

```bash
cd /home/user/ReLay/Sources/ReLayCore

# Create all module directories
mkdir -p GestureCapture/{Input/{Capture,Core,Dispatch,Engine,Normalize,Pipeline,Routing}}
mkdir -p LayoutEngine/{Spatial/{Bridge,Core,Engine,Layout,Resolution},Memory/{Core,Engine,Learning,Prediction},State/{Core,Engine,Store,Sync},Reconciliation}
mkdir -p LayoutOrchestration
mkdir -p LayoutLibrary
mkdir -p Core/Shared/{Models,Types}
mkdir -p SystemIntegration/WindowEngine/{Core,Engine,Capture,Control,Persistence}
mkdir -p Shared/Utilities

# Verify
echo "Directories created:"
ls -d GestureCapture LayoutEngine LayoutOrchestration LayoutLibrary Core SystemIntegration Shared 2>/dev/null | wc -l
# Expected: 7
```

**Verify:**
```bash
git status  # Should show new directories (but no changes yet)
```

**Commit:**
```bash
cd /home/user/ReLay
git add -A
git commit -m "refactor: create module directory structure"
```

---

### Phase 2: Move GestureCapture Files (5 min)

```bash
cd /home/user/ReLay/Sources/ReLayCore

# Root files
mv TitleBarInterceptor.swift GestureCapture/
mv GestureEngine.swift GestureCapture/

# Input subdirectory
mv Input/* GestureCapture/Input/
rmdir Input

# Verify
find GestureCapture -name "*.swift" | wc -l
# Expected: 16 (2 root + 14 in Input)
```

**Verify:**
```bash
ls -la Input 2>&1 | head -1  # Should error: No such file
```

**Commit:**
```bash
cd /home/user/ReLay
git add -A
git commit -m "refactor: move GestureCapture module files"
```

---

### Phase 3: Move Core/Shared Model Files (5 min)

```bash
cd /home/user/ReLay/Sources/ReLayCore

# Move existing models
mv WindowLayoutState.swift Core/Shared/Models/
mv WindowRoleClassifier.swift Core/Shared/Models/

# Create new model files
cat > Core/Shared/Models/WindowRole.swift << 'EOF'
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
EOF

cat > Core/Shared/Models/WindowID.swift << 'EOF'
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
EOF

# Verify
ls Core/Shared/Models/
# Expected: WindowLayoutState.swift, WindowRoleClassifier.swift, WindowRole.swift, WindowID.swift
```

**Commit:**
```bash
cd /home/user/ReLay
git add -A
git commit -m "refactor: create Core/Shared models module"
```

---

### Phase 4: Move SystemIntegration Files (5 min)

```bash
cd /home/user/ReLay/Sources/ReLayCore

# Accessibility bootstrap
mv AccessibilityBootstrap.swift SystemIntegration/

# Window engine
mv WindowEngine/* SystemIntegration/WindowEngine/
rmdir WindowEngine

# Verify
find SystemIntegration -name "*.swift" | wc -l
# Expected: 20
```

**Commit:**
```bash
cd /home/user/ReLay
git add -A
git commit -m "refactor: move SystemIntegration module files"
```

---

### Phase 5: Move LayoutEngine Files (10 min)

```bash
cd /home/user/ReLay/Sources/ReLayCore

# Root layout files
mv LayoutOrchestrator.swift LayoutEngine/
mv SpatialTransitionEngine.swift LayoutEngine/
mv LayoutResolver.swift LayoutEngine/
mv WindowStateStore.swift LayoutEngine/
mv PreviewManager.swift LayoutEngine/

# Spatial modules
mv SpatialEngine/* LayoutEngine/Spatial/
mv SpatialMemory/* LayoutEngine/Memory/
mv SpatialState/* LayoutEngine/State/
mv SpatialStateCore/* LayoutEngine/Reconciliation/

# Clean up old directories
rmdir SpatialEngine SpatialMemory SpatialState SpatialStateCore

# Verify
find LayoutEngine -name "*.swift" | wc -l
# Expected: 44
```

**Commit:**
```bash
cd /home/user/ReLay
git add -A
git commit -m "refactor: move LayoutEngine module files"
```

---

### Phase 6: Move LayoutLibrary Files (2 min)

```bash
cd /home/user/ReLay/Sources/ReLayCore

mv LayoutLibraryController.swift LayoutLibrary/
mv LayoutTemplate.swift LayoutLibrary/
mv LayoutSuggestionEngine.swift LayoutLibrary/
mv LayoutHistoryStore.swift LayoutLibrary/
mv AppLibraryStore.swift LayoutLibrary/
mv LayoutWorkspaceEditor.swift LayoutLibrary/
mv UIComponentLibrary.swift LayoutLibrary/

# Verify
find LayoutLibrary -name "*.swift" | wc -l
# Expected: 7
```

**Commit:**
```bash
cd /home/user/ReLay
git add -A
git commit -m "refactor: move LayoutLibrary module files"
```

---

### Phase 7: Move Shared/Utilities Files (2 min)

```bash
cd /home/user/ReLay/Sources/ReLayCore

mv AppLogger.swift Shared/Utilities/
mv CrashLogger.swift Shared/Utilities/
mv ReLaySettings.swift Shared/Utilities/
mv PersistenceModels.swift Shared/Utilities/
mv Imports.swift Shared/Utilities/

# Verify
find Shared/Utilities -name "*.swift" | wc -l
# Expected: 5
```

**Commit:**
```bash
cd /home/user/ReLay
git add -A
git commit -m "refactor: move Shared/Utilities module files"
```

---

### Phase 8: Build Test & Fix Imports

At this point, files are moved but imports may be broken. Swift will find them anyway since they're in the same target, but good to verify:

```bash
cd /home/user/ReLay

# Build and capture errors
swift build 2>&1 | tee build.log

# Check for errors
if grep -q "error:" build.log; then
    echo "Build errors found:"
    grep "error:" build.log | head -20
else
    echo "✓ Build succeeded!"
fi
```

**If errors:**
- Most will be about undefined types that are actually defined but in a different module directory
- Swift's type resolution should find them automatically since they're all in the same `ReLayCore` target
- If there are genuine import issues, they'll be qualified name issues, not actual missing files

**If no errors, continue to Phase 9.**

---

### Phase 9: Create LayoutOrchestration Controller (5 min)

```bash
cat > /home/user/ReLay/Sources/ReLayCore/LayoutOrchestration/LayoutOrchestrationController.swift << 'EOF'
import Foundation
import Accessibility
import ApplicationServices

/// High-level orchestrator for multi-window layout operations.
/// Wraps SpatialTransitionEngine (semantic state) + LayoutOrchestrator (animation).
public final class LayoutOrchestrationController {
    public static let shared = LayoutOrchestrationController()
    
    private let engine = SpatialTransitionEngine.shared
    private let animator = LayoutOrchestrator.shared
    
    private init() {}
    
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
EOF

cat > /home/user/ReLay/Sources/ReLayCore/LayoutOrchestration/AnimationSequencer.swift << 'EOF'
import Foundation

/// Manages animation timing and sequencing for multi-window operations.
public final class AnimationSequencer {
    public static let shared = AnimationSequencer()
    
    private init() {}
    
    // Placeholder for future animation composition logic
    // Currently, LayoutOrchestrator handles animations directly
}
EOF

echo "✓ LayoutOrchestration controller created"
```

**Commit:**
```bash
cd /home/user/ReLay
git add -A
git commit -m "refactor: create LayoutOrchestration controller module"
```

---

### Phase 10: Create README Files (10 min)

Copy the README templates from MODULARIZATION_PLAN.md to each module:

```bash
cat > /home/user/ReLay/Sources/ReLayCore/GestureCapture/README.md << 'EOF'
# GestureCapture Module

**Ownership:** Input interception & raw gesture detection

## Responsibility

Captures raw input events from macOS title bars and normalizes them into discrete gesture types.

## Public API

- `TitleBarInterceptor` — Main interceptor class
- `GestureEngine` — State machine for gesture recognition
- `InputPipeline.shared` — Start/stop the input pipeline
- `InputGesture` enum — Gesture types

## Dependencies

- Core/Shared
- Shared/Utilities
- SystemIntegration
EOF

# Repeat for other modules... (see MODULARIZATION_PLAN.md for full READMEs)

echo "✓ README files created (create others from MODULARIZATION_PLAN.md)"
```

---

### Phase 11: Final Build Verification

```bash
cd /home/user/ReLay

# Clean and rebuild
rm -rf .build
swift build 2>&1 | tail -5

# Run tests
swift test 2>&1 | tail -10

# Verify file counts
echo "=== File Count Verification ==="
echo -n "GestureCapture: "
find Sources/ReLayCore/GestureCapture -name "*.swift" | wc -l

echo -n "LayoutEngine: "
find Sources/ReLayCore/LayoutEngine -name "*.swift" | wc -l

echo -n "LayoutLibrary: "
find Sources/ReLayCore/LayoutLibrary -name "*.swift" | wc -l

echo -n "Core/Shared: "
find Sources/ReLayCore/Core/Shared -name "*.swift" | wc -l

echo -n "SystemIntegration: "
find Sources/ReLayCore/SystemIntegration -name "*.swift" | wc -l

echo -n "Shared/Utilities: "
find Sources/ReLayCore/Shared/Utilities -name "*.swift" | wc -l

echo -n "LayoutOrchestration: "
find Sources/ReLayCore/LayoutOrchestration -name "*.swift" | wc -l

echo "---"
echo -n "TOTAL: "
find Sources/ReLayCore -name "*.swift" | wc -l
echo "(Expected: 79, includes 2 new files)"
```

**Expected output:**
```
GestureCapture: 16
LayoutEngine: 44
LayoutLibrary: 7
Core/Shared: 4
SystemIntegration: 20
Shared/Utilities: 5
LayoutOrchestration: 2
---
TOTAL: 79
```

---

### Phase 12: Final Commit

```bash
cd /home/user/ReLay

# Create a summary
git log --oneline -12 | head -10

# Final verification
git status  # Should be clean

echo "=== Refactoring Complete ==="
echo "12 phases executed"
echo "Module structure established"
echo "Ready for next iteration!"
```

---

## Troubleshooting

### Build fails with "cannot find type X in scope"

**Cause:** Type defined in another module directory, but Swift can't find it yet.

**Solution:**
1. Verify the file exists in its new location:
   ```bash
   grep -r "class\|struct\|enum.*X" Sources/ReLayCore --include="*.swift" | grep -v ".build"
   ```
2. If found, the issue is usually import path. But since we're in a single target, imports shouldn't be needed.
3. If not found, it means the file wasn't moved correctly.

### Tests fail after reorganization

**Cause:** Test import paths or test structure doesn't match source structure.

**Solution:**
1. Update test imports if they have explicit module paths
2. Mirror source structure in Tests/ReLayCoreTests/

### "Imports.swift" no longer at root

**Cause:** Moved to Shared/Utilities/

**Solution:**
Check if any files import "Imports.swift" directly. Since it's in the same target, cross-module imports aren't needed. If there are explicit imports, remove them.

---

## Verification Checklist

- [ ] Phase 1: Directories created
- [ ] Phase 2: GestureCapture moved (16 files)
- [ ] Phase 3: Core/Shared created (4 files)
- [ ] Phase 4: SystemIntegration moved (20 files)
- [ ] Phase 5: LayoutEngine moved (44 files)
- [ ] Phase 6: LayoutLibrary moved (7 files)
- [ ] Phase 7: Shared/Utilities moved (5 files)
- [ ] Phase 8: Build succeeds
- [ ] Phase 9: LayoutOrchestration created (2 files)
- [ ] Phase 10: README files created
- [ ] Phase 11: Final build & tests pass
- [ ] Phase 12: All commits clean

---

## Time Estimate

- Phases 1-7 (moves): ~30 minutes
- Phase 8 (build fix): ~10 minutes
- Phase 9-11 (finalization): ~20 minutes
- **Total: ~1 hour**

---

## Next Steps After Modularization

1. **Document API surface** — Each module's public types and functions
2. **Add module-level tests** — GestureCapture tests, LayoutEngine tests, etc.
3. **Create module initialization docs** — How each module is initialized
4. **Consider feature flags** — Enable/disable modules at runtime
5. **Plan sub-target extraction** — If needed in future

---

## Questions?

Refer to `MODULARIZATION_PLAN.md` for:
- Detailed module responsibilities
- Dependency diagrams
- Import fix details
- Complete README templates
