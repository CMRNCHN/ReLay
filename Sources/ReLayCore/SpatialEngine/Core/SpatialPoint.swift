import CoreGraphics

public struct SpatialPoint: Codable, Hashable {
    public var x: CGFloat
    public var y: CGFloat

    public static let zero = SpatialPoint(x: 0, y: 0)

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    public init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }

    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}
