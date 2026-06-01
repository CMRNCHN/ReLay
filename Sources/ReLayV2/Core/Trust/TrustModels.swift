import Foundation

/// Trust is per-workspace. Every workspace starts at .explicitOnly
/// and advances independently through the phase lifecycle.
public enum TrustPhase: Codable, Equatable {
    case explicitOnly
    /// System may suggest; user must confirm each activation.
    /// Auto-promoted from explicitOnly after sufficient confirmed activations.
    case confirmedAutomation(activationCount: Int)
    /// System may auto-activate without prompt.
    /// NEVER auto-promoted — requires explicit user delegation per workspace.
    case ambientIntelligence
}

public struct TrustRecord: Codable {
    public var phase: TrustPhase = .explicitOnly
    public var totalActivations: Int = 0
    public var suggestedActivations: Int = 0

    public var successRate: Double {
        guard totalActivations > 0 else { return 0 }
        return Double(suggestedActivations) / Double(totalActivations)
    }

    public init() {}
}

// MARK: - Phase promotion thresholds

extension TrustPhase {
    static let confirmedAutomationMinActivations = 5
    static let confirmedAutomationMinSuccessRate = 0.70
}
