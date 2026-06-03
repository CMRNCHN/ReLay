import CoreGraphics

// Stateful, no UI dependencies, no system calls.
final class InputGestureEngine: GestureProcessing {
    private static let bufferCapacity = 10
    private static let swipeVelocityThreshold = 15.0
    private static let pinchInThreshold = -0.05
    private static let pinchOutThreshold = 0.05

    private var state: GestureState = .idle
    private var buffer: [NormalizedEvent] = []
    private var accumulatedScale: Double = 0

    // Returns a completed gesture if one can be determined, nil otherwise.
    func process(_ event: NormalizedEvent) -> InputGesture? {
        enqueue(event)

        switch event {
        case .swipe(let direction, let velocity):
            guard velocity >= Self.swipeVelocityThreshold else { return nil }
            state = .swiping
            switch direction {
            case .left:  return .twoFingerSwipeLeft
            case .right: return .twoFingerSwipeRight
            case .up, .down: return nil
            }

        case .scroll(let dx, let dy):
            state = .scrolling
            // Emit three-finger-drag from scroll delta (fallback inference)
            return .threeFingerDrag(delta: CGPoint(x: dx, y: dy))

        case .pinch(let scale):
            state = .pinching
            accumulatedScale += scale
            if accumulatedScale < Self.pinchInThreshold {
                accumulatedScale = 0
                state = .idle
                return .pinchZoomOut
            } else if accumulatedScale > Self.pinchOutThreshold {
                accumulatedScale = 0
                state = .idle
                return .pinchZoomIn
            }
            return nil
        }
    }

    func reset() {
        state = .idle
        buffer.removeAll(keepingCapacity: true)
        accumulatedScale = 0
    }

    // MARK: - Private

    private func enqueue(_ event: NormalizedEvent) {
        if buffer.count >= Self.bufferCapacity { buffer.removeFirst() }
        buffer.append(event)
    }
}
