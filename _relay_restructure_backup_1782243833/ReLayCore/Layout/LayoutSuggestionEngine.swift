import Foundation

struct LayoutSuggestionEngine {
    struct Context {
        let windows:           [LayoutWindowItem]
        let activeWindow:      LayoutWindowItem?
        let screenSize:        CGSize
        let isUltrawide:       Bool
        let recentTemplateIDs: [String]
        let workspaces:        [WorkspacePreset]
        let history:           [AppliedLayoutEvent]
    }

    struct Suggestion: Identifiable {
        let id:       String
        let template: LayoutTemplate
        let score:    Double
        let reason:   String
    }

    static func rank(context: Context) -> [Suggestion] {
#if DEBUG
        // GUARD 1 — active window consistency
        // context.activeWindow and LayoutWindowItem.isActive must agree on identity.
        // Mismatch means makeWindowItems() and the Context builder have diverged.
        if let explicit = context.activeWindow {
            let flaggedItems = context.windows.filter { $0.isActive }
            if !flaggedItems.isEmpty {
                let ids = Set(flaggedItems.map { $0.id })
                if !ids.contains(explicit.id) {
                    AppLogger.log(
                        "STRICT: activeWindow identity mismatch — explicit=\(explicit.id) flagged=\(ids.sorted().joined(separator: ","))",
                        subsystem: "suggestion"
                    )
                    for w in context.windows {
                        AppLogger.log(
                            "STRICT: window id=\(w.id) role=\(w.role) isActive=\(w.isActive)",
                            subsystem: "suggestion"
                        )
                    }
                    // do NOT auto-correct — log only
                }
            }
        }
#endif
        let templates    = LayoutTemplate.all
        let windowCount  = context.windows.count
        let roleCounts   = context.windows.reduce(into: [WindowRole: Int]()) { $0[$1.role, default: 0] += 1 }
        let roles        = Set(roleCounts.keys)
        let activeRole   = context.activeWindow?.role
        let currentBundleIDs = Set(context.windows.compactMap { $0.bundleID })
        let screenRatio  = context.screenSize.width / context.screenSize.height

        let suggestions: [Suggestion] = templates.map { template in
            var score:   Double = 0
            var reasons: [String] = []

            // 1. Window count match
            let countDiff = abs(template.slots.count - windowCount)
            if countDiff == 0 {
                score += 40
                reasons.append("\(windowCount) windows")
            } else if countDiff == 1 {
                score += 15
            }

            // 2. Template-owned scoring hints (replaces hardcoded template.id checks)
            for hint in template.scoringHints {
                guard hint.requiredRoles.isSubset(of: roles) else { continue }

                // Role frequency bonus: more instances of a required role = stronger signal
                let frequencyMultiplier = hint.requiredRoles.reduce(0) { $0 + (roleCounts[$1] ?? 0) }
                let hintScore = hint.bonus + Double(max(0, frequencyMultiplier - hint.requiredRoles.count)) * 5.0
                score += hintScore
                reasons.append(hint.reason)

                // Active window bonus: user is currently in the primary role for this template
                if let activeRole, let expectedActive = hint.activeRole, activeRole == expectedActive {
                    score += hint.activeBonus
                    reasons.append("Active")
                }
            }

            // 3. Generic slot role overlap (for templates with no matching hints)
            let templateRoles    = Set(template.slots.flatMap { $0.preferredRoles })
            let matchingRoles    = roles.intersection(templateRoles)
            let hintRolesHandled = Set(template.scoringHints.flatMap { $0.requiredRoles })
            let unhandledMatches = matchingRoles.subtracting(hintRolesHandled)
            if !unhandledMatches.isEmpty {
                score += Double(unhandledMatches.count) * 10
                let names = unhandledMatches.sorted { $0.rawValue < $1.rawValue }.map { $0.rawValue }.joined(separator: " + ")
                reasons.append(names)
            }

            // 4. Active window slot affinity (independent of hints)
            if let activeRole {
                let primarySlotRoles = Set(template.slots.first?.preferredRoles ?? [])
                if primarySlotRoles.contains(activeRole) {
                    score += 10
                }
            }

            // 5. Context match from history (adaptive learning)
            let contextMatches = context.history.filter { event in
                event.layoutTemplateID == template.id &&
                abs(event.screenAspectRatio - screenRatio) < 0.2 &&
                Set(event.visibleWindowRoles).isSubset(of: roles) &&
                roles.isSubset(of: Set(event.visibleWindowRoles))
            }
            let bundleMatches = contextMatches.filter { event in
                !Set(event.visibleAppBundleIDs).intersection(currentBundleIDs).isEmpty
            }
            if !contextMatches.isEmpty {
                let historyBoost = min(Double(contextMatches.count) * 8.0 + Double(bundleMatches.count) * 12.0, 80.0)
                score += historyBoost
                reasons.append("Context match")
            }

            // 6. Saved workspace boost
            let matchingWorkspaces = context.workspaces.filter { $0.layoutTemplateID == template.id }
            for workspace in matchingWorkspaces {
                let workspaceRoles = Set(workspace.slotRules.values.flatMap { $0 })
                if roles.isSuperset(of: workspaceRoles) {
                    score += 45.0
                    reasons.append("Matches \(workspace.name)")
                }
            }

            // 7. Ultrawide boost
            if context.isUltrawide && template.id == "thirds" {
                score += 20
                reasons.append("Ultrawide")
            }

            // 8. Recent usage boost
            if let index = context.recentTemplateIDs.firstIndex(of: template.id) {
                score += Double(max(0, 10 - index)) * 3.0
                if index == 0 { reasons.append("Recently used") }
            }

            // 9. Default suggested boost
            if template.isSuggested { score += 5 }

            return Suggestion(
                id:       template.id,
                template: template,
                score:    score,
                reason:   reasons.joined(separator: " • ")
            )
        }

        return suggestions.sorted { $0.score > $1.score }
    }
}

