import ApplicationServices
import Cocoa
import Accessibility

// GestureAxis is the only geometry this layer knows about.
// All semantic meaning (states, frames, actions) lives in SpatialTransitionEngine.
enum GestureAxis { case horizontal, vertical }

public final class GestureEngine: TitleBarInterceptorDelegate {
    public init() {
        reloadThresholds()
        AppLogger.log("gesture engine initialized", subsystem: "gesture")
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ReLaySettingsChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.reloadThresholds()
        }
    }

    private var thresholds: [String: CGFloat] = [:]

    private func reloadThresholds() {
        thresholds["lockThreshold"] = CGFloat(UserDefaults.standard.double(forKey: "lockThreshold") != 0 ? UserDefaults.standard.double(forKey: "lockThreshold") : 20.0)
        thresholds["cancelThreshold"] = CGFloat(UserDefaults.standard.double(forKey: "cancelThreshold") != 0 ? UserDefaults.standard.double(forKey: "cancelThreshold") : 25.0)
        thresholds["actionThreshold"] = CGFloat(UserDefaults.standard.double(forKey: "actionThreshold") != 0 ? UserDefaults.standard.double(forKey: "actionThreshold") : 100.0)
        thresholds["flickVelocity"] = CGFloat(UserDefaults.standard.double(forKey: "flickVelocity") != 0 ? UserDefaults.standard.double(forKey: "flickVelocity") : 800.0)
    }

    // MARK: - Session State

    private var axisLocked:        GestureAxis?
    private var accumulatedX:      CGFloat = 0
    private var accumulatedY:      CGFloat = 0
    private var hasCommitted:      Bool    = false
    private var currentFingerCount: Int    = 2
    private var startLocation:     CGPoint = .zero
    private var isShiftMode:       Bool    = false
    private var currentGestureID:  UUID    = UUID()
    private var sessionID:         String  = ""

    // MARK: - TitleBarInterceptorDelegate

    public func gestureDidBegin(on window: AXUIElement, at location: CGPoint, fingerCount: Int, shiftHeld: Bool, gestureID: UUID, sessionID: String) {
        axisLocked         = nil
        accumulatedX       = 0
        accumulatedY       = 0
        hasCommitted       = false
        currentFingerCount = fingerCount
        startLocation      = location
        isShiftMode        = shiftHeld && fingerCount == 2
        currentGestureID   = gestureID
        self.sessionID     = sessionID
        AppLogger.log("gesture began gesture=\(gestureID.uuidString.prefix(8)) fingers=\(fingerCount) shiftMode=\(isShiftMode)", subsystem: "gesture")
        SpatialTransitionEngine.shared.beginSession(window: window, fingerCount: fingerCount, at: location, gestureID: gestureID, sessionID: sessionID)
    }

    public func gestureDidDoubleTap(on window: AXUIElement, sessionID: String) {}

    public func killSwitchTriggered() {
        gestureDidCancel()
        NotificationCenter.default.post(name: NSNotification.Name("ReLayEmergencyStop"), object: nil)
    }

    public func gestureDidChange(deltaX: CGFloat, deltaY: CGFloat, velocity: CGFloat, sessionID: String) {
        self.sessionID = sessionID
        if isShiftMode {
            SpatialTransitionEngine.shared.applyResizeDelta(deltaY: deltaY)
            return
        }
        guard !hasCommitted else { return }

        accumulatedX += deltaX
        accumulatedY += deltaY
        if abs(accumulatedY) > 5 && axisLocked == nil {
            AppLogger.log("gesture=\(currentGestureID.uuidString.prefix(8)) deltaY accumulating: \(accumulatedY > 0 ? "positive" : "negative") (\(accumulatedY))", subsystem: "gesture")
        }

        // Axis locking: one axis must dominate the other by 1.5× before we commit direction
        if axisLocked == nil {
            let absX = abs(accumulatedX), absY = abs(accumulatedY)
            if absX > (thresholds["lockThreshold"] ?? 20.0) && absX > absY * 1.5 {
                axisLocked = .horizontal
                AppLogger.log("gesture axis locked horizontal gesture=\(currentGestureID.uuidString.prefix(8))", subsystem: "gesture")
                if ReLaySettings.hapticsEnabled { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default) }
            } else if absY > (thresholds["lockThreshold"] ?? 20.0) && absY > absX * 1.5 {
                axisLocked = .vertical
                AppLogger.log("gesture axis locked vertical gesture=\(currentGestureID.uuidString.prefix(8))", subsystem: "gesture")
                if ReLaySettings.hapticsEnabled { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default) }
            } else if max(absX, absY) > (thresholds["cancelThreshold"] ?? 25.0) {
                // Diagonal movement beyond ambiguity window — cancel
                AppLogger.log("gesture cancelled due to diagonal ambiguity gesture=\(currentGestureID.uuidString.prefix(8))", subsystem: "gesture")
                gestureDidCancel(sessionID: sessionID)
                return
            }
            guard axisLocked != nil else { return }
        }

        let effectiveX = axisLocked == .horizontal ? accumulatedX : 0
        let effectiveY = axisLocked == .vertical   ? accumulatedY : 0
        let distance   = max(abs(effectiveX), abs(effectiveY))
        let lockVal    = thresholds["lockThreshold"] ?? 20.0
        let actionVal  = thresholds["actionThreshold"] ?? 100.0
        let progress   = min(1.0, max(0.0, (distance - lockVal) / (actionVal - lockVal)))

        SpatialTransitionEngine.shared.updatePreview(
            effectiveX: effectiveX,
            effectiveY: effectiveY,
            progress:   progress,
            sessionID:  sessionID
        )

        if velocity > (thresholds["flickVelocity"] ?? 800.0) {
            AppLogger.log("gesture commit via flick velocity gesture=\(currentGestureID.uuidString.prefix(8))", subsystem: "gesture")
            commit(effectiveX: effectiveX, effectiveY: effectiveY, sessionID: sessionID)
        }
    }

    public func gestureDidEnd(sessionID: String) {
        self.sessionID = sessionID
        if isShiftMode {
            AppLogger.log("shift resize session ended gesture=\(currentGestureID.uuidString.prefix(8))", subsystem: "gesture")
            SpatialTransitionEngine.shared.endResizeSession()
            resetState()
            return
        }
        if hasCommitted {
            AppLogger.log("gesture ended after committed transition gesture=\(currentGestureID.uuidString.prefix(8))", subsystem: "gesture")
            resetState()
            return
        }
        guard !hasCommitted, let lockedAxis = axisLocked else {
            AppLogger.log("gesture ended without locked axis; cancelling gesture=\(currentGestureID.uuidString.prefix(8))", subsystem: "gesture")
            gestureDidCancel(sessionID: sessionID)
            return
        }
        let effectiveX = lockedAxis == .horizontal ? accumulatedX : 0
        let effectiveY = lockedAxis == .vertical   ? accumulatedY : 0
        let actionVal  = thresholds["actionThreshold"] ?? 100.0
        if abs(effectiveX) > actionVal || abs(effectiveY) > actionVal {
            AppLogger.log("gesture commit via distance threshold gesture=\(currentGestureID.uuidString.prefix(8))", subsystem: "gesture")
            commit(effectiveX: effectiveX, effectiveY: effectiveY, sessionID: sessionID)
        } else {
            AppLogger.log("gesture ended below action threshold; cancelling gesture=\(currentGestureID.uuidString.prefix(8))", subsystem: "gesture")
            gestureDidCancel(sessionID: sessionID)
        }
    }

    public func gestureDidCancel(sessionID: String) {
        self.sessionID = sessionID
        if isShiftMode {
            AppLogger.log("shift resize session cancelled gesture=\(currentGestureID.uuidString.prefix(8))", subsystem: "gesture")
            SpatialTransitionEngine.shared.cancelResizeSession()
            resetState()
            return
        }
        guard !hasCommitted else {
            AppLogger.log("gesture cancel received after commit; resetting gesture=\(currentGestureID.uuidString.prefix(8))", subsystem: "gesture")
            resetState()
            return
        }
        hasCommitted = true
        AppLogger.log("gesture cancelled gesture=\(currentGestureID.uuidString.prefix(8))", subsystem: "gesture")
        SpatialTransitionEngine.shared.cancelSession()
        resetState()
    }

    // MARK: - Private

    private func commit(effectiveX: CGFloat, effectiveY: CGFloat, sessionID: String) {
        hasCommitted = true
        let direction = GestureDirection(effectiveX: effectiveX, effectiveY: effectiveY)
        AppLogger.log(
            "gesture committed gesture=\(currentGestureID.uuidString.prefix(8)) direction=\(direction.map { String(describing: $0) } ?? "none") fingers=\(currentFingerCount)",
            subsystem: "gesture"
        )
        if ReLaySettings.hapticsEnabled { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
        SpatialTransitionEngine.shared.commitSession(
            effectiveX:  effectiveX,
            effectiveY:  effectiveY,
            fingerCount: currentFingerCount,
            at:          startLocation,
            sessionID:   sessionID
        )
    }

    private func resetState() {
        axisLocked         = nil
        accumulatedX       = 0
        accumulatedY       = 0
        hasCommitted       = false
        currentFingerCount = 2
        startLocation      = .zero
        isShiftMode        = false
    }
}
