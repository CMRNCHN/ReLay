import Foundation

/// Persists named WorkspaceModel snapshots to JSON on disk.
/// Location: ~/Library/Application Support/ReLay/workspaces.json
public final class WorkspaceStore {

    public static let shared = WorkspaceStore()

    private let fileURL: URL
    private var workspaces: [String: WorkspaceModel] = [:]

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("ReLay", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("workspaces.json")
        load()
        AppLogger.log("workspace store loaded entries=\(workspaces.count)", subsystem: "window-engine")
    }

    // MARK: - CRUD

    public func save(_ workspace: WorkspaceModel) {
        workspaces[workspace.id] = workspace
        persist()
        AppLogger.log("workspace saved id=\(workspace.id) windows=\(workspace.windows.count)", subsystem: "window-engine")
    }

    public func workspace(id: String) -> WorkspaceModel? {
        workspaces[id]
    }

    public func all() -> [WorkspaceModel] {
        workspaces.values.sorted { $0.createdAt < $1.createdAt }
    }

    public func delete(id: String) {
        workspaces.removeValue(forKey: id)
        persist()
    }

    // MARK: - Disk I/O

    private func persist() {
        do {
            let data = try JSONEncoder().encode(workspaces)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.log("workspace store write error: \(error)", subsystem: "window-engine")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            workspaces = try JSONDecoder().decode([String: WorkspaceModel].self, from: data)
        } catch {
            AppLogger.log("workspace store read error: \(error)", subsystem: "window-engine")
        }
    }
}
