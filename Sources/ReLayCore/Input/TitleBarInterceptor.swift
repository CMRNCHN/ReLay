import Cocoa
import ApplicationServices
import Accessibility

/// Delegate protocol to pass clean gesture lifecycle events to the Gesture Engine.
public protocol TitleBarInterceptorDelegate: AnyObject {
    func gestureDidBegin(on window: AXUIElement, at location: CGPoint, fingerCount: Int, shiftHeld: Bool, gestureID: UUID, sessionID: String)
    func gestureDidChange(deltaX: CGFloat, deltaY: CGFloat, velocity: CGFloat, sessionID: String)
    func gestureDidEnd(sessionID: String)
    func gestureDidCancel(sessionID: String)
    func gestureDidDoubleTap(on window: AXUIElement)
    func killSwitchTriggered()
}

public final class TitleBarInterceptor {
    private enum HitQualification {
        case accepted(String)
        case semanticMiss(String)
        case geometricMiss(String)
    }

    private struct ChromeSignals {
        let hitRole: String
        let hitSubrole: String
        let ancestryRoles: [String]
        let windowChildRoles: Set<String>

        var hasTabGroup: Bool {
            ancestryRoles.contains("AXTabGroup") || windowChildRoles.contains("AXTabGroup")
        }

        var hasToolbar: Bool {
            ancestryRoles.contains("AXToolbar") || windowChildRoles.contains("AXToolbar")
        }

        var hasContentOwnership: Bool {
            ancestryRoles.contains(where: Self.contentRoles.contains)
        }

        var allowsNormalizedTopBandOwnership: Bool {
            if hasContentOwnership {
                return false
            }
            if hasTabGroup || hasToolbar {
                return true
            }
            return ancestryRoles.contains(where: Self.chromeRoles.contains)
        }

        var variant: String {
            if hasTabGroup && hasToolbar {
                return "tabbed-toolbar"   // Safari, Chrome, Xcode — combined tab strip + nav bar
            }
            if hasTabGroup {
                return "tabbed"           // Terminal, plain tab bars
            }
            if hasToolbar && windowChildRoles.contains("AXGroup") {
                return "blended-toolbar"
            }
            if hasToolbar {
                return "unified-toolbar"
            }
            if ancestryRoles.contains("AXTitleBar") {
                return "standard-titlebar"
            }
            if hasContentOwnership {
                return "content-owned"
            }
            return "undifferentiated"
        }

        var topBandHeight: CGFloat {
            if hasTabGroup && hasToolbar {
                return 80.0 // combined tab strip + navigation toolbar (Safari, Chrome, Xcode)
            }
            if hasTabGroup {
                return 44.0 // tab strip only (Terminal)
            }
            if hasToolbar {
                return 80.0 // toolbar + title (Finder)
            }
            return 40.0 // standard title bar (TextEdit, Settings)
        }

        private static let chromeRoles: Set<String> = [
            "AXTitleBar",
            "AXToolbar",
            "AXTabGroup",
            "AXButton",
            "AXStaticText",
            "AXGroup"
        ]

        private static let contentRoles: Set<String> = [
            "AXWebArea",
            "AXScrollArea",
            "AXOutline",
            "AXTable",
            "AXRow",
            "AXCell",
            "AXTextArea",
            "AXTextField",
            "AXCollectionView",
            "AXList",
            "AXSplitGroup"
        ]
    }

    private struct WindowContextResolution {
        let window: AXUIElement?
        let semanticTitleSource: String?
        let hitRole: String
        let hitSubrole: String
    }
    
    public weak var delegate: TitleBarInterceptorDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var gestureMonitor: Any?

    // State Tracking
    private var isTrackingGesture = false
    private var activeTargetWindow: AXUIElement?
    private var lastKnownTouchCount: Int = 2
    private var isTracking3Finger = false
    private var accumulated3FingerY: CGFloat = 0
    private var pendingGestureID: UUID = UUID()

    // Configuration
    public init() {}
    
    /// Starts intercepting global mouse events
    public func start() throws {
        AppLogger.log("starting event tap setup", subsystem: "interceptor")
        let eventMask = (1 << CGEventType.scrollWheel.rawValue) | 
                         (1 << CGEventType.leftMouseDown.rawValue) |
                         (1 << CGEventType.keyDown.rawValue)
        
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let interceptor = Unmanaged<TitleBarInterceptor>.fromOpaque(refcon).takeUnretainedValue()
                return interceptor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        )
        
