# SessionID Tracking Implementation Plan

## Quick Start: Implementation Order

1. **AppLogger.swift** - Add helper function
2. **TitleBarInterceptorDelegate** - Update protocol signatures
3. **TitleBarInterceptor.swift** - Generate SessionID
4. **GestureEngine.swift** - Store and forward
5. **SpatialTransitionEngine.swift** - Distribute to all downstream
6. **PreviewManager.swift** - Accept parameter
7. **LayoutOrchestrator.swift** - Accept parameter
8. **WindowStateStore.swift** - Add to logs

---

## PHASE 1: SessionID Implementation

### Step 1.1: AppLogger.swift
Add new logging helper that formats `[sid=xxxxxxxx]`:

```swift
public static func log(_ message: String, sessionID: String, subsystem: String) {
    let timestamp = formatter.string(from: Date())
    let line = "[\(timestamp)] [\(subsystem)] [sid=\(sessionID)] \(message)\n"
    FileHandle.standardOutput.write(Data(line.utf8))
}
```

**Checklist:**
- [ ] New function added
- [ ] Format includes `[sid=\(sessionID)]`
- [ ] Existing `log(_:subsystem:)` unchanged

---

### Step 1.2: TitleBarInterceptor Protocol
Update all delegate methods to include `sessionID: String` parameter:

```swift
protocol TitleBarInterceptorDelegate: AnyObject {
    func gestureDidBegin(on window: AXUIElement, at location: CGPoint, fingerCount: Int, sessionID: String)
    func gestureDidChange(deltaX: CGFloat, deltaY: CGFloat, velocity: CGFloat, sessionID: String)
    func gestureDidEnd(sessionID: String)
    func gestureDidCancel(sessionID: String)
    func gestureDidDoubleTap(on window: AXUIElement, sessionID: String)
}
```

**Checklist:**
- [ ] 5 methods updated
- [ ] Parameter name is `sessionID`
- [ ] Type is `String`

---

### Step 1.3: TitleBarInterceptor Implementation
Generate and thread SessionID through gesture lifetime:

**Instance variable to add:**
```swift
private var activeSessionID: String?
```

**In `handleEvent()` at phase == .began (around line 214):**
```swift
if phase == .began {
    // After title bar hit confirmation
    let sessionID = UUID().uuidString.prefix(8).lowercased()
    self.activeSessionID = sessionID
    delegate?.gestureDidBegin(on: window, at: location, fingerCount: lastKnownTouchCount, sessionID: sessionID)
}
```

**Update all delegate calls:**
- Line ~222: Pass `sessionID: activeSessionID!` to `gestureDidBegin()`
- Line ~239: Pass `sessionID: activeSessionID!` to `gestureDidChange()`
- Line ~246-250: Pass `sessionID: activeSessionID!` to `gestureDidEnd()` or `gestureDidCancel()`

**In `resetState()` (line 558):**
```swift
activeSessionID = nil
```

**Checklist:**
- [ ] Instance variable `activeSessionID: String?` added
- [ ] SessionID generated as `UUID().prefix(8).lowercased()`
- [ ] All 5 delegate calls receive sessionID parameter
- [ ] Cleared in resetState()

---

### Step 1.4: GestureEngine
Store and forward SessionID to SpatialTransitionEngine:

**Instance variable to add:**
```swift
private var currentSessionID: String?
```

**In each delegate method signature:**
```swift
public func gestureDidBegin(on window: AXUIElement, at location: CGPoint, fingerCount: Int, sessionID: String) {
    // ... existing code ...
    self.currentSessionID = sessionID
    AppLogger.log("gesture began fingers=\(fingerCount)", sessionID: sessionID, subsystem: "gesture")
    SpatialTransitionEngine.shared.beginSession(window: window, fingerCount: fingerCount, at: location, sessionID: sessionID)
}
```

