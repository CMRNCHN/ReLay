import CoreGraphics

// MARK: - Layout Frame Resolver
// Pure: WindowLayoutState → pixel frame in AX coordinates.
// `gap` is both the outer margin (halved) and the seam between neighbouring
// tiles, and every edge is rounded so adjacent windows meet exactly.

enum LayoutFrameResolver {

    static func frame(for layout: WindowLayoutState, in screen: CGRect, gap: CGFloat = 8) -> CGRect {
        let m = Metrics(screen: screen, gap: gap)

        switch layout {
        // `.floating` means "geometry unknown". It is never a good idea to
        // apply it, so it falls back to the same rect as `.fullscreen` rather
        // than the raw screen — which would be larger than fullscreen.
        case .floating, .fullscreen:
            return m.rect(m.x0, m.y0, m.maxX, m.maxY)

        case .center:
            let cw = m.w * 0.72
            return m.rect(m.x0 + (m.w - cw) / 2, m.y0, m.x0 + (m.w + cw) / 2, m.maxY)

        case .leftHalf:
            return m.rect(m.x0, m.y0, m.x0 + m.half, m.maxY)

        case .rightHalf:
            return m.rect(m.maxX - m.half, m.y0, m.maxX, m.maxY)

        case .leftTwoThirds:
            return m.rect(m.x0, m.y0, m.x0 + m.twoThirds, m.maxY)

        case .rightTwoThirds:
            return m.rect(m.maxX - m.twoThirds, m.y0, m.maxX, m.maxY)

        case .leftThird:
            return m.rect(m.x0, m.y0, m.x0 + m.third, m.maxY)

        case .rightThird:
            return m.rect(m.maxX - m.third, m.y0, m.maxX, m.maxY)

        case .leftTopSixth:
            return m.rect(m.x0, m.y0, m.x0 + m.third, m.y0 + m.halfHeight)

        case .leftBottomSixth:
            return m.rect(m.x0, m.maxY - m.halfHeight, m.x0 + m.third, m.maxY)

        case .rightTopSixth:
            return m.rect(m.maxX - m.third, m.y0, m.maxX, m.y0 + m.halfHeight)

        case .rightBottomSixth:
            return m.rect(m.maxX - m.third, m.maxY - m.halfHeight, m.maxX, m.maxY)
        }
    }

    /// Frames for other windows that should fill the leftover region after a
    /// snap. Halves → opposite half; thirds → remaining two-thirds. Other
    /// layouts → none. Multiple companions are stacked top-to-bottom.
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

    /// Which layout a window is *actually* in, judged from its frame. The
    /// runtime uses this instead of remembering what it last did, so a window
    /// the user moved by hand — or that an app resized on its own — never
    /// leaves the gesture model out of sync with the screen.
    static func layout(
        matching rect: CGRect,
        in screen: CGRect,
        gap: CGFloat = 8,
        tolerance: CGFloat = 12
    ) -> WindowLayoutState {
        guard !rect.isEmpty, !screen.isEmpty else { return .floating }
        for candidate in WindowLayoutState.allCases where candidate != .floating {
            let f = frame(for: candidate, in: screen, gap: gap)
            if abs(f.minX - rect.minX) <= tolerance,
               abs(f.minY - rect.minY) <= tolerance,
               abs(f.width - rect.width) <= tolerance,
               abs(f.height - rect.height) <= tolerance {
                return candidate
            }
        }
        return .floating
    }

    private static func complementaryRegion(
        for primary: WindowLayoutState,
        in screen: CGRect,
        gap: CGFloat
    ) -> CGRect? {
        let m = Metrics(screen: screen, gap: gap)

        switch primary {
        case .leftHalf:
            return frame(for: .rightHalf, in: screen, gap: gap)
        case .rightHalf:
            return frame(for: .leftHalf, in: screen, gap: gap)
        case .leftTwoThirds:
            return frame(for: .rightThird, in: screen, gap: gap)
        case .rightTwoThirds:
            return frame(for: .leftThird, in: screen, gap: gap)
        case .leftThird:
            return m.rect(m.x0 + m.third + gap, m.y0, m.maxX, m.maxY)
        case .rightThird:
            return m.rect(m.x0, m.y0, m.maxX - m.third - gap, m.maxY)
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
            let top = (region.minY + CGFloat(i) * (h + gap)).rounded()
            return CGRect(x: region.minX, y: top,
                          width: region.width,
                          height: max(1, (top + h).rounded() - top))
        }
    }

    // MARK: - Geometry

    private struct Metrics {
        let x0, y0, w, h, gap: CGFloat

        init(screen: CGRect, gap: CGFloat) {
            self.gap = gap
            x0 = screen.minX + gap / 2
            y0 = screen.minY + gap / 2
            w = max(1, screen.width - gap)
            h = max(1, screen.height - gap)
        }

        var maxX: CGFloat { x0 + w }
        var maxY: CGFloat { y0 + h }
        /// Column widths reserve one `gap` for the seam between the two tiles.
        var half: CGFloat { max(1, (w - gap) / 2) }
        var third: CGFloat { max(1, (w - gap) / 3) }
        var twoThirds: CGFloat { max(1, (w - gap) - third) }
        var halfHeight: CGFloat { max(1, (h - gap) / 2) }

        /// Rounds edges rather than sizes so neighbouring tiles stay flush.
        func rect(_ minX: CGFloat, _ minY: CGFloat, _ maxX: CGFloat, _ maxY: CGFloat) -> CGRect {
            let x = minX.rounded(), y = minY.rounded()
            return CGRect(x: x, y: y,
                          width: max(1, maxX.rounded() - x),
                          height: max(1, maxY.rounded() - y))
        }
    }
}
