import Foundation

/// Per-workspace trust lifecycle manager.
/// Trust phases are independent per workspace — one workspace reaching
/// ambientIntelligence does not affect any other workspace's phase.
public final class TrustStateMachine {

    private var records: [WorkspaceID: TrustRecord] = [:]

    public init() {}

    public func phase(for id: WorkspaceID) -> TrustPhase {
        records[id]?.phase ?? .explicitOnly
    }

    /// Called after the user activates a workspace.
    /// `wasSuggested` is true when the activation was in response to a system suggestion.
    public func recordActivation(for id: WorkspaceID, wasSuggested: Bool) {
        var record = records[id] ?? TrustRecord()
        record.totalActivations += 1
        if wasSuggested { record.suggestedActivations += 1 }
        records[id] = record
        evaluateAutoPromotion(for: id)
    }

    /// Promote to Phase 3. Only callable from explicit user action — never called internally.
    public func delegateAutomation(for id: WorkspaceID) {
        guard var record = records[id] else { return }
        if case .confirmedAutomation = record.phase {
            record.phase = .ambientIntelligence
            records[id] = record
        }
    }

    /// Revoke automation delegation, returning workspace to Phase 2.
    public func revokeAutomation(for id: WorkspaceID) {
        guard var record = records[id] else { return }
        if case .ambientIntelligence = record.phase {
            record.phase = .confirmedAutomation(activationCount: record.totalActivations)
            records[id] = record
        }
    }

    public func allowsAutoActivation(for id: WorkspaceID) -> Bool {
        phase(for: id) == .ambientIntelligence
    }

    // MARK: - Private

    private func evaluateAutoPromotion(for id: WorkspaceID) {
        guard var record = records[id] else { return }
        guard case .explicitOnly = record.phase else { return }

        if record.totalActivations >= TrustPhase.confirmedAutomationMinActivations,
           record.successRate >= TrustPhase.confirmedAutomationMinSuccessRate {
            record.phase = .confirmedAutomation(activationCount: record.totalActivations)
            records[id] = record
        }
    }
}
