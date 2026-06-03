import CoreGraphics
import Cocoa
import Accessibility

// ReLay integration boundary. Only this layer is allowed to touch ReLay subsystems.
final class ActionDispatcher: IntentDispatching {
    private let reconciler = SpatialStateReconciler()

    func dispatch(_ intent: AppIntent) {
        switch intent {
        case .navigateBack:
            AppLogger.log("intent: navigateBack", subsystem: "input")
            withFrontmostApp { bundleID in
                self.withFrontmostWindow { window in
                    SpatialTransitionEngine.shared.beginSession(window: window, fingerCount: 2, at: .zero)
                    SpatialTransitionEngine.shared.commitSession(effectiveX: -120, effectiveY: 0, fingerCount: 2, at: .zero)
                }
                self.recordGestureEvent(bundleID: bundleID)
            }

        case .navigateForward:
            AppLogger.log("intent: navigateForward", subsystem: "input")
            withFrontmostApp { bundleID in
                self.withFrontmostWindow { window in
                    SpatialTransitionEngine.shared.beginSession(window: window, fingerCount: 2, at: .zero)
                    SpatialTransitionEngine.shared.commitSession(effectiveX: 120, effectiveY: 0, fingerCount: 2, at: .zero)
                }
                self.recordGestureEvent(bundleID: bundleID)
            }

        case .zoomIn:
            AppLogger.log("intent: zoomIn", subsystem: "input")
            // TODO: connect to ReLay window layout zoom engine

        case .zoomOut:
            AppLogger.log("intent: zoomOut", subsystem: "input")
            // TODO: connect to ReLay window layout zoom engine

        case .moveWorkspace(let delta):
            AppLogger.log("intent: moveWorkspace delta=\(delta)", subsystem: "input")
            SpatialEngine.shared.moveWorkspace(delta: delta)
            withFrontmostApp { bundleID in
                let state = self.reconciler.snapshot()
                SpatialMemoryEngine.shared.learn(
                    from: state,
                    event: UsageEvent(appBundleID: bundleID, action: .windowMoved)
                )
            }
        }
    }

    // MARK: - Private

    private func withFrontmostApp(_ body: (String) -> Void) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return }
        body(bundleID)
    }

    private func withFrontmostWindow(_ body: (AXUIElement) -> Void) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let window = ref else { return }
        body(unsafeBitCast(window, to: AXUIElement.self))
    }

    private func recordGestureEvent(bundleID: String) {
        let state = reconciler.snapshot()
        SpatialMemoryEngine.shared.learn(
            from: state,
            event: UsageEvent(appBundleID: bundleID, action: .gestureFired)
        )
    }
}
