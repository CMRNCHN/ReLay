import Foundation

typealias WorkspaceID = UUID

struct Workspace: Identifiable, Codable {
    let id: WorkspaceID
    var name: String
    var triggers: [WorkspaceTrigger]
    var layout: WorkspaceLayout
    var trustPhase: TrustPhase
    var createdAt: Date
    var lastActivatedAt: Date?
    var activationCount: Int

    init(
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

enum WorkspaceTrigger: Codable, Equatable {
    case appLaunch(bundleID: String)
    case manualShortcut(keyString: String)
    case gitBranch(pattern: String)   // reserved: not yet implemented
}

struct WorkspaceLayout: Codable {
    var appLayouts: [AppLayout]
}

struct AppLayout: Codable {
    let bundleID: String
    /// Frame as 0–1 fractions of screen bounds. Resolved at activation time.
    let normalizedFrame: NormalizedRect
}
