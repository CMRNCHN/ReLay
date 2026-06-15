import AppKit
import Foundation

// MARK: - AppInfo

public struct AppInfo: Identifiable, Hashable {
    public let id: String           // bundle identifier
    public let name: String
    public let url: URL
    public var icon: NSImage?

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: AppInfo, rhs: AppInfo) -> Bool { lhs.id == rhs.id }
}

// MARK: - AppLibraryStore

public final class AppLibraryStore {
    public static let shared = AppLibraryStore()

    private(set) public var allApps: [AppInfo] = []
    private var byBundleID: [String: AppInfo] = [:]

    private init() { refresh() }

    // MARK: - Enumeration

    public func refresh() {
        var apps: [AppInfo] = []
        let fm = FileManager.default
        let searchDirs: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "\(NSHomeDirectory())/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
        ]
        for dir in searchDirs {
            guard let contents = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isApplicationKey], options: .skipsHiddenFiles
            ) else { continue }
            for url in contents where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bid = bundle.bundleIdentifier,
                      !bid.hasPrefix("com.apple.installer"),
                      !bid.hasPrefix("com.apple.dt.")  // Skip Xcode helper bundles
                else { continue }
                let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String
                    ?? bundle.infoDictionary?["CFBundleName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                let info = AppInfo(id: bid, name: name, url: url, icon: icon)
                if byBundleID[bid] == nil {   // first occurrence wins (avoids dupes)
                    apps.append(info)
                    byBundleID[bid] = info
                }
            }
        }
        allApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        AppLogger.log("app library: \(allApps.count) apps indexed", subsystem: "expose")
    }

    public func app(bundleID: String) -> AppInfo? { byBundleID[bundleID] }

    public func search(_ query: String) -> [AppInfo] {
        guard !query.isEmpty else { return allApps }
        return allApps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Layout-aware recommendations

    /// Returns recommended bundle IDs for a given template, filtered to installed apps.
    public func recommendations(for templateID: String) -> [AppInfo] {
        let candidates = layoutRecommendations[templateID]
            ?? layoutRecommendations["default"]
            ?? []
        let installed = candidates.compactMap { byBundleID[$0] }
        // Pad with popular running apps not already in the list
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppInfo? in
                guard let bid = app.bundleIdentifier, byBundleID[bid] != nil,
                      !candidates.contains(bid) else { return nil }
                return byBundleID[bid]
            }
        return Array((installed + running).prefix(8))
    }

    // Map template IDs → ordered preferred bundle IDs (most relevant first)
    private let layoutRecommendations: [String: [String]] = [
        "coding": [
            "com.microsoft.VSCode",
            "com.apple.dt.Xcode",
            "com.todesktop.230313mzl4w4u92",  // Cursor
            "com.googlecode.iterm2",
            "com.apple.Terminal",
            "com.openai.chat",
            "com.apple.Safari",
            "com.runningwithcrayons.Alfred",
        ],
        "research": [
            "com.apple.Safari",
            "org.mozilla.firefox",
            "company.thebrowser.Browser",     // Arc
            "com.openai.chat",
            "md.obsidian",
            "com.apple.Notes",
            "com.pdfexpert.pdfexpert",
            "com.readdle.PDFExpert",
        ],
        "meeting": [
            "us.zoom.xos",
            "com.microsoft.teams2",
            "com.apple.FaceTime",
            "com.apple.Notes",
            "com.openai.chat",
            "com.apple.Reminders",
            "com.apple.Mail",
        ],
        "split": [
            "com.apple.Safari",
            "com.microsoft.VSCode",
            "com.openai.chat",
            "com.apple.Notes",
            "com.apple.Mail",
        ],
        "thirds": [
            "com.apple.Safari",
            "com.microsoft.VSCode",
            "com.googlecode.iterm2",
            "com.openai.chat",
            "com.apple.Notes",
        ],
        "grid4": [
            "com.apple.Safari",
            "com.openai.chat",
            "com.apple.Notes",
            "com.apple.Mail",
            "com.apple.Reminders",
            "com.googlecode.iterm2",
        ],
        "default": [
            "com.apple.Safari",
            "com.openai.chat",
            "com.apple.Notes",
            "com.apple.Mail",
            "com.apple.Finder",
        ],
    ]
}