// --- Merged WindowRoleClassifier ---
import Foundation

public enum WindowRole: String, CaseIterable, Codable {
    case editor   = "Editor"
    case browser  = "Browser"
    case terminal = "Terminal"
    case chat     = "Chat"
    case notes    = "Notes"
    case meeting  = "Meeting"
    case mail     = "Mail"
    case design   = "Design"
    case media    = "Media"
    case ai       = "AI"
    case other    = "Other"
}

struct WindowRoleClassifier {

    // MARK: - Lookup tables (exact, lowercased app names)

    private static let meetingApps: Set<String> = [
        "zoom", "facetime", "microsoft teams", "google meet", "webex",
        "whereby", "around", "loom"
    ]

    private static let editorApps: Set<String> = [
        "xcode", "cursor", "visual studio code", "intellij idea", "appcode",
        "sublime text", "textedit", "nova", "zed", "windsurf", "fleet",
        "rubymine", "goland", "clion", "pycharm", "webstorm", "rider",
        "android studio", "emacs", "vim", "neovim", "bbedit", "coderunner"
    ]

    private static let browserApps: Set<String> = [
        "safari", "google chrome", "arc", "firefox", "microsoft edge",
        "brave browser", "opera", "vivaldi", "zen browser", "orion",
        "chromium", "min"
    ]

    private static let terminalApps: Set<String> = [
        "terminal", "iterm2", "warp", "ghostty", "kitty", "alacritty",
        "hyper", "tabby"
    ]

    private static let chatApps: Set<String> = [
        "slack", "discord", "messages", "whatsapp", "telegram",
        "signal", "beeper", "mattermost", "microsoft teams"
    ]

    private static let notesApps: Set<String> = [
        "notes", "obsidian", "notion", "craft", "bear", "drafts",
        "ulysses", "ia writer", "logseq", "roam research", "capacities",
        "apple notes"
    ]

    private static let mailApps: Set<String> = [
        "mail", "microsoft outlook", "spark", "airmail 5", "mimestream",
        "hey", "proton mail", "thunderbird", "canary mail"
    ]

    private static let designApps: Set<String> = [
        "figma", "sketch", "adobe photoshop", "adobe illustrator",
        "canva", "affinity designer", "affinity photo", "pixelmator pro",
        "inkscape", "principle", "framer", "origami studio", "rive",
        "adobe xd", "lunacy"
    ]

    private static let mediaApps: Set<String> = [
        "spotify", "apple music", "music", "vlc", "iina", "infuse",
        "plex", "youtube", "quicktime player", "final cut pro",
        "adobe premiere pro", "davinci resolve", "handbrake", "permute 3"
    ]

    private static let aiApps: Set<String> = [
        "chatgpt", "claude", "perplexity", "lm studio", "ollama",
        "jan", "msty", "diffusion bee", "draw things", "invoke ai",
        "copilot", "raycast"
    ]

    // MARK: - Title-based context signals

    private static let mediaTitleKeywords: [String] = [
        "youtube", "netflix", "twitch", "spotify", "hulu", "disney+",
        "apple tv", "prime video", "soundcloud"
    ]

    private static let meetingTitleKeywords: [String] = [
        "zoom", "google meet", "microsoft teams", "facetime", "webex"
    ]

    // MARK: - Classification

    static func classify(appName: String?, windowTitle: String?) -> WindowRole {
        let title = windowTitle?.lowercased() ?? ""

        // Title-based overrides first — a browser showing YouTube is media, not browser
        if meetingTitleKeywords.contains(where: { title.contains($0) }) { return .meeting }
        if mediaTitleKeywords.contains(where: { title.contains($0) })   { return .media   }

        guard let name = appName?.lowercased() else { return .other }

        if meetingApps.contains(name)  { return .meeting  }
        if editorApps.contains(name)   { return .editor   }
        if browserApps.contains(name)  { return .browser  }
        if terminalApps.contains(name) { return .terminal }
        if aiApps.contains(name)       { return .ai       }
        if chatApps.contains(name)     { return .chat     }
        if notesApps.contains(name)    { return .notes    }
        if mailApps.contains(name)     { return .mail     }
        if designApps.contains(name)   { return .design   }
        if mediaApps.contains(name)    { return .media    }

        return .other
    }
}
