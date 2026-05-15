import ApplicationServices
import CoreGraphics

// MARK: - CGRect tolerance comparison

extension CGRect {
    func approximatelyEquals(_ other: CGRect, tolerance: CGFloat = 20) -> Bool {
        return abs(origin.x - other.origin.x) <= tolerance
            && abs(origin.y - other.origin.y) <= tolerance
            && abs(width  - other.width)       <= tolerance
            && abs(height - other.height)      <= tolerance
    }
}

// MARK: - Layout Resolver

/// Pure geometric mapping between WindowLayoutState and CGRect.
/// No AX knowledge. No side effects. No mutable state.
class LayoutResolver {
    static let shared = LayoutResolver()
    private init() {}

    // MARK: - State → Frame

    func frame(for state: WindowLayoutState, on screen: CGRect) -> CGRect {
        let W = screen.width, H = screen.height
        let X = screen.origin.x, Y = screen.origin.y

        switch state {
        case .floating:
            // Caller must substitute the window's saved floatingFrame.
            return .zero

        case .fullscreen:
            return screen

        case .center:
            // ~72% wide, centered — visually distinct from fullscreen
            let w = round(W * 0.72)
            return CGRect(x: X + round((W - w) / 2), y: Y, width: w, height: H)

        case .leftHalf:
            return CGRect(x: X, y: Y, width: round(W * 0.5), height: H)

        case .rightHalf:
            let w = round(W * 0.5)
            return CGRect(x: X + (W - w), y: Y, width: w, height: H)

        case .leftThird:
            return CGRect(x: X, y: Y, width: round(W / 3), height: H)

        case .rightThird:
            let w = round(W / 3)
            return CGRect(x: X + W - w, y: Y, width: w, height: H)

        case .leftTopSixth:
            return CGRect(x: X, y: Y, width: round(W / 3), height: round(H / 2))

        case .leftBottomSixth:
            let h = round(H / 2)
            return CGRect(x: X, y: Y + h, width: round(W / 3), height: h)

        case .rightTopSixth:
            let w = round(W / 3)
            return CGRect(x: X + W - w, y: Y, width: w, height: round(H / 2))

        case .rightBottomSixth:
            let w = round(W / 3)
            let h = round(H / 2)
            return CGRect(x: X + W - w, y: Y + h, width: w, height: h)
        }
    }

    // MARK: - Frame → State inference

    /// Infers the semantic state of an arbitrary frame. Used when a window
    /// is touched for the first time and has no entry in WindowStateStore.
    func inferState(from frame: CGRect, on screen: CGRect) -> WindowLayoutState {
        AppLogger.log("inferring state from frame", subsystem: "resolver")
        let candidates = WindowLayoutState.allCases.filter { $0 != .floating }
        for state in candidates {
            let expected = self.frame(for: state, on: screen)
            if frame.approximatelyEquals(expected) {
                return state
            }
        }
        return .floating
    }

    // MARK: - Preview interpolation helper

    /// Returns the linearly interpolated frame at `progress` (0…1) between
    /// `from` and `to`. Used by PreviewManager to track the gesture in real time.
    func interpolate(from: CGRect, to: CGRect, progress: CGFloat) -> CGRect {
        let p = max(0, min(1, progress))
        return CGRect(
            x:      from.origin.x + (to.origin.x - from.origin.x) * p,
            y:      from.origin.y + (to.origin.y - from.origin.y) * p,
            width:  from.width    + (to.width     - from.width)    * p,
            height: from.height   + (to.height    - from.height)   * p
        )
    }
}
