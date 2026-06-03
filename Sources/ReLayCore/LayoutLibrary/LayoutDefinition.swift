import CoreGraphics
import Foundation

/// A named, persistent snapshot of window frames that can be restored on demand.
public struct LayoutDefinition: Codable {
    public let id: String
    public let name: String
    public let createdAt: Date
    public let windows: [WindowModel]

    public init(
        id: String = UUID().uuidString,
        name: String,
        createdAt: Date = Date(),
        windows: [WindowModel]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.windows = windows
    }
}
