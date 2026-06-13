# ReLay Gesture Testing & Verification Package

**Date**: 2026-06-13  
**Status**: Ready for on-device verification  
**Scope**: Gesture matrix validation + Settings verification

---

## Test Entry Criteria

✅ All tests below assume:
- `swift build` passes (no compile errors)
- `swift test` shows 70+ passing tests, 0 failures
- ReLay is built and ready to run on macOS
- Test device has Accessibility permissions granted
- 5 test apps available: Finder, Safari, Terminal, Xcode, System Settings

---

## Test Suite 1: Gesture Ingress Matrix

**Objective**: Verify 2-finger title-bar drag is recognized and logged correctly in all chrome variants.

### 1.1 Basic Gesture Recognition

| App | Chrome Style | Test | Expected |
|-----|--------------|------|----------|
| **Finder** | Cocoa (tabbed toolbar, window controls) | 2-finger drag on title bar | `title bar hit` logged; gesture begins |
| **Safari** | Cocoa (tabbed toolbar, unified title bar) | 2-finger drag on title bar | `title bar hit` logged; gesture begins |
| **Terminal** | Cocoa (no tabs, simple title bar) | 2-finger drag on title bar | `title bar hit` logged; gesture begins |
| **Xcode** | Custom (top band ~96px, native title bar) | 2-finger drag on title bar | `title bar hit` logged; gesture begins |
| **System Settings** | Native (unified title bar) | 2-finger drag on title bar | `title bar hit` logged; gesture begins |

**How to verify:**
1. Open test app
2. Position app window so gesture space is visible
3. 2-finger tap + drag horizontally on title bar (≥2cm distance)
4. Open ReLay logs: `tail -f /tmp/relay.log` (or equivalent)
5. Look for: `[interceptor] title bar hit gesture=<8char>`

**Pass**: Gesture recognized and logged in ≥4/5 apps  
**Fail**: No log entry or gesture not recognized  

---

### 1.2 Gesture Lifecycle Logging

**Objective**: Verify each gesture phase produces correct log output with matching gesture ID.

**Test procedure:**
1. Open Finder
2. Perform 2-finger title-bar drag left (≥2cm)
3. Collect logs (all lines with same `gesture=<id>`)
4. Verify sequence

**Expected log output for one complete gesture:**
```
[timestamp] [interceptor] title bar hit gesture=a3f82c1b ...
[timestamp] [gesture]     gesture began gesture=a3f82c1b fingerCount=2 ...
[timestamp] [transition]  gesture request gesture=a3f82c1b ...
[timestamp] [transition]  state transition gesture=a3f82c1b floating -> leftHalf
[timestamp] [transition]  layout resolution gesture=a3f82c1b state=leftHalf
[timestamp] [gesture]     gesture committed gesture=a3f82c1b ...
```

**Pass**: All 6 lines present with same gesture ID  
**Fail**: Missing lines, mismatched IDs, or wrong state  

---

### 1.3 Left / Right Snap

**Objective**: Verify left and right title-bar swipes resolve to correct layout states.

**Test procedure:**
1. Open Finder
2. 2-finger drag **left** on title bar (≥2cm, fast)
3. Observe: window should snap to left half of screen
4. Repeat with **right** drag

**Expected**:
- Left drag → window moves to left 50% of screen
- Right drag → window moves to right 50% of screen
- Logs show `state transition ... -> leftHalf` / `... -> rightHalf`

**Pass**: Both snaps work correctly  
**Fail**: Wrong snap target or no motion  

---

### 1.4 Center Snap (if enabled)

**Objective**: Verify center snap works when `centerSnapEnabled = true`.

**Test procedure:**
1. Open Settings (ReLay menu → Preferences)
2. Enable "Center Snap" toggle
3. Open Finder
4. 2-finger drag **up** on title bar
5. Observe window motion

**Expected (centerSnap=false)**: Drag up → halves scroll or no effect  
**Expected (centerSnap=true)**: Drag up → window centers on screen  
**Log**: `state transition ... -> center`

