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
