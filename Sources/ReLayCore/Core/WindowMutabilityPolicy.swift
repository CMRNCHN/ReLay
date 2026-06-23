import Foundation

// MARK: - Profile

struct WindowMutabilityProfile {
    let bundleID: String
    let supportsAXPosition: Bool
    let supportsAXSize: Bool
    let isResponsiveToAX: Bool
    let lastKnownFailureRate: Double
}

// MARK: - Decision

enum WindowMutabilityDecision {
    case allow       // known movable — write position + size
    case deny        // known non-movable — no AX write
    case skipWindow  // unknown app — no AX write (default)
}

// MARK: - Policy
// Single source of truth. Pure function. No side effects.
// entries populated from AXTest survey output only — never guessed.
// Default: deny-by-absence. Unknown apps never move.

enum WindowMutabilityPolicy {

    static let defaultDecision: WindowMutabilityDecision = .skipWindow

    private static let entries: [String: WindowMutabilityProfile] = [
        "com.apple.finder": WindowMutabilityProfile(
            bundleID: "com.apple.finder",
            supportsAXPosition: true,
            supportsAXSize: true,
            isResponsiveToAX: true,
            lastKnownFailureRate: 0.0
        ),
        "com.apple.Safari": WindowMutabilityProfile(
            bundleID: "com.apple.Safari",
            supportsAXPosition: true,
            supportsAXSize: true,
            isResponsiveToAX: true,
            lastKnownFailureRate: 0.0
        ),
        "com.microsoft.VSCode": WindowMutabilityProfile(
            bundleID: "com.microsoft.VSCode",
            supportsAXPosition: true,
            supportsAXSize: true,
            isResponsiveToAX: true,
            lastKnownFailureRate: 0.0
        ),
        "com.googlecode.iterm2": WindowMutabilityProfile(
            bundleID: "com.googlecode.iterm2",
            supportsAXPosition: true,
            supportsAXSize: true,
            isResponsiveToAX: true,
            lastKnownFailureRate: 0.0
        ),
        "com.anthropic.claudefordesktop": WindowMutabilityProfile(
            bundleID: "com.anthropic.claudefordesktop",
            supportsAXPosition: true,
            supportsAXSize: true,
            isResponsiveToAX: true,
            lastKnownFailureRate: 0.0
        ),
        "com.apple.Terminal": WindowMutabilityProfile(
            bundleID: "com.apple.Terminal",
            supportsAXPosition: true,
            supportsAXSize: true,
            isResponsiveToAX: true,
            lastKnownFailureRate: 0.0
        ),
        "com.apple.mail": WindowMutabilityProfile(
            bundleID: "com.apple.mail",
            supportsAXPosition: true,
            supportsAXSize: true,
            isResponsiveToAX: true,
            lastKnownFailureRate: 0.0
        ),
    ]

    static func decision(for bundleID: String) -> WindowMutabilityDecision {
        guard let profile = entries[bundleID] else { return defaultDecision }
        return evaluate(profile)
    }

    private static func evaluate(_ profile: WindowMutabilityProfile) -> WindowMutabilityDecision {
        guard profile.isResponsiveToAX                                      else { return .deny }
        guard profile.lastKnownFailureRate < 0.5                            else { return .deny }
        if profile.supportsAXPosition && profile.lastKnownFailureRate < 0.2 { return .allow }
        return .deny
    }
}
