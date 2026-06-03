import CoreGraphics

/// Metadata for a connected display at capture time.
public struct DisplayModel: Codable, Hashable {
    public let id: CGDirectDisplayID
    /// Full bounds in global screen coordinates (top-left origin, CG coordinates).
    public let frame: CGRect

    /// All currently active displays.
    public static func all() -> [DisplayModel] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return [] }
        return (0..<Int(count)).map { i in
            DisplayModel(id: ids[i], frame: CGDisplayBounds(ids[i]))
        }
    }
}
