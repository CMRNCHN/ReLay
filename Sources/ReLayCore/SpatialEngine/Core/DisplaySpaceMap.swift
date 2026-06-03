import CoreGraphics
import Cocoa

// Snapshot of all active displays and their normalized bounds.
struct DisplaySpaceMap {
    struct DisplayInfo {
        let id: CGDirectDisplayID
        let bounds: SpatialFrame   // in unified coordinate space
        let scaleFactor: CGFloat
    }

    let displays: [DisplayInfo]

    // Unified bounding rect enclosing all displays.
    var globalBounds: CGRect {
        displays.reduce(CGRect.null) { $0.union($1.bounds.cgRect) }
    }

    static func current() -> DisplaySpaceMap {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &displayIDs, &count)

        let screens = NSScreen.screens
        let primary = screens.first?.frame ?? .zero

        let infos: [DisplayInfo] = (0..<Int(count)).compactMap { i in
            let id = displayIDs[i]
            let bounds = CGDisplayBounds(id)
            // Flip y to match AX coordinate space (top-left origin).
            let flippedY = primary.height - bounds.origin.y - bounds.height
            let scaleFactor = CGFloat(CGDisplayScreenSize(id).width > 0
                ? CGDisplayPixelsWide(id) : 1)
            return DisplayInfo(
                id: id,
                bounds: SpatialFrame(x: bounds.origin.x, y: flippedY,
                                     width: bounds.width, height: bounds.height),
                scaleFactor: scaleFactor
            )
        }
        return DisplaySpaceMap(displays: infos)
    }

    func displayContaining(_ frame: SpatialFrame) -> DisplayInfo? {
        displays.max { a, b in
            intersection(a.bounds, frame) < intersection(b.bounds, frame)
        }
    }

    private func intersection(_ a: SpatialFrame, _ b: SpatialFrame) -> CGFloat {
        let ix = max(0, min(a.maxX, b.maxX) - max(a.x, b.x))
        let iy = max(0, min(a.maxY, b.maxY) - max(a.y, b.y))
        return ix * iy
    }
}
