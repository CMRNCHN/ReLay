import SwiftUI
import AppKit
import ReLayV2

@main
struct ReLayMVPApp: App {

    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            WorkspaceListView()
                .environmentObject(model)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 480, height: 560)
    }
}
