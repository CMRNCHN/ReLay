import CoreGraphics

// MARK: - Gesture Direction

enum GestureDirection: Hashable {
    case left, right, up, down

    init?(effectiveX: CGFloat, effectiveY: CGFloat) {
        guard effectiveX != 0 || effectiveY != 0 else { return nil }
        if abs(effectiveX) > abs(effectiveY) {
            self = effectiveX > 0 ? .right : .left
        } else {
            // Natural scrolling: positive Y = swipe up
            self = effectiveY > 0 ? .up : .down
        }
    }
}

// MARK: - Semantic Layout State

enum WindowLayoutState: Hashable, CaseIterable {
    // Unmanaged — frame does not match any known state
    case floating

    // Full-screen states
    case fullscreen     // 100% width, 100% height
    case center         // ~72% width, centered, full height

    // Left column
    case leftHalf           // 50% left
    case leftThird          // 33% left, full height
    case leftTopSixth       // 33% left, top 50%
    case leftBottomSixth    // 33% left, bottom 50%

    // Right column
    case rightHalf          // 50% right
    case rightThird         // 33% right, full height
    case rightTopSixth      // 33% right, top 50%
    case rightBottomSixth   // 33% right, bottom 50%
}

// MARK: - Transition Graph

private struct TransitionKey: Hashable {
    let state: WindowLayoutState
    let direction: GestureDirection
}

/// Declarative lookup table: (WindowLayoutState × GestureDirection) → WindowLayoutState.
/// All entries cover 2-finger gestures only. Multi-finger operations are
/// handled as special cases in SpatialTransitionEngine.
class LayoutTransitionGraph {

    private var table: [TransitionKey: WindowLayoutState] = [:]

    init() { buildTable() }

    func nextState(from state: WindowLayoutState, moving direction: GestureDirection) -> WindowLayoutState? {
        return table[TransitionKey(state: state, direction: direction)]
    }

    private func buildTable() {
        func add(_ from: WindowLayoutState, _ dir: GestureDirection, _ to: WindowLayoutState) {
            table[TransitionKey(state: from, direction: dir)] = to
        }

        // MARK: Horizontal — navigate columns
        for state in [WindowLayoutState.floating, .fullscreen] {
            add(state, .left,  .leftHalf)
            add(state, .right, .rightHalf)
        }
        // Center navigates out to halves in either mode
        add(.center, .left,  .leftHalf)
        add(.center, .right, .rightHalf)
        // Half → third (push further) or cross-side jump (pull back)
        add(.leftHalf,  .left,  .leftThird)
        add(.leftHalf,  .right, .rightHalf)
        add(.rightHalf, .right, .rightThird)
        add(.rightHalf, .left,  .leftHalf)
        // Third → half (pull back; edge resist in other direction)
        add(.leftThird,  .right, .leftHalf)
        add(.rightThird, .left,  .rightHalf)
        // Cross-column: jump sixths across the screen
        add(.leftTopSixth,    .right, .rightTopSixth)
        add(.leftBottomSixth, .right, .rightBottomSixth)
        add(.rightTopSixth,   .left,  .leftTopSixth)
        add(.rightBottomSixth,.left,  .leftBottomSixth)

        // Vertical gestures (up/down) are handled as direct actions in
        // SpatialTransitionEngine, not as graph transitions.
    }
}
