import XCTest
import ApplicationServices
@testable import ReLayCore

final class SmartSuggestionTests: XCTestCase {
    
    // Mock AXUIElement
    private class MockAXUIElement {
        // Just to have something to use
    }

    func testWindowRoleClassifier() {
        XCTAssertEqual(WindowRoleClassifier.classify(appName: "Xcode", windowTitle: "Project.swift"), .editor)
        XCTAssertEqual(WindowRoleClassifier.classify(appName: "Safari", windowTitle: "Google"), .browser)
        XCTAssertEqual(WindowRoleClassifier.classify(appName: "iTerm2", windowTitle: "zsh"), .terminal)
        XCTAssertEqual(WindowRoleClassifier.classify(appName: "Slack", windowTitle: "General"), .chat)
        XCTAssertEqual(WindowRoleClassifier.classify(appName: "Zoom", windowTitle: "Meeting"), .meeting)
        XCTAssertEqual(WindowRoleClassifier.classify(appName: "Google Chrome", windowTitle: "Zoom Meeting"), .meeting)
        XCTAssertEqual(WindowRoleClassifier.classify(appName: "UnknownApp", windowTitle: "UnknownTitle"), .other)
    }
    
    func testLayoutSuggestionEngine() {
        let windows: [LayoutWindowItem] = [
            mockItem(id: "1", app: "Xcode", title: "Code", role: .editor),
            mockItem(id: "2", app: "Safari", title: "Docs", role: .browser),
            mockItem(id: "3", app: "iTerm", title: "Terminal", role: .terminal)
        ]
        
        let context = LayoutSuggestionEngine.Context(
            windows: windows,
            activeWindow: windows[0],
            screenSize: CGSize(width: 1920, height: 1080),
            isUltrawide: false,
            recentTemplateIDs: [],
            workspaces: [],
            history: []
        )
        
        let suggestions = LayoutSuggestionEngine.rank(context: context)
        
        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertEqual(suggestions[0].template.id, "coding", "Coding should be top suggestion for Editor+Browser+Terminal")
        XCTAssertTrue(suggestions[0].reason.contains("IDE + Terminal"))
    }

    func testAdaptiveLearningBoost() {
        let windows: [LayoutWindowItem] = [
            mockItem(id: "1", app: "Xcode", title: "Code", role: .editor),
            mockItem(id: "2", app: "Safari", title: "Docs", role: .browser)
        ]
        
        let currentRoles = windows.map { $0.role }
        
        // Setup history where "split" was used many times for these roles
        let history = (1...10).map { _ in
            AppliedLayoutEvent(
                layoutTemplateID: "split",
                workspacePresetID: nil,
                visibleWindowRoles: currentRoles,
                visibleAppBundleIDs: [],
                screenAspectRatio: 1920.0/1080.0,
                displayCount: 1
            )
        }
        
        let context = LayoutSuggestionEngine.Context(
            windows: windows,
            activeWindow: windows[0],
            screenSize: CGSize(width: 1920, height: 1080),
            isUltrawide: false,
            recentTemplateIDs: [],
            workspaces: [],
            history: history
        )
        
        let suggestions = LayoutSuggestionEngine.rank(context: context)
        
        XCTAssertEqual(suggestions[0].template.id, "split", "Split should be boosted by history")
        XCTAssertTrue(suggestions[0].reason.contains("Context match"))
    }

    func testWorkspaceBoost() {
        let windows: [LayoutWindowItem] = [
            mockItem(id: "1", app: "Xcode", title: "Code", role: .editor),
            mockItem(id: "2", app: "Slack", title: "Chat", role: .chat)
        ]
        
        let workspace = WorkspacePreset(
            name: "My Setup",
            layoutTemplateID: "split",
            slotRules: [0: [.editor], 1: [.chat]]
        )
        
        let context = LayoutSuggestionEngine.Context(
            windows: windows,
            activeWindow: windows[0],
            screenSize: CGSize(width: 1920, height: 1080),
            isUltrawide: false,
            recentTemplateIDs: [],
            workspaces: [workspace],
            history: []
        )
        
        let suggestions = LayoutSuggestionEngine.rank(context: context)
        
        XCTAssertEqual(suggestions[0].template.id, "split")
        XCTAssertTrue(suggestions[0].reason.contains("Matches My Setup"))
    }
    
    func testAutoFillLogic() {
        let template = LayoutTemplate.all.first { $0.id == "coding" }!
        let windows: [LayoutWindowItem] = [
            mockItem(id: "1", app: "iTerm", title: "Terminal", role: .terminal, bundleID: "com.googlecode.iterm2"),
            mockItem(id: "2", app: "Xcode", title: "Code", role: .editor, bundleID: "com.apple.dt.Xcode"),
            mockItem(id: "3", app: "Safari", title: "Docs", role: .browser, bundleID: "com.apple.Safari")
        ]

        let assignments = LayoutAssignment.autoFill(template: template, windows: windows)

        XCTAssertEqual(assignments[0], "com.apple.dt.Xcode", "Main slot should have Editor")
        XCTAssertEqual(assignments[2], "com.googlecode.iterm2", "Bottom-right slot should have Terminal")
    }
    
    private func mockItem(id: String, app: String, title: String, role: WindowRole, bundleID: String? = nil) -> LayoutWindowItem {
        let dummyElement = AXUIElementCreateApplication(getpid())
        
        return LayoutWindowItem(
            id: id,
            element: dummyElement,
            title: title,
            appName: app,
            bundleID: bundleID,
            appIcon: nil,
            role: role
        )
    }
}
