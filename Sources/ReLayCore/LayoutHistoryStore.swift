import Foundation

public final class LayoutHistoryStore {
    public static let shared = LayoutHistoryStore()
    
    private let fileManager = FileManager.default
    private let appSupportDir: URL
    private let workspacesURL: URL
    private let historyURL: URL
    private let savedLayoutsURL: URL

    private var workspaces: [WorkspacePreset] = []
    private var history: [AppliedLayoutEvent] = []
    private var savedLayouts: [SavedLayout] = []
    
    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appSupportDir = appSupport.appendingPathComponent("ReLay")
        workspacesURL = appSupportDir.appendingPathComponent("workspaces.json")
        historyURL    = appSupportDir.appendingPathComponent("layout-history.json")
        savedLayoutsURL = appSupportDir.appendingPathComponent("saved-layouts.json")
        
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
        if let data = try? Data(contentsOf: savedLayoutsURL),
           let decoded = try? JSONDecoder().decode([SavedLayout].self, from: data) {
            savedLayouts = decoded
        }
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(workspaces) {
            try? data.write(to: workspacesURL)
        }
        
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyURL)
        }
        if let data = try? JSONEncoder().encode(savedLayouts) {
            try? data.write(to: savedLayoutsURL)
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

    // MARK: - SavedLayout CRUD

    public func saveSavedLayout(_ layout: SavedLayout) {
        if let idx = savedLayouts.firstIndex(where: { $0.id == layout.id }) {
            savedLayouts[idx] = layout
        } else {
            savedLayouts.insert(layout, at: 0)
        }
        save()
    }

    public func deleteSavedLayout(id: UUID) {
        savedLayouts.removeAll { $0.id == id }
        save()
    }

    public func getSavedLayouts() -> [SavedLayout] { savedLayouts }

    public func touchSavedLayout(id: UUID) {
        if let idx = savedLayouts.firstIndex(where: { $0.id == id }) {
            savedLayouts[idx].lastUsedAt = Date()
            savedLayouts[idx].usageCount += 1
        }
        save()
    }

    // MARK: - App Favorites

    private let favoritesKey = "ReLayFavoriteApps"

    public func getFavoriteApps() -> [String] {
        UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
    }

    public func setFavoriteApp(_ bundleID: String, favorite: Bool) {
        var favs = getFavoriteApps()
        if favorite {
            if !favs.contains(bundleID) { favs.insert(bundleID, at: 0) }
        } else {
            favs.removeAll { $0 == bundleID }
        }
        UserDefaults.standard.set(favs, forKey: favoritesKey)
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
