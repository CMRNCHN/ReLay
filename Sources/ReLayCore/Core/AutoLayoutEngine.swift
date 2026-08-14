import CoreGraphics

// MARK: - Auto Layout Engine
// Pure: given how many standard windows are on a screen, produce the tile
// frames they should occupy. No AX. No NSScreen.
//
// Frame arrays are oldest → newest (caller reverses front-to-back CG order).
// Newest always lands in the last slot (right / right-third / bottom-right).

enum AutoLayoutEngine {

    /// Highest window count we will auto-tile. Beyond this, leave the desk alone
    /// so we never micro-stack five-plus windows into unusable strips.
    static let maxTileCount = 4

    /// Tile frames for `count` windows on `screen`. Returns nil when auto-layout
    /// should leave the desk alone.
    static func frames(
        for count: Int,
        in screen: CGRect,
        gap: CGFloat = 8
    ) -> [CGRect]? {
        guard !screen.isEmpty else { return nil }
        switch count {
        case 2:
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
        case 4:
            return grid2x2(in: screen, gap: gap)
        default:
            return nil
        }
    }

    /// Which window gets which slot: frontmost (newest) lands in the last slot.
    static func assignmentOrder(windowCount: Int) -> [Int]? {
        guard (2...maxTileCount).contains(windowCount) else { return nil }
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

    /// 2×2 quarters: [top-left, top-right, bottom-left, bottom-right].
    static func grid2x2(in screen: CGRect, gap: CGFloat = 8) -> [CGRect]? {
        let left = LayoutFrameResolver.frame(for: .leftHalf, in: screen, gap: gap)
        let right = LayoutFrameResolver.frame(for: .rightHalf, in: screen, gap: gap)
        guard let (leftTop, leftBottom) = splitVertically(left, gap: gap),
              let (rightTop, rightBottom) = splitVertically(right, gap: gap)
        else { return nil }
        let frames = [leftTop, rightTop, leftBottom, rightBottom]
        guard frames.allSatisfy({ AXWindowOps.isWritableFrame($0) }) else { return nil }
        return frames
    }

    private static func splitVertically(_ region: CGRect, gap: CGFloat) -> (CGRect, CGRect)? {
        let innerH = region.height - gap
        guard innerH >= AXWindowOps.minWritableHeight * 2 else { return nil }
        let topH = (innerH / 2).rounded()
        let top = CGRect(x: region.minX, y: region.minY, width: region.width, height: topH)
        let bottomY = top.maxY + gap
        let bottom = CGRect(
            x: region.minX,
            y: bottomY,
            width: region.width,
            height: max(1, region.maxY - bottomY)
        )
        guard AXWindowOps.isWritableFrame(top), AXWindowOps.isWritableFrame(bottom) else { return nil }
        return (top, bottom)
    }
}
