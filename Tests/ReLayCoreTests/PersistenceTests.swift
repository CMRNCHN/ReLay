import XCTest
@testable import ReLayCore

final class PersistenceTests: XCTestCase {
    
    func testWorkspaceStore() {
        let store = LayoutHistoryStore.shared
        let workspace = WorkspacePreset(
            name: "Test Workspace",
            layoutTemplateID: "split",
            slotRules: [0: [.editor], 1: [.browser]]
        )
        
        store.saveWorkspace(workspace)
        let workspaces = store.getWorkspaces()
        XCTAssertTrue(workspaces.contains(where: { $0.id == workspace.id }))
        
        store.deleteWorkspace(id: workspace.id)
        XCTAssertFalse(store.getWorkspaces().contains(where: { $0.id == workspace.id }))
    }
    
    func testHistoryStore() {
        let store = LayoutHistoryStore.shared
        let event = AppliedLayoutEvent(
            layoutTemplateID: "coding",
            workspacePresetID: nil,
            visibleWindowRoles: [.editor, .browser, .terminal],
            visibleAppBundleIDs: ["com.apple.dt.Xcode"],
            screenAspectRatio: 1.77,
            displayCount: 1
        )
        
        store.recordApply(event: event)
        let history = store.getHistory()
        XCTAssertTrue(history.contains(where: { $0.layoutTemplateID == "coding" }))
        XCTAssertEqual(store.getRecentTemplateIDs().first, "coding")
    }
}
