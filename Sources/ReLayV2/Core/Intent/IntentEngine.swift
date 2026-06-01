import Foundation

/// Receives Intent values from the input layer and routes them to WorkspaceStore + ActivationEngine.
/// Also observes context changes and surfaces suggestions when a matching workspace exists.
///
/// Data flow:
///   ContextEngine (observation) → IntentEngine (suggestion) → UI banner
///   Input layer (explicit) → IntentEngine → WorkspaceStore + ActivationEngine
final class IntentEngine {

    private let contextEngine:    ContextEngine
    private let workspaceStore:   WorkspaceStore
    private let trustMachine:     TrustStateMachine
    private let activationEngine: ActivationEngine

    private(set) var pendingSuggestion: WorkspaceSuggestion?
    var onSuggestion: ((WorkspaceSuggestion) -> Void)?

    init(
        contextEngine:    ContextEngine,
        workspaceStore:   WorkspaceStore,
        trustMachine:     TrustStateMachine,
        activationEngine: ActivationEngine
    ) {
        self.contextEngine    = contextEngine
        self.workspaceStore   = workspaceStore
        self.trustMachine     = trustMachine
        self.activationEngine = activationEngine

        contextEngine.onSnapshotChange { [weak self] snapshot in
            self?.evaluateSnapshot(snapshot)
        }
    }

    // MARK: - Explicit Intent Handling

    func handle(_ intent: Intent) {
        switch intent {

        case .activateWorkspace(let id):
            guard let workspace = workspaceStore.get(id) else { return }
            activationEngine.activate(workspace)
            trustMachine.recordActivation(for: id, wasSuggested: pendingSuggestion?.workspaceID == id)
            workspaceStore.recordActivation(id)
            pendingSuggestion = nil

        case .createWorkspaceFromCurrent:
            let captureService = WorkspaceCaptureService()
            let windows = captureService.captureWindows()
            let workspace = WorkspaceBuilder.build(from: windows, name: "Workspace")
            workspaceStore.save(workspace)

        case .snapWindow, .enterExpose, .undo:
            break
        }
    }

    // MARK: - Reactive Context Evaluation

    private func evaluateSnapshot(_ snapshot: AppSnapshot) {
        guard let workspace = workspaceStore.find(matching: snapshot.activeApps) else { return }

        if trustMachine.allowsAutoActivation(for: workspace.id) {
            // Phase 3: auto-activate — only reachable via explicit user delegation
            activationEngine.activate(workspace)
            trustMachine.recordActivation(for: workspace.id, wasSuggested: false)
            workspaceStore.recordActivation(workspace.id)
        } else {
            let suggestion = WorkspaceSuggestion(
                workspaceID: workspace.id,
                workspaceName: workspace.name,
                trigger: .appPattern,
                confidence: 1.0
            )
            pendingSuggestion = suggestion
            onSuggestion?(suggestion)
        }
    }
}
