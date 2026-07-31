import CoreGraphics

// MARK: - Linked Resize
// Pure geometry for "drag this window's edge → resize neighbors that share it".

enum WindowEdge: Hashable, CaseIterable {
    case left, right, top, bottom
}

enum LinkedResize {

    static let edgeThickness: CGFloat = 10
    static let shareTolerance: CGFloat = 18
    static let minOverlap: CGFloat = 60
    static let minNeighborSize: CGFloat = 160
    static let defaultGap: CGFloat = 8

    /// Which outer edge of `frame` contains `point`, if any.
    /// On a true corner hit, prefers the nearer axis.
    static func edge(at point: CGPoint, of frame: CGRect, thickness: CGFloat = edgeThickness) -> WindowEdge? {
        let hit = edges(at: point, of: frame, thickness: thickness)
        switch hit.count {
        case 1:
            return hit[0]
        case 2:
            func distance(_ edge: WindowEdge) -> CGFloat {
                switch edge {
                case .left:   return abs(point.x - frame.minX)
                case .right:  return abs(point.x - frame.maxX)
                case .top:    return abs(point.y - frame.minY)
                case .bottom: return abs(point.y - frame.maxY)
                }
            }
            return hit.min(by: { distance($0) < distance($1) })
        default:
            return nil
        }
    }

    static func edges(at point: CGPoint, of frame: CGRect, thickness: CGFloat = edgeThickness) -> [WindowEdge] {
        var hit: [WindowEdge] = []
        let inset = frame.insetBy(dx: -thickness, dy: -thickness)
        guard inset.contains(point) else { return [] }

        let alongY = point.y >= frame.minY - thickness && point.y <= frame.maxY + thickness
        let alongX = point.x >= frame.minX - thickness && point.x <= frame.maxX + thickness

        if alongY, abs(point.x - frame.minX) <= thickness { hit.append(.left) }
        if alongY, abs(point.x - frame.maxX) <= thickness { hit.append(.right) }
        if alongX, abs(point.y - frame.minY) <= thickness { hit.append(.top) }
        if alongX, abs(point.y - frame.maxY) <= thickness { hit.append(.bottom) }
        return hit
    }

    /// Indices of `others` that share `edge` of `primary` (within gap + tolerance).
    static func neighborIndices(
        of primary: CGRect,
        edge: WindowEdge,
        among others: [CGRect],
        gap: CGFloat = defaultGap,
        tolerance: CGFloat = shareTolerance,
        minOverlap: CGFloat = minOverlap
    ) -> [Int] {
        others.indices.filter { i in
            shares(edge, of: primary, with: others[i], gap: gap, tolerance: tolerance, minOverlap: minOverlap)
        }
    }

    static func shares(
        _ edge: WindowEdge,
        of primary: CGRect,
        with other: CGRect,
        gap: CGFloat = defaultGap,
        tolerance: CGFloat = shareTolerance,
        minOverlap: CGFloat = minOverlap
    ) -> Bool {
        switch edge {
        case .right:
            let seam = abs(other.minX - primary.maxX)
            guard seam <= gap + tolerance else { return false }
            return verticalOverlap(primary, other) >= minOverlap
        case .left:
            let seam = abs(primary.minX - other.maxX)
            guard seam <= gap + tolerance else { return false }
            return verticalOverlap(primary, other) >= minOverlap
        case .bottom:
            let seam = abs(other.minY - primary.maxY)
            guard seam <= gap + tolerance else { return false }
            return horizontalOverlap(primary, other) >= minOverlap
        case .top:
            let seam = abs(primary.minY - other.maxY)
            guard seam <= gap + tolerance else { return false }
            return horizontalOverlap(primary, other) >= minOverlap
        }
    }

    /// New frame for a neighbor after `primary` was resized along `edge`.
    /// Keeps the neighbor's far edge fixed; slides the shared edge to stay flush.
    static func resizedNeighbor(
        _ neighbor: CGRect,
        sharing edge: WindowEdge,
        primaryNow: CGRect,
        gap: CGFloat = defaultGap,
        minSize: CGFloat = minNeighborSize
    ) -> CGRect? {
        switch edge {
        case .right:
            let newMinX = (primaryNow.maxX + gap).rounded()
            let newWidth = neighbor.maxX - newMinX
            guard newWidth >= minSize else { return nil }
            return CGRect(x: newMinX, y: neighbor.minY, width: newWidth, height: neighbor.height)

        case .left:
            let newMaxX = (primaryNow.minX - gap).rounded()
            let newWidth = newMaxX - neighbor.minX
            guard newWidth >= minSize else { return nil }
            return CGRect(x: neighbor.minX, y: neighbor.minY, width: newWidth, height: neighbor.height)

        case .bottom:
            let newMinY = (primaryNow.maxY + gap).rounded()
            let newHeight = neighbor.maxY - newMinY
            guard newHeight >= minSize else { return nil }
            return CGRect(x: neighbor.minX, y: newMinY, width: neighbor.width, height: newHeight)

        case .top:
            let newMaxY = (primaryNow.minY - gap).rounded()
            let newHeight = newMaxY - neighbor.minY
            guard newHeight >= minSize else { return nil }
            return CGRect(x: neighbor.minX, y: neighbor.minY, width: neighbor.width, height: newHeight)
        }
    }

    private static func verticalOverlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
    }

    private static func horizontalOverlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
    }
}
