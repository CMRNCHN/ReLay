import Foundation

/// Top-level dependency graph for the v2 architecture.
/// Owns all core engine instances and wires them together.
/// The gesture pipeline (v1) integrates by calling intentEngine.handle(_:).
@MainActor
final class AppModel: ObservableObject {

    let contextEngine    = ContextEngine()
    let workspaceStore   = WorkspaceStore()
    let activationEngine = ActivationEngine()
    let trustMachine     = TrustStateMachine()
    let permissions      = PermissionService()
    let intentEngine:      IntentEngine

    @Published var pendingSuggestion: WorkspaceSuggestion?
    @Published var isFirstLaunch: Bool

    init() {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "ReLayV2HasLaunched")
        isFirstLaunch = !hasLaunchedBefore

        intentEngine = IntentEngine(
            contextEngine:    contextEngine,
            workspaceStore:   workspaceStore,
            trustMachine:     trustMachine,
            activationEngine: activationEngine
        )

        intentEngine.onSuggestion = { [weak self] suggestion in
            Task { @MainActor [weak self] in
                self?.pendingSuggestion = suggestion
            }
        }
    }

    func acknowledgeFirstLaunch() {
        UserDefaults.standard.set(true, forKey: "ReLayV2HasLaunched")
        isFirstLaunch = false
    }

    func dismissSuggestion() {
        pendingSuggestion = nil
    }

    func acceptSuggestion() {
        guard let suggestion = pendingSuggestion else { return }
        intentEngine.handle(.activateWorkspace(suggestion.workspaceID))
    }
}
