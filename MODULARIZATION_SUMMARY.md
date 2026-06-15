# ReLay Modularization - Executive Summary

## What We're Doing

Reorganizing the ReLay codebase from a flat monolithic structure (77 Swift files scattered at root + subdirs) into 10 logical, modular subsystems while maintaining a **single Swift Package target** (ReLayCore). This is pure **structural refactoring**—zero behavioral changes, zero API modifications.

## Why We're Doing It

**Current state problems:**
- Hard to understand which files are related
- No clear ownership or responsibility boundaries
- Difficult to add features without touching multiple unrelated files
- Folder structure doesn't match logical architecture

**Target state benefits:**
- Clear module boundaries (what each module owns)
- Easier to understand information flow
- Faster to locate and modify code
- Preparation for future feature isolation or sub-targeting

## What's Changing

### Before (Flat Monolithic)
```
Sources/ReLayCore/
├── 22 root-level .swift files (mix of everything)
├── Input/ (8 files)
├── SpatialEngine/ (12 files)
├── SpatialMemory/ (11 files)
├── SpatialState/ (8 files)
├── SpatialStateCore/ (1 file)
└── WindowEngine/ (14 files)
```

### After (Modular)
```
Sources/ReLayCore/
└── Modules/
    ├── Foundation/ (5 files: logging, settings, accessibility, models)
    ├── Input/ (8 files: unchanged, just moved)
    ├── Gesture/ (2 files: title bar interception + gesture recognition)
    ├── StateManagement/ (4 files: persistent state, preview, history)
    ├── Layout/ (5 files: templates, resolution, orchestration)
    ├── SpatialEngine/ (12 files: geometry calculations)
    ├── SpatialMemory/ (11 files: pattern learning & prediction)
    ├── SpatialState/ (9 files: system state reconciliation)
    ├── WindowEngine/ (14 files: unchanged, just moved)
    └── UI/ (2 files: library UI, workspace editor)
```

## The 10 Modules Explained

| Module | What It Does | Key Classes | Depends On |
|--------|--------------|-------------|-----------|
| **Foundation** | Core infrastructure: logging, settings, AX permission, window roles | AppLogger, CrashLogger, ReLaySettings, AccessibilityBootstrap | System frameworks only |
| **Input** | Raw event capture → normalization → gesture detection | EventTapCapture, EventNormalizer, InputGestureEngine, GestureRouter | Foundation |
| **Gesture** | Title bar detection + gesture state machine | TitleBarInterceptor, GestureEngine | Foundation + Input |
| **StateManagement** | Persistent state, history, caches, preview overlays | WindowStateStore, LayoutHistoryStore, PreviewManager | Foundation |
| **Layout** | Templates, frame resolution, high-level orchestration | LayoutTemplate, LayoutResolver, SpatialTransitionEngine, LayoutOrchestrator | Foundation + others |
| **SpatialEngine** | Geometric calculations (frames, collisions, stabilization) | SpatialEngine, CollisionResolver, LayoutStabilizer | Foundation |
| **SpatialMemory** | Learn patterns, predict next layout | SpatialMemoryEngine, LayoutPredictor, PatternExtractor | Foundation + SpatialEngine |
| **SpatialState** | Single source of truth; drift detection & reconciliation | SpatialStateCore, DriftDetector, ReconciliationEngine | Foundation + SpatialEngine |
| **WindowEngine** | macOS window control layer (move, resize, query) | WindowEngine, WindowMover, WindowResizer | Foundation |
| **UI** | Library UI, workspace editor | LayoutLibraryController, LayoutWorkspaceEditor | Foundation + others |

## Dependency Graph (No Cycles!)

```
Foundation (leaf)
    ↑
    ├─ Input, SpatialEngine, StateManagement, WindowEngine
    │      ↑
    │      └─ Gesture, Layout
    │             ↑
    │             └─ SpatialMemory, SpatialState
    │                    ↑
    │                    └─ UI
```

**Result:** Pure hierarchical structure, zero circular dependencies.

## How Much Changes?

