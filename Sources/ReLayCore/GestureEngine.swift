import ApplicationServices
import Cocoa
import Accessibility

// GestureAxis is the only geometry this layer knows about.
// All semantic meaning (states, frames, actions) lives in SpatialTransitionEngine.
enum GestureAxis { case horizontal, vertical }

public final class GestureEngine: TitleBarInterceptorDelegate {
    public init() {
        AppLogger.log("gesture engine initialized", subsystem: "gesture")
    }

    // MARK: - Thresholds

    private let lockThreshold:   CGFloat = 20.0
    private let cancelThreshold: CGFloat = 25.0
    private let actionThreshold: CGFloat = 100.0
    private let flickVelocity:   CGFloat = 800.0

    // MARK: - Session State

    private var axisLocked:        GestureAxis?
    private var accumulatedX:      CGFloat = 0
    private var accumulatedY:      CGFloat = 0
    private var hasCommitted:      Bool    = false
    private var currentFingerCount: Int    = 2
    private var startLocation:     CGPoint = .zero
    private var currentSessionID:  String?

    // MARK: - TitleBarInterceptorDelegate

    public func gestureDidBegin(on window: AXUIElement, at location: CGPoint, fingerCount: Int, sessionID: String) {
        axisLocked         = nil
        accumulatedX       = 0
        accumulatedY       = 0
        hasCommitted       = false
        currentFingerCount = fingerCount
        startLocation      = location
        currentSessionID   = sessionID
        AppLogger.log("gesture began fingers=\(fingerCount)", sessionID: sessionID, subsystem: "gesture")
        SpatialTransitionEngine.shared.beginSession(window: window, fingerCount: fingerCount, at: location, sessionID: sessionID)
    }

    public func gestureDidDoubleTap(on window: AXUIElement, sessionID: String) {}

    public func gestureDidChange(deltaX: CGFloat, deltaY: CGFloat, velocity: CGFloat, sessionID: String) {
        guard !hasCommitted else { return }

        accumulatedX += deltaX
        accumulatedY += deltaY

        // Axis locking: one axis must dominate the other by 1.5× before we commit direction
        if axisLocked == nil {
            let absX = abs(accumulatedX), absY = abs(accumulatedY)
            if absX > lockThreshold && absX > absY * 1.5 {
                axisLocked = .horizontal
                AppLogger.log("gesture axis locked horizontal", sessionID: sessionID, subsystem: "gesture")
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            } else if absY > lockThreshold && absY > absX * 1.5 {
                axisLocked = .vertical
                AppLogger.log("gesture axis locked vertical", sessionID: sessionID, subsystem: "gesture")
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            } else if max(absX, absY) > cancelThreshold {
                // Diagonal movement beyond ambiguity window — cancel
                AppLogger.log("gesture cancelled due to diagonal ambiguity", sessionID: sessionID, subsystem: "gesture")
                gestureDidCancel(sessionID: sessionID)
                return
            }
            guard axisLocked != nil else { return }
        }

        let effectiveX = axisLocked == .horizontal ? accumulatedX : 0
        let effectiveY = axisLocked == .vertical   ? accumulatedY : 0
        let distance   = max(abs(effectiveX), abs(effectiveY))
        let progress   = min(1.0, max(0.0, (distance - lockThreshold) / (actionThreshold - lockThreshold)))

        SpatialTransitionEngine.shared.updatePreview(
            effectiveX: effectiveX,
            effectiveY: effectiveY,
            progress:   progress,
            sessionID:  sessionID
        )

        if velocity > flickVelocity {
            AppLogger.log("gesture commit via flick velocity", sessionID: sessionID, subsystem: "gesture")
            commit(effectiveX: effectiveX, effectiveY: effectiveY, sessionID: sessionID)
        }
    }

    public func gestureDidEnd(sessionID: String) {
        if hasCommitted {
            AppLogger.log("gesture ended after committed transition", sessionID: sessionID, subsystem: "gesture")
            resetState()
            return
        }
        guard !hasCommitted, let lockedAxis = axisLocked else {
            AppLogger.log("gesture ended without locked axis; cancelling", sessionID: sessionID, subsystem: "gesture")
            gestureDidCancel(sessionID: sessionID)
            return
        }
        let effectiveX = lockedAxis == .horizontal ? accumulatedX : 0
        let effectiveY = lockedAxis == .vertical   ? accumulatedY : 0
        if abs(effectiveX) > actionThreshold || abs(effectiveY) > actionThreshold {
            AppLogger.log("gesture commit via distance threshold", sessionID: sessionID, subsystem: "gesture")
            commit(effectiveX: effectiveX, effectiveY: effectiveY, sessionID: sessionID)
        } else {
            AppLogger.log("gesture ended below action threshold; cancelling", sessionID: sessionID, subsystem: "gesture")
            gestureDidCancel(sessionID: sessionID)
        }
    }

    public func gestureDidCancel(sessionID: String) {
        guard !hasCommitted else {
            AppLogger.log("gesture cancel received after commit; resetting", sessionID: sessionID, subsystem: "gesture")
            resetState()
            return
        }
        hasCommitted = true
        AppLogger.log("gesture cancelled", sessionID: sessionID, subsystem: "gesture")
        SpatialTransitionEngine.shared.cancelSession(sessionID: sessionID)
        resetState()
    }

    // MARK: - Private

    private func commit(effectiveX: CGFloat, effectiveY: CGFloat, sessionID: String) {
        hasCommitted = true
        let direction = GestureDirection(effectiveX: effectiveX, effectiveY: effectiveY)
        AppLogger.log(
            "gesture committed direction=\(direction.map { String(describing: $0) } ?? "none") fingers=\(currentFingerCount)",
            sessionID: sessionID,
            subsystem: "gesture"
        )
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
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
        currentSessionID   = nil
    }
}
