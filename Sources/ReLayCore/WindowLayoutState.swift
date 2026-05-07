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
        for state in [WindowLayoutState.floating, .center, .fullscreen] {
            add(state, .left,  .leftHalf)
            add(state, .right, .rightHalf)
        }
        // Half → third (push further) or center (pull back)
        add(.leftHalf,  .left,  .leftThird)
        add(.leftHalf,  .right, .center)
        add(.rightHalf, .right, .rightThird)
        add(.rightHalf, .left,  .center)
        // Third → half (pull back; edge resist in other direction)
        add(.leftThird,  .right, .leftHalf)
        add(.rightThird, .left,  .rightHalf)
        // Cross-column: jump sixths across the screen
        add(.leftTopSixth,    .right, .rightTopSixth)
        add(.leftBottomSixth, .right, .rightBottomSixth)
        add(.rightTopSixth,   .left,  .leftTopSixth)
        add(.rightBottomSixth,.left,  .leftBottomSixth)

        // MARK: Vertical — resize and subdivide
        // Grow halves/center/floating up to fullscreen
        for state in [WindowLayoutState.floating, .center, .leftHalf, .rightHalf] {
            add(state, .up, .fullscreen)
        }
        // Shrink fullscreen down to center; halves down to thirds
        add(.fullscreen, .down, .center)
        add(.leftHalf,   .down, .leftThird)
        add(.rightHalf,  .down, .rightThird)

        // Subdivide thirds into sixths (first split picks the natural half)
        add(.leftThird,  .up,   .leftBottomSixth)   // upward scroll → bottom half shown
        add(.leftThird,  .down, .leftTopSixth)      // downward scroll → top half shown
        add(.rightThird, .up,   .rightBottomSixth)
        add(.rightThird, .down, .rightTopSixth)

        // Toggle between sixths — both directions cycle top↔bottom
        add(.leftTopSixth,    .up,   .leftBottomSixth)
        add(.leftTopSixth,    .down, .leftBottomSixth)
        add(.leftBottomSixth, .up,   .leftTopSixth)
        add(.leftBottomSixth, .down, .leftTopSixth)
        add(.rightTopSixth,    .up,   .rightBottomSixth)
        add(.rightTopSixth,    .down, .rightBottomSixth)
        add(.rightBottomSixth, .up,   .rightTopSixth)
        add(.rightBottomSixth, .down, .rightTopSixth)
    }
}
