import Foundation

/// Trust is per-workspace. Every workspace starts at .explicitOnly
/// and advances independently through the phase lifecycle.
enum TrustPhase: Codable, Equatable {
    case explicitOnly
    /// System may suggest; user must confirm each activation.
    /// Auto-promoted from explicitOnly after sufficient confirmed activations.
    case confirmedAutomation(activationCount: Int)
    /// System may auto-activate without prompt.
    /// NEVER auto-promoted — requires explicit user delegation per workspace.
    case ambientIntelligence
}

struct TrustRecord: Codable {
    var phase: TrustPhase = .explicitOnly
    var totalActivations: Int = 0
    var suggestedActivations: Int = 0

    var successRate: Double {
        guard totalActivations > 0 else { return 0 }
        return Double(suggestedActivations) / Double(totalActivations)
    }
}

// MARK: - Phase promotion thresholds

extension TrustPhase {
    static let confirmedAutomationMinActivations = 5
    static let confirmedAutomationMinSuccessRate = 0.70
}
