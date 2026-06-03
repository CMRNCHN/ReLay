import CoreGraphics

/// A CGRect expressed as 0–1 fractions of screen bounds.
/// Screen-size and display-change safe. Resolved to absolute coordinates at activation time.
public struct NormalizedRect: Codable, Equatable {
    public let x: CGFloat
    public let y: CGFloat
    public let width: CGFloat
    public let height: CGFloat

    public init(_ rect: CGRect) {
        x = rect.origin.x; y = rect.origin.y
        width = rect.size.width; height = rect.size.height
    }

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public func resolved(to screen: CGRect) -> CGRect {
        CGRect(
            x: screen.minX + x * screen.width,
            y: screen.minY + y * screen.height,
            width: width * screen.width,
            height: height * screen.height
        )
    }

    public static func normalize(_ rect: CGRect, in screen: CGRect) -> NormalizedRect {
        NormalizedRect(
            x: (rect.minX - screen.minX) / screen.width,
            y: (rect.minY - screen.minY) / screen.height,
            width: rect.width / screen.width,
            height: rect.height / screen.height
        )
    }
}
