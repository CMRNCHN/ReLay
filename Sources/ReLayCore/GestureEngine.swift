import ApplicationServices
import Cocoa
import Accessibility

// GestureAxis is the only geometry this layer knows about.
// All semantic meaning (states, frames, actions) lives in SpatialTransitionEngine.
enum GestureAxis { case horizontal, vertical }

class GestureEngine: TitleBarInterceptorDelegate {

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

    // MARK: - TitleBarInterceptorDelegate

    func gestureDidBegin(on window: AXUIElement, at location: CGPoint, fingerCount: Int) {
        axisLocked         = nil
        accumulatedX       = 0
        accumulatedY       = 0
        hasCommitted       = false
        currentFingerCount = fingerCount
        startLocation      = location
        SpatialTransitionEngine.shared.beginSession(window: window, fingerCount: fingerCount, at: location)
    }

    func gestureDidDoubleTap(on window: AXUIElement) {}

    func gestureDidChange(deltaX: CGFloat, deltaY: CGFloat, velocity: CGFloat) {
        guard !hasCommitted else { return }

        accumulatedX += deltaX
        accumulatedY += deltaY

        // Axis locking: one axis must dominate the other by 1.5× before we commit direction
        if axisLocked == nil {
            let absX = abs(accumulatedX), absY = abs(accumulatedY)
            if absX > lockThreshold && absX > absY * 1.5 {
                axisLocked = .horizontal
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            } else if absY > lockThreshold && absY > absX * 1.5 {
                axisLocked = .vertical
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            } else if max(absX, absY) > cancelThreshold {
                // Diagonal movement beyond ambiguity window — cancel
                gestureDidCancel()
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
            progress:   progress
        )

        if velocity > flickVelocity {
            commit(effectiveX: effectiveX, effectiveY: effectiveY)
        }
    }

    func gestureDidEnd() {
        guard !hasCommitted, let lockedAxis = axisLocked else {
            gestureDidCancel()
            return
        }
        let effectiveX = lockedAxis == .horizontal ? accumulatedX : 0
        let effectiveY = lockedAxis == .vertical   ? accumulatedY : 0
        if abs(effectiveX) > actionThreshold || abs(effectiveY) > actionThreshold {
            commit(effectiveX: effectiveX, effectiveY: effectiveY)
        } else {
            gestureDidCancel()
        }
    }

    func gestureDidCancel() {
        guard !hasCommitted else { return }
        hasCommitted = true
        SpatialTransitionEngine.shared.cancelSession()
        resetState()
    }

    // MARK: - Private

    private func commit(effectiveX: CGFloat, effectiveY: CGFloat) {
        hasCommitted = true
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        SpatialTransitionEngine.shared.commitSession(
            effectiveX:  effectiveX,
            effectiveY:  effectiveY,
            fingerCount: currentFingerCount,
            at:          startLocation
        )
        resetState()
    }

    private func resetState() {
        axisLocked         = nil
        accumulatedX       = 0
        accumulatedY       = 0
        hasCommitted       = false
        currentFingerCount = 2
        startLocation      = .zero
    }
}
