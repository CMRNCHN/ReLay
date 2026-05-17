import Foundation
import AppKit

struct LayoutSuggestionEngine {
    struct Context {
        let windows: [LayoutWindowItem]
        let activeWindow: LayoutWindowItem?
        let screenSize: CGSize
        let isUltrawide: Bool
        let recentTemplateIDs: [String]
        let workspaces: [WorkspacePreset]
        let history: [AppliedLayoutEvent]
    }
    
    struct Suggestion: Identifiable {
        let id: String
        let template: LayoutTemplate
        let score: Double
        let reason: String
    }

    static func rank(context: Context) -> [Suggestion] {
        let templates = LayoutTemplate.all
        let windowCount = context.windows.count
        let roles = Set(context.windows.map { $0.role })
        let currentBundleIDs = Set(context.windows.compactMap { $0.bundleID })
        let screenRatio = context.screenSize.width / context.screenSize.height
        
        var suggestions: [Suggestion] = templates.map { template in
            var score: Double = 0
            var reasons: [String] = []
            
            // 1. Window Count Match
            let countDiff = abs(template.slots.count - windowCount)
            if countDiff == 0 {
                score += 40
                reasons.append("\(windowCount) windows")
            } else if countDiff == 1 {
                score += 15
            }
            
            // 2. Role matching (Specific & Generic)
            var roleMatchScore: Double = 0
            if template.id == "coding" && roles.contains(.editor) && roles.contains(.terminal) {
                roleMatchScore += 30
                reasons.append("IDE + Terminal")
            } else if template.id == "research" && roles.contains(.browser) && roles.contains(.notes) {
                roleMatchScore += 25
                reasons.append("Browser + Notes")
            } else if template.id == "meeting" && roles.contains(.meeting) {
                roleMatchScore += 50
                reasons.append("Meeting active")
            } else {
                let templateRoles = Set(template.slots.flatMap { $0.preferredRoles })
                let matchingRoles = roles.intersection(templateRoles)
                if !matchingRoles.isEmpty {
                    roleMatchScore += Double(matchingRoles.count) * 10
                    let roleNames = matchingRoles.sorted(by: { $0.rawValue < $1.rawValue }).map { $0.rawValue }.joined(separator: " + ")
                    reasons.append(roleNames)
                }
            }
            score += roleMatchScore
            
            // 3. Context Match from History (Adaptive Learning)
            let contextMatches = context.history.filter { event in
                event.layoutTemplateID == template.id &&
                abs(event.screenAspectRatio - screenRatio) < 0.2 &&
                Set(event.visibleWindowRoles).isSubset(of: roles) &&
                roles.isSubset(of: Set(event.visibleWindowRoles))
            }
            
            // Further refine with bundle IDs if available
            let bundleMatches = contextMatches.filter { event in
                !Set(event.visibleAppBundleIDs).intersection(currentBundleIDs).isEmpty
            }
            
            if !contextMatches.isEmpty {
                let historyBoost = min(Double(contextMatches.count) * 8.0 + Double(bundleMatches.count) * 12.0, 80.0)
                score += historyBoost
                reasons.append("Context match")
            }

            // 4. Saved Workspace Boost
            let matchingWorkspaces = context.workspaces.filter { $0.layoutTemplateID == template.id }
            for workspace in matchingWorkspaces {
                let workspaceRoles = Set(workspace.slotRules.values.flatMap { $0 })
                if roles.isSuperset(of: workspaceRoles) {
                    score += 45.0
                    reasons.append("Matches \(workspace.name)")
                }
            }
            
            // 5. Ultrawide boost
            if context.isUltrawide && template.id == "thirds" {
                score += 20
                reasons.append("Ultrawide")
            }
            
            // 6. Recent usage boost
            if let index = context.recentTemplateIDs.firstIndex(of: template.id) {
                let recencyBoost = Double(max(0, 10 - index)) * 3.0
                score += recencyBoost
                if index == 0 {
                    reasons.append("Recently used")
                }
            }

            // 7. Default suggested boost
            if template.isSuggested {
                score += 5
            }

            return Suggestion(
                id: template.id,
                template: template,
                score: score,
                reason: reasons.joined(separator: " • ")
            )
        }
        
        suggestions.sort { $0.score > $1.score }
        return suggestions
    }
}
