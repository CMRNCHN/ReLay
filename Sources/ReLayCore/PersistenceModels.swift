import Foundation

public struct WorkspacePreset: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let layoutTemplateID: String
    public let slotRules: [Int: [WindowRole]] // Slot Index -> Roles
    public let createdAt: Date
    public var lastUsedAt: Date
    public var usageCount: Int

    public init(id: UUID = UUID(), name: String, layoutTemplateID: String, slotRules: [Int: [WindowRole]], createdAt: Date = Date(), lastUsedAt: Date = Date(), usageCount: Int = 1) {
        self.id = id
        self.name = name
        self.layoutTemplateID = layoutTemplateID
        self.slotRules = slotRules
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.usageCount = usageCount
    }
}

public struct AppliedLayoutEvent: Codable {
    public let layoutTemplateID: String
    public let workspacePresetID: UUID?
    public let visibleWindowRoles: [WindowRole]
    public let visibleAppBundleIDs: [String]
    public let screenAspectRatio: Double
    public let displayCount: Int
    public let timestamp: Date

    public init(layoutTemplateID: String, workspacePresetID: UUID?, visibleWindowRoles: [WindowRole], visibleAppBundleIDs: [String], screenAspectRatio: Double, displayCount: Int, timestamp: Date = Date()) {
        self.layoutTemplateID = layoutTemplateID
        self.workspacePresetID = workspacePresetID
        self.visibleWindowRoles = visibleWindowRoles
        self.visibleAppBundleIDs = visibleAppBundleIDs
        self.screenAspectRatio = screenAspectRatio
        self.displayCount = displayCount
        self.timestamp = timestamp
    }
}
