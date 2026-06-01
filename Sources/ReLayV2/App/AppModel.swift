import Foundation

@MainActor
public final class AppModel: ObservableObject {

    public let captureService   = WorkspaceCaptureService()
    public let workspaceStore   = WorkspaceStore()
    public let activationEngine: ActivationEngine
    public let trustMachine     = TrustStateMachine()

    @Published public var workspaces: [Workspace] = []
    @Published public var isCapturing = false

    public init() {
        activationEngine = ActivationEngine(captureService: captureService)
        workspaces = workspaceStore.all()
    }

    // MARK: - Capture

    public func captureWorkspace(name: String) {
        isCapturing = true
        let windows = captureService.captureWindows()
        let workspace = WorkspaceBuilder.build(from: windows, name: name)
        workspaceStore.save(workspace)
        workspaces = workspaceStore.all()
        isCapturing = false
    }

    // MARK: - Activate

    public func activate(_ workspace: Workspace) {
        activationEngine.activate(workspace)
        workspaceStore.recordActivation(workspace.id)
        trustMachine.recordActivation(for: workspace.id, wasSuggested: false)
        workspaces = workspaceStore.all()
    }

    // MARK: - Delete

    public func delete(_ workspace: Workspace) {
        workspaceStore.delete(workspace.id)
        workspaces = workspaceStore.all()
    }
}
