import SwiftUI
import AppKit
import ReLayV2

@main
struct ReLayMVPApp: App {

    @StateObject private var model = AppModel()

    init() {
        NSApp.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            WorkspaceListView()
                .environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 480, height: 560)
    }
}
