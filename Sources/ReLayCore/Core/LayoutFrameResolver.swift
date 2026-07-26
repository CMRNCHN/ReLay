import CoreGraphics

// MARK: - Layout Frame Resolver
// Pure: WindowLayoutState → pixel frame in AX coordinates.

enum LayoutFrameResolver {

    static func frame(for layout: WindowLayoutState, in screen: CGRect, gap: CGFloat = 8) -> CGRect {
        let inset = gap / 2
        let x0 = screen.minX + inset
        let y0 = screen.minY + inset
        let w  = max(1, screen.width  - gap)
        let h  = max(1, screen.height - gap)

        switch layout {
        case .floating:
            return screen

        case .fullscreen:
            return CGRect(x: x0, y: y0, width: w, height: h)

        case .center:
            let cw = w * 0.72
            return CGRect(x: x0 + (w - cw) / 2, y: y0, width: cw, height: h)

        case .leftHalf:
            return CGRect(x: x0, y: y0, width: w * 0.5, height: h)

        case .rightHalf:
            return CGRect(x: x0 + w * 0.5, y: y0, width: w * 0.5, height: h)

        case .leftThird:
            return CGRect(x: x0, y: y0, width: w / 3, height: h)

        case .rightThird:
            return CGRect(x: x0 + w * 2 / 3, y: y0, width: w / 3, height: h)

        case .leftTopSixth:
            return CGRect(x: x0, y: y0, width: w / 3, height: h * 0.5)

        case .leftBottomSixth:
            return CGRect(x: x0, y: y0 + h * 0.5, width: w / 3, height: h * 0.5)

        case .rightTopSixth:
            return CGRect(x: x0 + w * 2 / 3, y: y0, width: w / 3, height: h * 0.5)

        case .rightBottomSixth:
            return CGRect(x: x0 + w * 2 / 3, y: y0 + h * 0.5, width: w / 3, height: h * 0.5)
        }
    }

    /// Frames for other windows that should fill the leftover region after a snap.
    /// Halves → opposite half; thirds → remaining two-thirds. Other layouts → none.
    /// Multiple companions are stacked top-to-bottom in that region.
    static func companionFrames(
        for primary: WindowLayoutState,
        count: Int,
        in screen: CGRect,
        gap: CGFloat = 8
    ) -> [CGRect] {
        guard count > 0,
              let region = complementaryRegion(for: primary, in: screen, gap: gap)
        else { return [] }
        return splitVertically(region, into: count, gap: gap)
    }

    private static func complementaryRegion(
        for primary: WindowLayoutState,
        in screen: CGRect,
        gap: CGFloat
    ) -> CGRect? {
        let inset = gap / 2
        let x0 = screen.minX + inset
        let y0 = screen.minY + inset
        let w  = max(1, screen.width  - gap)
        let h  = max(1, screen.height - gap)

        switch primary {
        case .leftHalf:
            return frame(for: .rightHalf, in: screen, gap: gap)
        case .rightHalf:
            return frame(for: .leftHalf, in: screen, gap: gap)
        case .leftThird:
            return CGRect(x: x0 + w / 3, y: y0, width: w * 2 / 3, height: h)
        case .rightThird:
            return CGRect(x: x0, y: y0, width: w * 2 / 3, height: h)
        default:
            return nil
        }
    }

    private static func splitVertically(_ region: CGRect, into count: Int, gap: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        if count == 1 { return [region] }
        let totalGap = gap * CGFloat(count - 1)
        let h = max(1, (region.height - totalGap) / CGFloat(count))
        return (0..<count).map { i in
            CGRect(
                x: region.minX,
                y: region.minY + CGFloat(i) * (h + gap),
                width: region.width,
                height: h
            )
        }
    }
}