**Code changes:** ZERO
- No file contents modified
- No class/method signatures changed
- No behavioral changes
- No imports need rewriting (single target)

**File movements:** ALL 77 files
- Move to new module directories
- Create 2 new controller files (LayoutOrchestrationController)
- Create module README files (documentation only)

**Build system:** NO CHANGES
- Package.swift stays exactly the same
- One ReLayCore target (not split into sub-targets)
- ReLay executable unchanged
- Test target unchanged

## Implementation Approach

### Phase 1: Directory Structure (30 min)
Create all module folders, move files physically. **Git commit** this separately.

### Phase 2: Verification (15 min)
Build, test, confirm everything compiles and works.

### Phase 3: Documentation (15 min)
Create README files for each module explaining responsibility and API.

**Total time: ~1 hour**

## Risk Assessment

**Risk level: LOW**

Why?
- No code changes (just file moves)
- Single Swift Package target (imports work automatically)
- Acyclic dependency graph (no circular import risks)
- Build will fail immediately if anything breaks
- Tests verify no behavioral changes

**Rollback:** If needed, `git reset --hard` undoes everything instantly.

## What Stays the Same

✓ Package.swift (unchanged)  
✓ ReLay executable behavior (unchanged)  
✓ ReLayCore target (unchanged)  
✓ Test structure (unchanged)  
✓ API surface (unchanged)  
✓ Performance (unchanged)  
✓ Git history (commits added, never rewritten)  

## Deliverables

Three detailed documents have been created:

1. **MODULARIZATION_PLAN.md** (detailed implementation guide)
   - Complete file mapping (77 files → module homes)
   - Module responsibility matrix
   - Dependency diagrams
   - Step-by-step implementation
   - Build verification checklist

2. **IMPLEMENTATION_QUICK_START.md** (execution checklist)
   - 12 phases with copy-paste bash commands
   - Pre-flight checklist
   - Troubleshooting guide
   - Time estimates

3. **ARCHITECTURE_VISUAL_GUIDE.md** (visual reference)
   - Module organization diagrams
   - Dependency hierarchy
   - Data flow during gesture
   - Public API reference for each module
   - Example feature addition walkthrough

## Next Steps (If Approved)

1. **Review** the three documents above
2. **Execute** IMPLEMENTATION_QUICK_START.md in order
3. **Commit** after each phase
4. **Verify** build and tests pass at each step
5. **Document** any deviations from plan
6. **Celebrate** organized codebase!

## Key Principles Maintained

- **Single Package target:** No split into multiple Package.swift targets (keeps it simple)
- **Structural only:** Folder organization, zero logic changes
- **Clear ownership:** Each module has defined files and responsibilities
- **Acyclic:** No circular dependencies (all imports flow downward)
- **Testable:** Each module can be tested independently
- **Extensible:** Easy to add features to specific modules

## FAQ

**Q: Will this affect the shipped app?**
A: No. This is pure refactoring. The app behavior, performance, and features are identical.

**Q: Can we do this incrementally?**
A: Yes. Phases can be done one per session, with commits between phases. But it's fast enough to do in one go (1 hour).

**Q: What if something breaks?**
A: `git reset --hard` instantly reverts all changes. Plus, the build system will catch errors immediately.

**Q: Do we need to update imports?**
A: No. Single Swift Package target means all Swift files are compiled together. Imports reference type names, not file paths.

**Q: Will this make the codebase slower to compile?**
A: No. Same source files, same compilation process. Actually might be slightly faster due to better module locality in compiler cache.

**Q: Can we split into sub-targets later?**
A: Yes! This organizational structure is perfect prep for future Package.swift sub-target definitions.

## Recommendation

**Proceed with the refactoring.** The structure is solid, risk is low, and the benefits (clarity, maintainability) are substantial. The 1-hour investment will pay off every day when developers work on this codebase.

---

**For detailed information, see:**
- `MODULARIZATION_PLAN.md` — 400+ line detailed guide
- `IMPLEMENTATION_QUICK_START.md` — Copy-paste execution steps
- `ARCHITECTURE_VISUAL_GUIDE.md` — Visual reference and diagrams
