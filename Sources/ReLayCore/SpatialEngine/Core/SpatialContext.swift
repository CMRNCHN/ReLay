import CoreGraphics

public struct SpatialContext {
    public let displays: [CGDirectDisplayID]
    public let activeSpace: Int?
    public let globalBounds: CGRect

    static func current(map: DisplaySpaceMap) -> SpatialContext {
        SpatialContext(
            displays: map.displays.map(\.id),
            activeSpace: nil, // CGSSpace APIs require private entitlement; reserved for future use
            globalBounds: map.globalBounds
        )
    }
}
