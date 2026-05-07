import ApplicationServices
import Cocoa
import ApplicationServices
import Accessibility

/// Delegate protocol to pass clean gesture lifecycle events to the Gesture Engine.
protocol TitleBarInterceptorDelegate: AnyObject {
    func gestureDidBegin(on window: AXUIElement, at location: CGPoint, fingerCount: Int)
    func gestureDidChange(deltaX: CGFloat, deltaY: CGFloat, velocity: CGFloat)
    func gestureDidEnd()
    func gestureDidCancel()
    func gestureDidDoubleTap(on window: AXUIElement)
}

class TitleBarInterceptor {
    
    weak var delegate: TitleBarInterceptorDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var gestureMonitor: Any?

    // State Tracking
    private var isTrackingGesture = false
    private var activeTargetWindow: AXUIElement?
    private var lastKnownTouchCount: Int = 2

    // Configuration
    private let titleBarHeightThreshold: CGFloat = 40.0 // Accommodates modern Big Sur+ toolbars

    init() {}
    
    /// Starts intercepting global mouse events
    func start() throws {
        let eventMask = (1 << CGEventType.scrollWheel.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)
        
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
            throw InterceptorError.failedToCreateEventTap
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        // Secondary monitor: gesture events (type 29) expose touch count via NSTouch
        gestureMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: NSEvent.EventTypeMask(rawValue: 1 << 29)
        ) { [weak self] event in
            let count = event.touches(matching: .touching, in: nil).count
            if count > 0 { self?.lastKnownTouchCount = count }
        }
    }
    
    /// Stops the global event tap
    func stop() {
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
    
    /// Main callback handler for intercepted events
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable event tap if the system disabled it due to timeout or user input.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Handle Double Tap (Left Mouse Down with clickCount == 2)
        if type == .leftMouseDown {
            if let nsEvent = NSEvent(cgEvent: event), nsEvent.clickCount == 2 {
                let location = event.unflippedLocation
                if let window = hitTestTitleBar(at: location) {
                    delegate?.gestureDidDoubleTap(on: window)
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
            let location = event.unflippedLocation
            
            if let window = hitTestTitleBar(at: location) {
                isTrackingGesture = true
                activeTargetWindow = window
                delegate?.gestureDidBegin(on: window, at: location, fingerCount: lastKnownTouchCount)
                
                // Swallow the event to prevent underlying scroll
                return nil 
            }
        }
        
        // Phase: Changed (Physical finger movement)
        if phase == .changed && isTrackingGesture {
            // Calculate velocity approximation (pixels per second based on standard 60hz scroll polling)
            let deltaX = nsEvent.scrollingDeltaX
            let deltaY = nsEvent.scrollingDeltaY
            let velocity = sqrt(deltaX * deltaX + deltaY * deltaY) * 60.0 
            
            delegate?.gestureDidChange(deltaX: deltaX, deltaY: deltaY, velocity: velocity)
            return nil // Swallow event
        }
        
        // Phase: Ended or Cancelled
        if (phase == .ended || phase == .cancelled || momentumPhase == .began) && isTrackingGesture {
            if phase == .cancelled {
                delegate?.gestureDidCancel()
            } else {
                delegate?.gestureDidEnd()
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
        
        guard error == .success, let hitElement = element else { return nil }
        
        // Traverse up the AX hierarchy to find the parent Window
        guard let window = findParentWindow(for: hitElement) else { return nil }
        
        // Verify the window frame
        var position: CFTypeRef?
        var size: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success else {
            return nil
        }

        guard let positionValue = position,
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
        
        // Check if the click is within the top bounds (Title Bar region)
        let isWithinTitleBarHeight = (point.y >= cgPosition.y) && (point.y <= cgPosition.y + titleBarHeightThreshold)
        
        return isWithinTitleBarHeight ? window : nil
    }
    
    /// Recursively traverses the Accessibility tree to find the nearest `kAXWindowRole`
    private func findParentWindow(for element: AXUIElement) -> AXUIElement? {
        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success {
            if let roleString = role as? String, roleString == kAXWindowRole {
                return element
            }
        }
        
        var parent: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success {
            if let parent,
               CFGetTypeID(parent) == AXUIElementGetTypeID() {
                let parentElement = unsafeBitCast(parent, to: AXUIElement.self)
                return findParentWindow(for: parentElement)
            }
        }
        
        return nil
    }
    
    private func resetState() {
        isTrackingGesture = false
        activeTargetWindow = nil
    }
    
    enum InterceptorError: Error {
        case failedToCreateEventTap
    }
}