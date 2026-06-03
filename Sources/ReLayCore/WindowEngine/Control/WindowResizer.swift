import CoreGraphics

/// Resizes a window independently of its position.
public final class WindowResizer {

    private let mover = WindowMover()

    public init() {}

    /// Resizes `window` to `size`, keeping the top-left corner anchored.
    public func resize(window: WindowModel, to size: CGSize) {
        var frame = window.frame
        frame.size = size
        mover.move(window: window, to: frame)
    }

    /// Applies a size delta to `window` (positive = grow, negative = shrink).
    public func applyDelta(window: WindowModel, delta: CGSize) {
        var frame = window.frame
        frame.size.width  = max(100, frame.size.width  + delta.width)
        frame.size.height = max(100, frame.size.height + delta.height)
        mover.move(window: window, to: frame)
    }
}