**Update method signatures:**
- `gestureDidBegin()` - add `sessionID: String`, store it
- `gestureDidChange()` - add `sessionID: String`, forward it
- `gestureDidEnd()` - add `sessionID: String`, forward it
- `gestureDidCancel()` - add `sessionID: String`, forward it
- `gestureDidDoubleTap()` - add `sessionID: String`

**Forward to SpatialTransitionEngine:**
- Line 40: `SpatialTransitionEngine.shared.beginSession(..., sessionID: sessionID)`
- Line 76-80: `SpatialTransitionEngine.shared.updatePreview(..., sessionID: sessionID)`
- Line 118: `SpatialTransitionEngine.shared.cancelSession(sessionID: sessionID)`
- Line 132-137: `SpatialTransitionEngine.shared.commitSession(..., sessionID: sessionID)`

**Update AppLogger calls:**
- All existing `AppLogger.log()` calls change to `AppLogger.log(..., sessionID: currentSessionID ?? "none", ...)`

**In resetState():**
```swift
currentSessionID = nil
```

**Checklist:**
- [ ] Instance variable added
- [ ] All delegate method signatures updated
- [ ] All SpatialTransitionEngine calls include sessionID parameter
- [ ] All AppLogger calls updated
- [ ] Cleared in resetState()

---

### Step 1.5: SpatialTransitionEngine
Central hub—store and distribute to all downstream:

**Instance variable to add:**
```swift
private var activeSessionID: String?
```

**Update method signatures:**
```swift
func beginSession(window: AXUIElement, fingerCount: Int, at location: CGPoint, sessionID: String)
func updatePreview(effectiveX: CGFloat, effectiveY: CGFloat, progress: CGFloat, sessionID: String)
func commitSession(effectiveX: CGFloat, effectiveY: CGFloat, fingerCount: Int, at location: CGPoint, sessionID: String)
func cancelSession(sessionID: String)
```

**In `beginSession()` (line 37):**
```swift
func beginSession(window: AXUIElement, fingerCount: Int, at location: CGPoint, sessionID: String) {
    self.activeSessionID = sessionID
    AppLogger.log("session begin fingers=\(fingerCount)", sessionID: sessionID, subsystem: "transition")
    // ... rest of existing code ...
}
```

**Forward to PreviewManager:**
- Line 62, 75: `PreviewManager.shared.updateOverlay(..., sessionID: sessionID)`
- Line 150, 167, 190, 207, 231: `PreviewManager.shared.commitOverlay(..., sessionID: sessionID)` or `dismiss(..., sessionID: sessionID)`

**Forward to LayoutOrchestrator:**
- Line 118, 151, 168, 189, 206, 224: `animator.animateWindowFrame(..., sessionID: sessionID)` / `animator.tileWindows(..., sessionID: sessionID)`

**Update all AppLogger calls** to use `sessionID: activeSessionID ?? "orphaned"`

**In `clearSession()` (line 252):**
```swift
activeSessionID = nil
```

**Checklist:**
- [ ] Instance variable added
- [ ] 4 public method signatures updated with sessionID parameter
- [ ] sessionID stored in beginSession()
- [ ] sessionID forwarded to all PreviewManager calls
- [ ] sessionID forwarded to all LayoutOrchestrator calls
- [ ] All AppLogger calls updated
- [ ] Cleared in clearSession()

---

### Step 1.6: PreviewManager
Accept SessionID parameter (for tracing):

**Update method signatures:**
```swift
func updateOverlay(currentFrame: CGRect, targetFrame: CGRect, progress: CGFloat, sessionID: String)
func commitOverlay(finalFrame: CGRect, sessionID: String)
func dismiss(animated: Bool, sessionID: String)
```

**Checklist:**
- [ ] 3 method signatures updated
- [ ] Parameter type is `String`
- [ ] No other changes needed (no logging required at this layer unless debugging)

---

### Step 1.7: LayoutOrchestrator
Accept SessionID parameter (for tracing):

