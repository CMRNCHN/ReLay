import Foundation

/// Single authority for workspace reads and writes.
/// Persists to JSON in Application Support.
public final class WorkspaceStore {

    private var workspaces: [WorkspaceID: Workspace] = [:]
    private let storeURL: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ReLay")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("workspaces-v2.json")
        load()
    }

    public func get(_ id: WorkspaceID) -> Workspace? { workspaces[id] }

    public func all() -> [Workspace] {
        workspaces.values.sorted { $0.createdAt < $1.createdAt }
    }

    public func save(_ workspace: Workspace) {
        workspaces[workspace.id] = workspace
        persist()
    }

    public func delete(_ id: WorkspaceID) {
        workspaces.removeValue(forKey: id)
        persist()
    }

    public func recordActivation(_ id: WorkspaceID) {
        guard var w = workspaces[id] else { return }
        w.activationCount += 1
        w.lastActivatedAt = Date()
        workspaces[id] = w
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(Array(workspaces.values)) else { return }
        try? data.write(to: storeURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let loaded = try? JSONDecoder().decode([Workspace].self, from: data) else { return }
        workspaces = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
    }
}