        guard let eventTap = eventTap else {
            AppLogger.log("failed to create event tap", subsystem: "interceptor")
            throw InterceptorError.failedToCreateEventTap
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        AppLogger.log("event tap enabled", subsystem: "interceptor")

        // Secondary monitor: gesture events (type 29) expose touch count via NSTouch
        gestureMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: NSEvent.EventTypeMask(rawValue: 1 << 29)
        ) { [weak self] event in
            let count = event.touches(matching: .touching, in: nil).count
            // Always update (including count==0) so stale 3-finger count doesn't bleed
            // into the next gesture (e.g. after 3-finger expose → 2-finger title-bar swipe).
            self?.lastKnownTouchCount = count > 0 ? count : 2
            if count > 0 {
                AppLogger.log("touch count observed count=\(count)", subsystem: "interceptor")
            }
        }
        AppLogger.log("gesture monitor installed", subsystem: "interceptor")
    }
    
    /// Stops the global event tap
    public func stop() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let runLoopSource = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
        }
        if let monitor = gestureMonitor {
            NSEvent.removeMonitor(monitor)
            gestureMonitor = nil
        }
        resetState()
    }
    
    
    private func getFrontmostWindow() -> AXUIElement? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &ref) == .success {
            return (ref as! AXUIElement)
        }
        // Fallback to the first window in the windows list
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
           let list = ref as? [AXUIElement], !list.isEmpty {
            return list[0]
        }
        return nil
    }

    /// Main callback handler for intercepted events
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // CGEvent.location is in screen coordinates (top-left is 0,0). 
        // We use it directly for AXUIElementCopyElementAtPosition which expects the same.
        // let location = event.location
        // AppLogger.log("interceptor event location=\(Int(location.x)),\(Int(location.y))", subsystem: "interceptor")
        // Re-enable event tap if the system disabled it due to timeout or user input.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            AppLogger.log("event tap re-enabled after system disable", subsystem: "interceptor")
            return Unmanaged.passUnretained(event)
        }

        // Handle Global Shortcut (Control + Option + Space)
        if type == .keyDown {
            if let nsEvent = NSEvent(cgEvent: event) {
                let modifiers = nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let keyCode  = nsEvent.keyCode

                // Route navigation keys to expose while it is open (swallows them)
                if LayoutLibraryController.shared.isPresented {
                    switch keyCode {
                    case 53, 36, 76, 123, 124, 125, 126:
                        let code = keyCode
                        DispatchQueue.main.async {
                            LayoutLibraryController.shared.handleKeyCode(code)
                        }
                        return nil // Swallow
                    default:
                        break
                    }
                }

                // Global shortcut: Ctrl+Option+Space opens Layout Exposé
                if modifiers == [.control, .option] && keyCode == 49 {
                    DispatchQueue.main.async {
                        LayoutLibraryController.shared.present(triggerWindow: self.getFrontmostWindow())
                    }
                    return nil // Swallow
                }

                // Shuffle layout slots: Ctrl+Option+Tab
                if modifiers == [.control, .option] && keyCode == 48 {
                    DispatchQueue.main.async {
                        SpatialTransitionEngine.shared.shuffleExposeLayout()
                    }
                    return nil
                }

                // Emergency Kill Switch (Cmd + Shift + Escape)
                if modifiers == [.command, .shift] && keyCode == 53 {
                    AppLogger.log("emergency kill-switch triggered via keyboard", subsystem: "interceptor")
                    delegate?.killSwitchTriggered()
                    return nil // Swallow to prevent system seeing it
                }
            }
            return Unmanaged.passUnretained(event)
        }

        // Handle Double Tap (Left Mouse Down with clickCount == 2)
        if type == .leftMouseDown {
            if let nsEvent = NSEvent(cgEvent: event), nsEvent.clickCount == 2 {
                let location = event.location
                if let window = hitTestTitleBar(at: location) {
                    let sessionID = UUID().uuidString.prefix(8).lowercased()
                    delegate?.gestureDidDoubleTap(on: window, sessionID: sessionID)
                    return nil // Swallow the double click to override macOS default behavior
                }
            }
            return Unmanaged.passUnretained(event)
        }
        
        guard type == .scrollWheel, let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }
        
        let phase = nsEvent.phase
        let momentumPhase = nsEvent.momentumPhase
        
        // Phase: Began (Start of a physical gesture)
        if phase == .began {
            AppLogger.log("scroll phase began", subsystem: "interceptor")
            let location = event.location
            let fingerCount = lastKnownTouchCount
            // Fresh UUID for every potential gesture — assigned before hit-test so all
            // log lines from this interaction share the same prefix whether accepted or missed.
            pendingGestureID = UUID()

            if let window = hitTestTitleBar(at: location) {
                let sessionID = UUID().uuidString.prefix(8).lowercased()
                self.activeSessionID = sessionID
                isTrackingGesture = true
                activeTargetWindow = window
                let shiftHeld = NSEvent.modifierFlags.contains(.shift)
                AppLogger.log("title bar hit; beginning gesture tracking fingers=\(lastKnownTouchCount) shift=\(shiftHeld) gesture=\(pendingGestureID.uuidString.prefix(8))", subsystem: "interceptor")
                delegate?.gestureDidBegin(on: window, at: location, fingerCount: lastKnownTouchCount, shiftHeld: shiftHeld, gestureID: pendingGestureID, sessionID: sessionID)
                
                // Swallow the event to prevent underlying scroll
                return nil
            } else {
                AppLogger.log("scroll began outside title bar hit region", subsystem: "interceptor")
                // 3-finger gestures trigger expose from anywhere on screen
                if fingerCount >= 3 {
                    isTracking3Finger = true
                    accumulated3FingerY = 0
                    return nil
                }
            }
        }

        // Handle 3-finger global tracking (non-title-bar areas)
        if isTracking3Finger {
            if phase == .changed {
                accumulated3FingerY += nsEvent.scrollingDeltaY
                return nil
            }
            if phase == .ended || phase == .cancelled || momentumPhase == .began {
                let y = accumulated3FingerY
                isTracking3Finger = false
                accumulated3FingerY = 0
                if y < -50 {
                    AppLogger.log("3-finger swipe down detected; presenting expose", subsystem: "interceptor")
                    DispatchQueue.main.async {
                        LayoutLibraryController.shared.present(triggerWindow: self.getFrontmostWindow())
                    }
                }
                return nil
            }
            return nil // Swallow any other event while tracking
        }

        // Phase: Changed (Physical finger movement)
        if phase == .changed && isTrackingGesture, let sessionID = activeSessionID {
            // Calculate velocity approximation (pixels per second based on standard 60hz scroll polling)
            let deltaX = nsEvent.scrollingDeltaX
            let deltaY = nsEvent.scrollingDeltaY
            let velocity = sqrt(deltaX * deltaX + deltaY * deltaY) * 60.0 
            
            AppLogger.log("scroll phase changed while tracking gesture=\(pendingGestureID.uuidString.prefix(8))", subsystem: "interceptor")
            delegate?.gestureDidChange(deltaX: deltaX, deltaY: deltaY, velocity: velocity)
            return nil // Swallow event
        }

        // Phase: Ended or Cancelled
        if (phase == .ended || phase == .cancelled || momentumPhase == .began) && isTrackingGesture {
            AppLogger.log("scroll gesture finished gesture=\(pendingGestureID.uuidString.prefix(8)) phase=\(phase.rawValue) momentum=\(momentumPhase.rawValue)", subsystem: "interceptor")
            if phase == .cancelled {
                delegate?.gestureDidCancel(sessionID: sessionID)
            } else {
                delegate?.gestureDidEnd(sessionID: sessionID)
            }
            resetState()
            return nil // Swallow final event
        }
        
        // If we are actively tracking, swallow all intermediate momentum/unphased events
        if isTrackingGesture {
            return nil
        }
        
        // Let standard events flow through to macOS
        return Unmanaged.passUnretained(event)
    }
    
    /// Uses AX APIs to determine if the given screen coordinate is over a window's title bar.
    private func hitTestTitleBar(at point: CGPoint) -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(systemWideElement, Float(point.x), Float(point.y), &element)
        
        guard error == .success, let hitElement = element else {
            AppLogger.log("ax hit test failed point=(\(Int(point.x)),\(Int(point.y))) error=\(error.rawValue)", subsystem: "interceptor")
            return nil
        }
        
        let resolution = resolveWindowContext(for: hitElement)

        guard let window = resolution.window else {
            AppLogger.log(
                "semantic miss reason=no-parent-window point=(\(Int(point.x)),\(Int(point.y))) role=\(resolution.hitRole) subrole=\(resolution.hitSubrole)",
                subsystem: "interceptor"
            )
            return nil
        }

        let owner    = appName(for: window)
        let bundleId = bundleID(for: window)
        let signals  = chromeSignals(for: hitElement, window: window)

        let qualification = qualifyHit(
            at: point,
            window: window,
            semanticSource: resolution.semanticTitleSource,
            signals: signals
        )

        switch qualification {
        case .accepted(let reason):
            // pendingGestureID was already set fresh at scroll-began; just log it.
            AppLogger.log(
                "title bar hit gesture=\(pendingGestureID.uuidString.prefix(8)) app=\(owner) bundle=\(bundleId) variant=\(signals.variant) topBand=\(Int(signals.topBandHeight)) hitRole=\(signals.hitRole) via \(reason)",
                subsystem: "interceptor"
            )
            return window
        case .semanticMiss(let reason):
            AppLogger.log(
                "semantic miss app=\(owner) bundle=\(bundleId) variant=\(signals.variant) topBand=\(Int(signals.topBandHeight)) hitRole=\(signals.hitRole) subrole=\(signals.hitSubrole) reason=\(reason)",
                subsystem: "interceptor"
            )
            return nil
        case .geometricMiss(let reason):
            AppLogger.log(
                "geometric miss app=\(owner) bundle=\(bundleId) variant=\(signals.variant) topBand=\(Int(signals.topBandHeight)) hitRole=\(signals.hitRole) subrole=\(signals.hitSubrole) reason=\(reason)",
                subsystem: "interceptor"
            )
            return nil
        }
    }
    
    private func resolveWindowContext(for element: AXUIElement) -> WindowContextResolution {
        let hitRole = axStringAttribute(kAXRoleAttribute, on: element) ?? "unknown"
        let hitSubrole = axStringAttribute(kAXSubroleAttribute, on: element) ?? "none"
        var containsTitleBar = false
        let window = findParentWindow(for: element, containsTitleBar: &containsTitleBar)
        guard let window else {
            return WindowContextResolution(
                window: nil,
                semanticTitleSource: containsTitleBar ? "ax-ancestry" : nil,
                hitRole: hitRole,
                hitSubrole: hitSubrole
            )
        }
        if containsTitleBar {
            return WindowContextResolution(
                window: window,
                semanticTitleSource: "ax-ancestry",
                hitRole: hitRole,
                hitSubrole: hitSubrole
            )
        }
        if isElementInSemanticRegion(element, attribute: kAXTitleUIElementAttribute, of: window) {
            return WindowContextResolution(
                window: window,
                semanticTitleSource: "ax-title-ui",
                hitRole: hitRole,
                hitSubrole: hitSubrole
            )
        }
        if isElementInSemanticRegion(element, attribute: kAXHeaderAttribute, of: window) {
            return WindowContextResolution(
                window: window,
                semanticTitleSource: "ax-header",
                hitRole: hitRole,
                hitSubrole: hitSubrole
            )
        }
        return WindowContextResolution(
            window: window,
            semanticTitleSource: nil,
            hitRole: hitRole,
            hitSubrole: hitSubrole
        )
    }

    /// Recursively traverses the Accessibility tree to find the nearest `kAXWindowRole`
    private func findParentWindow(for element: AXUIElement, containsTitleBar: inout Bool) -> AXUIElement? {
        if let directWindow = axElementAttribute(kAXWindowAttribute, on: element) {
            return directWindow
        }
        if let topLevelElement = axElementAttribute(kAXTopLevelUIElementAttribute, on: element) {
            return topLevelElement
        }

        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success {
            if let roleString = role as? String {
                if roleString == "AXTitleBar" {
                    containsTitleBar = true
                }
                if roleString == kAXWindowRole {
                    return element
                }
            }
        }

        var subrole: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success,
           let subroleString = subrole as? String,
           subroleString == "AXTitleBar" {
            containsTitleBar = true
        }
        
        var parent: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success {
            if let parent,
               CFGetTypeID(parent) == AXUIElementGetTypeID() {
                let parentElement = unsafeBitCast(parent, to: AXUIElement.self)
                return findParentWindow(for: parentElement, containsTitleBar: &containsTitleBar)
            }
        }
        
        return nil
    }

    private func axStringAttribute(_ attribute: String, on element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func axElementAttribute(_ attribute: String, on element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func isElementInSemanticRegion(_ element: AXUIElement, attribute: String, of window: AXUIElement) -> Bool {
        guard let regionElement = axElementAttribute(attribute, on: window) else {
            return false
        }
        return ancestryContains(element, target: regionElement)
    }

    private func ancestryContains(_ element: AXUIElement, target: AXUIElement) -> Bool {
        if CFEqual(element, target) {
            return true
        }

        var parent: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
              let parent,
              CFGetTypeID(parent) == AXUIElementGetTypeID() else {
            return false
        }

        let parentElement = unsafeBitCast(parent, to: AXUIElement.self)
        return ancestryContains(parentElement, target: target)
    }

    private func appName(for element: AXUIElement) -> String {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid) else {
            return "unknown"
        }
        return app.localizedName ?? app.bundleIdentifier ?? "pid-\(pid)"
    }

    private func bundleID(for element: AXUIElement) -> String {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid) else {
            return "unknown"
        }
        return app.bundleIdentifier ?? "pid-\(pid)"
    }

    private func qualifyHit(
        at point: CGPoint,
        window: AXUIElement,
        semanticSource: String?,
        signals: ChromeSignals
    ) -> HitQualification {
        if let semanticSource {
            return .accepted(semanticSource)
        }

        guard let frame = windowFrame(for: window) else {
            return .semanticMiss("window-frame-unavailable")
        }

        let titleBarMinY = frame.origin.y
        let titleBarMaxY = frame.origin.y + signals.topBandHeight
        
        // Use a consistent coordinate system (screen coordinates).
        // AXUIElementCopyElementAtPosition and kAXPositionAttribute both use top-left as origin.
        let hitBuffer: CGFloat = 8.0
        let isWithinTopBand = point.y >= (titleBarMinY - hitBuffer) && point.y <= (titleBarMaxY + hitBuffer)

        guard isWithinTopBand else {
            AppLogger.log("geometric miss: pointY=\(Int(point.y)) band=\(Int(titleBarMinY))..\(Int(titleBarMaxY)) windowY=\(Int(frame.origin.y))", subsystem: "interceptor")
            return .geometricMiss(
                "pointY=\(Int(point.y)) titleBarMinY=\(Int(titleBarMinY)) titleBarMaxY=\(Int(titleBarMaxY)) windowY=\(Int(frame.origin.y)) windowHeight=\(Int(frame.size.height))"
            )
        }

        let ancestry = signals.ancestryRoles.joined(separator: ">")

        // Reject only if the hit element is clearly inside scrollable/editable content.
        // Everything else within the top band is treated as the title bar area —
        // this covers Electron apps, custom-chrome apps, and any app that doesn't
        // expose a formal AXTitleBar element.
        if signals.hasContentOwnership {
            AppLogger.log("semantic miss: content-ownership at point (role: \(signals.hitRole)) ancestry=\(ancestry)", subsystem: "interceptor")
            return .semanticMiss("content-ownership ancestry=\(ancestry)")
        }

        return .accepted("geometric-topband variant=\(signals.variant)")
    }

    private func chromeSignals(for element: AXUIElement, window: AXUIElement) -> ChromeSignals {
        ChromeSignals(
            hitRole: axStringAttribute(kAXRoleAttribute, on: element) ?? "unknown",
            hitSubrole: axStringAttribute(kAXSubroleAttribute, on: element) ?? "none",
            ancestryRoles: ancestryRoles(for: element),
            windowChildRoles: childRoles(for: window)
        )
    }

    private func ancestryRoles(for element: AXUIElement) -> [String] {
        var roles: [String] = []
        var currentElement: AXUIElement? = element
        var depth = 0

        while depth < 12 {
            guard let element = currentElement else {
                break
            }

            if let role = axStringAttribute(kAXRoleAttribute, on: element) {
                roles.append(role)
            }

            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
                  let parent,
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else {
                break
            }

            currentElement = unsafeBitCast(parent, to: AXUIElement.self)
            depth += 1
        }

        return roles
    }

    private func childRoles(for element: AXUIElement) -> Set<String> {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else {
            return []
        }

        return Set(children.compactMap { axStringAttribute(kAXRoleAttribute, on: $0) })
    }

    private func windowFrame(for window: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?

        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
              let positionValue = position,
              let sizeValue = size,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        var cgPosition = CGPoint.zero
        var cgSize = CGSize.zero

        guard AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &cgPosition),
              AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &cgSize) else {
            return nil
        }

        return CGRect(origin: cgPosition, size: cgSize)
    }
    
    private func resetState() {
        isTrackingGesture = false
        activeTargetWindow = nil
        isTracking3Finger = false
        accumulated3FingerY = 0
    }
    
    enum InterceptorError: Error {
        case failedToCreateEventTap
    }
}
