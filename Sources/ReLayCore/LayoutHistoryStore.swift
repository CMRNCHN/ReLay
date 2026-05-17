import Foundation

public final class LayoutHistoryStore {
    public static let shared = LayoutHistoryStore()
    
    private let fileManager = FileManager.default
    private let appSupportDir: URL
    private let workspacesURL: URL
    private let historyURL: URL
    
    private var workspaces: [WorkspacePreset] = []
    private var history: [AppliedLayoutEvent] = []
    
    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appSupportDir = appSupport.appendingPathComponent("ReLay")
        workspacesURL = appSupportDir.appendingPathComponent("workspaces.json")
        historyURL = appSupportDir.appendingPathComponent("layout-history.json")
        
        try? fileManager.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        
        load()
    }
    
    private func load() {
        if let data = try? Data(contentsOf: workspacesURL),
           let decoded = try? JSONDecoder().decode([WorkspacePreset].self, from: data) {
            workspaces = decoded
        }
        
        if let data = try? Data(contentsOf: historyURL),
           let decoded = try? JSONDecoder().decode([AppliedLayoutEvent].self, from: data) {
            history = decoded
        }
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(workspaces) {
            try? data.write(to: workspacesURL)
        }
        
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyURL)
        }
    }
    
    public func recordApply(event: AppliedLayoutEvent) {
        history.insert(event, at: 0)
        // Keep only last 100
        if history.count > 100 {
            history.removeLast()
        }
        
        // Update workspace if applicable
        if let workspaceID = event.workspacePresetID,
           let index = workspaces.firstIndex(where: { $0.id == workspaceID }) {
            workspaces[index].lastUsedAt = Date()
            workspaces[index].usageCount += 1
        }
        
        save()
    }
    
    public func saveWorkspace(_ workspace: WorkspacePreset) {
        workspaces.append(workspace)
        save()
    }
    
    public func deleteWorkspace(id: UUID) {
        workspaces.removeAll { $0.id == id }
        save()
    }
    
    public func getWorkspaces() -> [WorkspacePreset] {
        return workspaces
    }
    
    public func getHistory() -> [AppliedLayoutEvent] {
        return history
    }

    public func getRecentTemplateIDs() -> [String] {
        let ids = history.map { $0.layoutTemplateID }
        var uniqueIds: [String] = []
        for id in ids {
            if !uniqueIds.contains(id) {
                uniqueIds.append(id)
            }
            if uniqueIds.count >= 10 { break }
        }
        return uniqueIds
    }
}
