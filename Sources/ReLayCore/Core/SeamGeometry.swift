import CoreGraphics

// MARK: - Seam Geometry
// Shared gaps between tiled windows — where a Swish-style divider slider lives.

enum SeamAxis: Hashable {
    case vertical   // left | right
    case horizontal // top / bottom (AX: top has smaller Y)
}

struct Seam: Hashable {
    let axis: SeamAxis
    /// Center of the gap in AX coordinates (X for vertical, Y for horizontal).
    let center: CGFloat
    /// Overlap span along the seam (Y range for vertical, X range for horizontal).
    let spanMin: CGFloat
    let spanMax: CGFloat
    let firstIndex: Int  // left or top
    let secondIndex: Int // right or bottom
}

enum SeamGeometry {

    static let handleLength: CGFloat = 42
    static let handleThickness: CGFloat = 5
    static let hitPadding: CGFloat = 10

    /// Detect shared seams between window frames (AX space).
    static func seams(
        among frames: [CGRect],
        gap: CGFloat = LinkedResize.defaultGap,
        tolerance: CGFloat = LinkedResize.shareTolerance,
        minOverlap: CGFloat = LinkedResize.minOverlap
    ) -> [Seam] {
        var result: [Seam] = []
        guard frames.count >= 2 else { return result }

        for i in frames.indices {
            for j in frames.indices where j > i {
                let a = frames[i], b = frames[j]
                if LinkedResize.shares(.right, of: a, with: b, gap: gap, tolerance: tolerance, minOverlap: minOverlap) {
                    let overlapMin = max(a.minY, b.minY)
                    let overlapMax = min(a.maxY, b.maxY)
                    result.append(Seam(
                        axis: .vertical,
                        center: (a.maxX + b.minX) / 2,
                        spanMin: overlapMin,
                        spanMax: overlapMax,
                        firstIndex: i,
                        secondIndex: j
                    ))
                } else if LinkedResize.shares(.right, of: b, with: a, gap: gap, tolerance: tolerance, minOverlap: minOverlap) {
                    let overlapMin = max(a.minY, b.minY)
                    let overlapMax = min(a.maxY, b.maxY)
                    result.append(Seam(
                        axis: .vertical,
                        center: (b.maxX + a.minX) / 2,
                        spanMin: overlapMin,
                        spanMax: overlapMax,
                        firstIndex: j,
                        secondIndex: i
                    ))
                } else if LinkedResize.shares(.bottom, of: a, with: b, gap: gap, tolerance: tolerance, minOverlap: minOverlap) {
                    let overlapMin = max(a.minX, b.minX)
                    let overlapMax = min(a.maxX, b.maxX)
                    result.append(Seam(
                        axis: .horizontal,
                        center: (a.maxY + b.minY) / 2,
                        spanMin: overlapMin,
                        spanMax: overlapMax,
                        firstIndex: i,
                        secondIndex: j
                    ))
                } else if LinkedResize.shares(.bottom, of: b, with: a, gap: gap, tolerance: tolerance, minOverlap: minOverlap) {
                    let overlapMin = max(a.minX, b.minX)
                    let overlapMax = min(a.maxX, b.maxX)
                    result.append(Seam(
                        axis: .horizontal,
                        center: (b.maxY + a.minY) / 2,
                        spanMin: overlapMin,
                        spanMax: overlapMax,
                        firstIndex: j,
                        secondIndex: i
                    ))
                }
            }
        }
        return result
    }

    /// Compact handle rect centered on the seam (AX coordinates).
    static func handleRect(
        for seam: Seam,
        length: CGFloat = handleLength,
        thickness: CGFloat = handleThickness
    ) -> CGRect {
        let mid = (seam.spanMin + seam.spanMax) / 2
        let len = min(length, max(24, seam.spanMax - seam.spanMin - 16))
        switch seam.axis {
        case .vertical:
            return CGRect(
                x: seam.center - thickness / 2,
                y: mid - len / 2,
                width: thickness,
                height: len
            )
        case .horizontal:
            return CGRect(
                x: mid - len / 2,
                y: seam.center - thickness / 2,
                width: len,
                height: thickness
            )
        }
    }

    /// Hit-testing rect (larger than the visible pill).
    static func hitRect(for seam: Seam) -> CGRect {
        handleRect(for: seam).insetBy(dx: -hitPadding, dy: -hitPadding)
    }

    /// Split a pair across a moved divider center. Returns nil if either side
    /// would fall below `minSize`.
    static func frames(
        first: CGRect,
        second: CGRect,
        axis: SeamAxis,
        dividerCenter: CGFloat,
        gap: CGFloat = LinkedResize.defaultGap,
        minSize: CGFloat = LinkedResize.minNeighborSize
    ) -> (CGRect, CGRect)? {
        let half = gap / 2
        switch axis {
        case .vertical:
            let leftMax = (dividerCenter - half).rounded()
            let rightMin = (dividerCenter + half).rounded()
            let leftW = leftMax - first.minX
            let rightW = second.maxX - rightMin
            guard leftW >= minSize, rightW >= minSize else { return nil }
            let left = CGRect(x: first.minX, y: first.minY, width: leftW, height: first.height)
            let right = CGRect(x: rightMin, y: second.minY, width: rightW, height: second.height)
            return (left, right)

        case .horizontal:
            let topMax = (dividerCenter - half).rounded()
            let bottomMin = (dividerCenter + half).rounded()
            let topH = topMax - first.minY
            let bottomH = second.maxY - bottomMin
            guard topH >= minSize, bottomH >= minSize else { return nil }
            let top = CGRect(x: first.minX, y: first.minY, width: first.width, height: topH)
            let bottom = CGRect(x: second.minX, y: bottomMin, width: second.width, height: bottomH)
            return (top, bottom)
        }
    }
}
