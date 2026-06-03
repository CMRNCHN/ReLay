import Foundation

/// Persists named LayoutDefinitions to JSON on disk.
/// Location: ~/Library/Application Support/ReLay/layouts.json
public final class LayoutStore {

    public static let shared = LayoutStore()

    private let fileURL: URL
    private var layouts: [String: LayoutDefinition] = [:]
    private let queue = DispatchQueue(label: "com.relay.LayoutStore", qos: .utility)

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("ReLay", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("layouts.json")
        load()
        AppLogger.log("layout store loaded entries=\(layouts.count)", subsystem: "window-engine")
    }

    // MARK: - CRUD

    public func save(_ layout: LayoutDefinition) {
        queue.async { [weak self] in
            self?.layouts[layout.id] = layout
            self?.persist()
        }
        AppLogger.log("layout saved id=\(layout.id) name=\(layout.name) windows=\(layout.windows.count)", subsystem: "window-engine")
    }

    public func layout(id: String) -> LayoutDefinition? {
        queue.sync { layouts[id] }
    }

    public func all() -> [LayoutDefinition] {
        queue.sync { layouts.values.sorted { $0.createdAt < $1.createdAt } }
    }

    public func delete(id: String) {
        queue.async { [weak self] in
            self?.layouts.removeValue(forKey: id)
            self?.persist()
        }
        AppLogger.log("layout deleted id=\(id)", subsystem: "window-engine")
    }

    public func update(_ layout: LayoutDefinition) {
        save(layout)
    }

    // MARK: - Disk I/O

    private func persist() {
        do {
            let data = try JSONEncoder().encode(layouts)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.log("layout store write error: \(error)", subsystem: "window-engine")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            layouts = try JSONDecoder().decode([String: LayoutDefinition].self, from: data)
        } catch {
            AppLogger.log("layout store read error: \(error)", subsystem: "window-engine")
        }
    }
}
