import CoreGraphics
import Foundation

// MARK: - WindowModel

// Lightweight, AX-free representation of a window in spatial space.
public struct WindowModel: Codable, Hashable, Identifiable {
    public let id: String              // stable identifier (bundle+title hash)
    public let appBundleID: String
    public let title: String?
    public var frame: SpatialFrame
    public let displayID: CGDirectDisplayID
    public let spaceID: Int?           // nil until CGSSpace APIs are available

    public init(
        id: String,
        appBundleID: String,
        title: String?,
        frame: SpatialFrame,
        displayID: CGDirectDisplayID,
        spaceID: Int?
    ) {
        self.id        = id
        self.appBundleID = appBundleID
        self.title     = title
        self.frame     = frame
        self.displayID = displayID
        self.spaceID   = spaceID
    }
}

// MARK: - WorkspaceModel

// The current set of windows active in the workspace.
public struct WorkspaceModel: Codable {
    public var windows: [WindowModel]
    public var displayMap: DisplaySpaceMap

    // The active bundle IDs in focus-recency order.
    public var recentBundleIDs: [String]

    public init(windows: [WindowModel] = [],
                displayMap: DisplaySpaceMap = DisplaySpaceMap.current(),
                recentBundleIDs: [String] = []) {
        self.windows           = windows
        self.displayMap        = displayMap
        self.recentBundleIDs   = recentBundleIDs
    }
}

// MARK: - SpatialState

// Single source of truth for the full spatial system at any given moment.
public struct SpatialState: Codable {
    public var workspace: WorkspaceModel
    public var spatialFrames: [SpatialFrame]
    public var displayMap: DisplaySpaceMap
    public var capturedAt: Date

    public init(
        workspace: WorkspaceModel = WorkspaceModel(),
        spatialFrames: [SpatialFrame] = [],
        displayMap: DisplaySpaceMap = DisplaySpaceMap.current(),
        capturedAt: Date = Date()
    ) {
        self.workspace     = workspace
        self.spatialFrames = spatialFrames
        self.displayMap    = displayMap
        self.capturedAt    = capturedAt
    }
}

// MARK: - DisplaySpaceMap: Codable

// DisplaySpaceMap lives in SpatialEngine/Core but needs Codable conformance here.
extension DisplaySpaceMap: Codable {
    enum CodingKeys: String, CodingKey { case displays }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displays, forKey: .displays)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.displays = try container.decode([DisplayInfo].self, forKey: .displays)
    }
}

extension DisplaySpaceMap.DisplayInfo: Codable {}
