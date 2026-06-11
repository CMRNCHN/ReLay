import Foundation

public typealias WorkspaceID = UUID

public struct Workspace: Identifiable, Codable {
    public let id: WorkspaceID
    public var name: String
    public var triggers: [WorkspaceTrigger]
    public var layout: WorkspaceLayout
    public var trustPhase: TrustPhase
    public var createdAt: Date
    public var lastActivatedAt: Date?
    public var activationCount: Int

    public init(
        id: WorkspaceID = UUID(),
        name: String,
        triggers: [WorkspaceTrigger] = [],
        layout: WorkspaceLayout,
        trustPhase: TrustPhase = .explicitOnly
    ) {
        self.id = id
        self.name = name
        self.triggers = triggers
        self.layout = layout
        self.trustPhase = trustPhase
        self.createdAt = Date()
        self.lastActivatedAt = nil
        self.activationCount = 0
    }
}

public enum WorkspaceTrigger: Codable, Equatable {
    case appLaunch(bundleID: String)
    case manualShortcut(keyString: String)
    case gitBranch(pattern: String)   // reserved: not yet implemented
}

public struct WorkspaceLayout: Codable {
    public var appLayouts: [AppLayout]
    public init(appLayouts: [AppLayout]) { self.appLayouts = appLayouts }
}

public struct AppLayout: Codable {
    public let bundleID: String
    public let windowTitle: String
    /// Frame as 0–1 fractions of screen bounds. Resolved at activation time.
    public let normalizedFrame: NormalizedRect
    /// CGDirectDisplayID as String for display-aware resolution.
    public let displayID: String

    public init(bundleID: String, windowTitle: String, normalizedFrame: NormalizedRect, displayID: String) {
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.normalizedFrame = normalizedFrame
        self.displayID = displayID
    }
}
