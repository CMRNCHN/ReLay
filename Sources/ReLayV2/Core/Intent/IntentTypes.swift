import Foundation

/// The complete vocabulary of user actions.
/// All input modalities (gesture, keyboard, AI, command palette) produce Intent values.
/// Nothing downstream of IntentRouter knows which input produced an Intent.
enum Intent {
    case activateWorkspace(WorkspaceID)
    case createWorkspaceFromCurrent
    case snapWindow(bundleID: String, direction: SnapDirection)
    case enterExpose
    case undo
}

enum SnapDirection {
    case left, right, up, down
}

/// Advisory output from the learning system. Never triggers execution.
struct WorkspaceSuggestion {
    let workspaceID: WorkspaceID
    let workspaceName: String
    let trigger: SuggestionTrigger
    let confidence: Double
}

enum SuggestionTrigger {
    case appPattern
    case gitBranch(String)
    case manualRequest
}
