import CoreGraphics

// MARK: - Auto Layout Engine
// Pure: given how many standard windows are on a screen, produce the tile
// frames they should occupy. No AX. No NSScreen.

enum AutoLayoutEngine {

    /// Tile frames for `count` windows on `screen`, front-to-back order
    /// (index 0 = newest / frontmost). Returns nil when auto-layout should
    /// leave the desk alone.
    static func frames(
        for count: Int,
        in screen: CGRect,
        gap: CGFloat = 8
    ) -> [CGRect]? {
        guard !screen.isEmpty else { return nil }
        switch count {
        case 2:
            // Newest on the right — matches "I opened something beside what I had".
            return [
                LayoutFrameResolver.frame(for: .leftHalf, in: screen, gap: gap),
                LayoutFrameResolver.frame(for: .rightHalf, in: screen, gap: gap)
            ]
        case 3:
            return [
                LayoutFrameResolver.frame(for: .leftThird, in: screen, gap: gap),
                middleThird(in: screen, gap: gap),
                LayoutFrameResolver.frame(for: .rightThird, in: screen, gap: gap)
            ]
        default:
            return nil
        }
    }

    /// Which window gets which slot: frontmost (newest) lands in the last slot
    /// (right / right-third), older windows fill left-to-right.
    static func assignmentOrder(windowCount: Int) -> [Int]? {
        // Identity permutation: caller passes windows oldest→newest or we
        // reverse so newest is last. Exposed for tests.
        guard windowCount == 2 || windowCount == 3 else { return nil }
        return Array(0..<windowCount)
    }

    static func middleThird(in screen: CGRect, gap: CGFloat = 8) -> CGRect {
        let left = LayoutFrameResolver.frame(for: .leftThird, in: screen, gap: gap)
        let right = LayoutFrameResolver.frame(for: .rightThird, in: screen, gap: gap)
        let x = left.maxX + gap
        return CGRect(
            x: x,
            y: left.minY,
            width: max(1, right.minX - gap - x),
            height: left.height
        )
    }
}