**Pass**: Center snap activates when enabled, disabled when off  
**Fail**: No change or wrong target state  

---

### 1.5 Multi-Gesture Sequence

**Objective**: Verify consecutive gestures have different IDs and don't interfere.

**Test procedure:**
1. Open Finder
2. Perform gesture #1: 2-finger drag left
3. Wait for snap to complete
4. Perform gesture #2: 2-finger drag right
5. Collect all logs
6. Verify gesture IDs differ

**Expected**:
- Gesture #1 logs: `gesture=a3f82c1b`
- Gesture #2 logs: `gesture=f7c2e0d9` (different)
- Window state clean between gestures

**Pass**: Different gesture IDs, both complete, no state bleed  
**Fail**: Same ID used, state confusion, or missed gesture  

---

## Test Suite 2: Settings Verification

**Objective**: Verify all new settings wire through to runtime behavior.

### 2.1 Snap Speed Slider

**Test procedure:**
1. Open Settings → Feel & Motion section
2. Move "Snap Speed" slider to **Instant** (left)
3. Snap a window (title-bar drag)
4. Observe snap animation duration
5. Repeat with **Smooth** (right)

**Expected**:
- Instant: snap completes in ~0.08s
- Smooth: snap completes in ~0.45s

**Pass**: Slider affects animation duration  
**Fail**: No visual difference or crash  

---

### 2.2 Snap Haptics Toggle

**Test procedure:**
1. Open Settings → Feel & Motion section
2. Toggle "Snap Haptics" on/off
3. Perform 2-finger snap
4. Feel device haptic feedback

**Expected**:
- When enabled: tactile feedback on snap start
- When disabled: no haptic feedback

**Pass**: Haptics respond to toggle  
**Fail**: Always haptic or never haptic  

---

### 2.3 Feel Presets

**Test procedure:**
1. Open Settings
2. Click "Careful" preset
3. Observe all five sliders move to Careful values
4. Snap a window and observe feel
5. Click "Balanced" and "Snappy" presets
6. Repeat snaps

**Expected**:
- Each preset moves all sliders in unison
- Snappy = faster, more responsive
- Careful = slower, deliberate
- Balanced = middle ground

**Pass**: Presets apply; feel noticeably different  
**Fail**: Sliders don't move or no observable change  

---

### 2.4 Swipe Actions (Up/Down)

**Test procedure:**
1. Open Settings → Swipe Actions
2. Set Up-Swipe to "Center"
3. Set Down-Swipe to "Minimize"
4. Snap window to a half state
5. Perform **up** swipe on title bar → window should center
6. Perform **down** swipe on title bar → window should minimize

**Expected**:
- Up swipe respects the "Center" action
- Down swipe respects the "Minimize" action

**Pass**: Both swipe directions execute correct actions  
**Fail**: Wrong action or no response  

---

## Test Suite 3: Layout Library Verification

**Objective**: Verify library UI is responsive and drag-drop works correctly.

### 3.1 Template Selection & Preview

**Test procedure:**
1. Press modifier + L (or ReLay menu → Layout Library)
2. Observe Library window appears, centered
3. Click on "Split" template card
4. Observe canvas updates to show split layout
5. Repeat with "Thirds" and "Grid 4"

**Expected**:
- Library appears within 300ms
- Template card highlights on selection
- Canvas shows correct slot arrangement
- Smooth animation between templates

**Pass**: All templates selectable and preview correct  
**Fail**: Library doesn't appear, crashes, or wrong preview  

---

### 3.2 Drag-Drop App Assignment

**Test procedure:**
1. Open Layout Library
2. Select "Split" template
3. Drag Safari from dock to left slot
4. Drag Finder from dock to right slot
5. Click "Apply Layout"
6. Observe both apps snap to assigned slots

