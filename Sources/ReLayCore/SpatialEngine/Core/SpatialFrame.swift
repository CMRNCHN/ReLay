import CoreGraphics

public struct SpatialFrame: Codable, Hashable {
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat

    public static let zero = SpatialFrame(x: 0, y: 0, width: 0, height: 0)

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.width
        self.height = rect.height
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    public var origin: SpatialPoint { SpatialPoint(x: x, y: y) }
    public var maxX: CGFloat { x + width }
    public var maxY: CGFloat { y + height }

    func intersects(_ other: SpatialFrame) -> Bool {
        x < other.maxX && maxX > other.x && y < other.maxY && maxY > other.y
    }
}