**Update method signatures:**
```swift
func tileWindows(_ windows: [AXUIElement], in screen: CGRect, columns: Int? = nil, gap: CGFloat = 2, sessionID: String)
func animateWindowFrame(_ window: AXUIElement, to frame: CGRect, duration: CGFloat = 0.220, sessionID: String)
```

**Checklist:**
- [ ] 2+ method signatures updated with sessionID parameter
- [ ] All internal calls to `animateWindowFrame()` forward sessionID
- [ ] Optional: Add logging for animation start/end with sessionID

---

### Step 1.8: WindowStateStore
Add SessionID to state transition logging:

**Update method signatures (optional):**
```swift
func setRecord(_ record: WindowRecord, for window: AXUIElement, sessionID: String? = nil)
func updateState(_ state: WindowLayoutState, for window: AXUIElement, sessionID: String? = nil)
```

**Update AppLogger calls (lines 67, 70, 79):**
```swift
if let sessionID = sessionID {
    AppLogger.log("state transition \(previousState) -> \(currentState)", sessionID: sessionID, subsystem: "state")
} else {
    AppLogger.log("state transition \(previousState) -> \(currentState)", subsystem: "state")
}
```

**Checklist:**
- [ ] Method signatures updated with optional sessionID parameter
- [ ] AppLogger calls conditional on sessionID presence
- [ ] Backward compatible (old callers without sessionID still work)

---

## PHASE 2-6: Testing & Validation

See detailed plan sections for:
- Phase 2: End-to-End Integration Verification
- Phase 3: Unit Testing (test fixtures, SessionID format, threading)
- Phase 4: Integration Testing (gesture flows, edge cases, multi-gesture)
- Phase 5: Build & Manual Testing
- Phase 6: Pre-Human-Testing Checklist

---

## Key Implementation Notes

### SessionID Format
- 8 characters, lowercase hex
- Generated: `UUID().uuidString.prefix(8).lowercased()`
- Example: `a1b2c3d4`, `f0e1d2c3`

### Log Format
```
[2026-05-19T10:30:45.123Z] [subsystem] [sid=xxxxxxxx] message
```

### ThreadFlow
```
TitleBarInterceptor (GENERATE sid)
    ↓ gestureDidBegin(sid)
GestureEngine (STORE sid)
    ↓ beginSession(sid)
SpatialTransitionEngine (DISTRIBUTE sid)
    ├↓ updateOverlay(sid)
    │  PreviewManager
    │  
    ├↓ commitSession(sid)
    ├↓ animateWindowFrame(sid)
    └↓ tileWindows(sid)
    LayoutOrchestrator
```

### Error Handling
- If sessionID is somehow nil, log with "orphaned" or skip SessionID in logs
- Bootstrap logs (before gesture starts) should NOT include SessionID
- All gesture-related logs MUST include SessionID

---

## Files to Modify (in order)

1. `Sources/ReLayCore/AppLogger.swift` ← New helper function
2. `Sources/ReLayCore/TitleBarInterceptor.swift` ← Protocol + implementation
3. `Sources/ReLayCore/GestureEngine.swift` ← Receive + forward
4. `Sources/ReLayCore/SpatialTransitionEngine.swift` ← Central hub
5. `Sources/ReLayCore/PreviewManager.swift` ← Accept parameter
6. `Sources/ReLayCore/LayoutOrchestrator.swift` ← Accept parameter
7. `Sources/ReLayCore/WindowStateStore.swift` ← Optional: add to logs

---

## Validation Checklist

After implementation:

- [ ] `swift build` compiles without errors
- [ ] `swift build` compiles without warnings
- [ ] `swift test` passes all unit tests
- [ ] Manual test: single 2-finger gesture produces logs with `[sid=xxxxxxxx]`
- [ ] Manual test: two consecutive gestures have different SessionIDs
- [ ] Manual test: all logs in a single gesture have the same SessionID
- [ ] Code review: all method signatures match between caller and callee
- [ ] Code review: no "orphaned" log calls missing sessionID
- [ ] Documentation: example log output provided