**Expected**:
- Apps highlight slots on drag-over
- Apps assign to slots on drop
- "Apply Layout" snaps both apps instantly

**Pass**: Drag-drop works; windows snap correctly  
**Fail**: Apps don't drag, don't drop, or don't snap  

---

### 3.3 Save & Restore Custom Layout

**Test procedure:**
1. Open Layout Library
2. Assign Safari → left, Finder → right
3. Click "Save…" button
4. Name layout "Test Layout"
5. Confirm save
6. Close Library
7. Snap windows to different positions
8. Open Layout Library again
9. Click on "Test Layout" in template strip

**Expected**:
- Layout saves with custom name
- Layout appears in template strip with bookmark icon
- Clicking saved layout reassigns slots
- "Apply Layout" activates saved configuration

**Pass**: Save, restore, and reapply work  
**Fail**: Save fails, layout doesn't persist, or reapply doesn't work  

---

## Test Suite 4: Edge Cases & Robustness

### 4.1 Minimized Window Behavior

**Test procedure:**
1. Open Finder, minimize window
2. Snap another window (title-bar drag)
3. Verify minimized window is skipped

**Expected**: Snap works; minimized window unchanged  

---

### 4.2 Hidden Application Behavior

**Test procedure:**
1. Open Safari, hide it (Cmd+H)
2. Try to snap Finder (title-bar drag)
3. Verify hidden app doesn't interfere

**Expected**: Snap works; hidden apps excluded from candidates  

---

### 4.3 Rapid Consecutive Gestures

**Test procedure:**
1. Open Finder
2. Perform 3 title-bar snaps in rapid succession (1sec apart)
3. Verify each gesture completes cleanly
4. Check logs for correct gesture IDs

**Expected**: All 3 gestures complete; different gesture IDs  

---

### 4.4 Library Dismiss on Escape

**Test procedure:**
1. Open Layout Library
2. Press Escape key
3. Verify Library closes smoothly

**Expected**: Library closes with fade-out animation  

---

## Verification Checklist

After running all tests, verify:

- [ ] Gesture matrix: ≥4/5 apps recognize 2-finger title-bar drag
- [ ] Logging: All gestures produce complete, matching-ID log sequences
- [ ] Left/Right snap: Both directions work on ≥3 apps
- [ ] Center snap: Toggles on/off correctly
- [ ] Multi-gesture: Different IDs, no state interference
- [ ] Snap Speed: Slider adjusts animation duration visibly
- [ ] Snap Haptics: Toggle affects feedback presence
- [ ] Feel Presets: All three presets apply; feel differs
- [ ] Swipe Actions: Up/down perform assigned actions
- [ ] Library UI: Opens, templates selectable, canvas updates
- [ ] Drag-drop: Apps assign to slots, apply snaps correctly
- [ ] Save/Restore: Custom layouts persist and reapply
- [ ] Edge cases: Minimized/hidden apps handled; rapid gestures OK
- [ ] No crashes: Full session without exceptions
- [ ] Logs clean: No orphaned or malformed gesture IDs

---

## Known Issues & Workarounds

### Xcode topBand geometry (potential)
If title-bar hits miss on Xcode at high resolutions, topBand may need bumping from 88px to 96px.  
**Workaround**: Test on 1080p and 1440p displays.

### Center snap tests
`centerSnap=true` graph tests not yet in suite.  
**Status**: Can be added post-device-verification if behavior is correct.

---

## Logging Setup

To collect gesture logs during testing:

```bash
# Terminal 1: tail live logs
log stream --predicate 'processImagePath contains[cd] "ReLay"' --level debug

# Terminal 2: or check file logs
tail -f /tmp/relay.log
```

---

## Sign-off

**Date Tested**: ___________  
**Tester**: ___________  
**Device**: ___________  
**OS Version**: ___________  

**All tests passed**: ☐ Yes ☐ No  
**Issues found**: 

---

**Next**: If all tests pass, freeze gesture pipeline. If issues found, diagnose and iterate.

