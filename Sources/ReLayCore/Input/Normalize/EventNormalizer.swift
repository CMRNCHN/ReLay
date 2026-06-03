import Foundation

struct EventNormalizer {
    private let swipeThreshold = 2.0

    func normalize(_ raw: RawInputEvent) -> NormalizedEvent? {
        if let scale = raw.gestureScale, scale != 0 {
            return .pinch(scale: scale)
        }

        let absX = abs(raw.deltaX), absY = abs(raw.deltaY)
        guard absX > 0 || absY > 0 else { return nil }

        if absX > absY * 1.5 && absX > swipeThreshold {
            let velocity = absX
            let direction: Direction = raw.deltaX < 0 ? .left : .right
            return .swipe(direction: direction, velocity: velocity)
        }

        return .scroll(dx: raw.deltaX, dy: raw.deltaY)
    }
}
