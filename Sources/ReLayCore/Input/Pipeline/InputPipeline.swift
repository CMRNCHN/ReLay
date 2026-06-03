import Foundation

/// Wires all input subsystem components together.
/// Start/stop from the main RunLoop. All processing is synchronous on the RunLoop thread.
public final class InputPipeline {
    public static let shared = InputPipeline()

    private let capture    = EventTapCapture()
    private let normalizer = EventNormalizer()
    private let engine     = InputGestureEngine()
    private let router     = GestureRouter()
    private let dispatcher = ActionDispatcher()

    private var isRunning = false

    private init() {
        capture.delegate = self
    }

    public func start() {
        guard !isRunning else { return }
        guard AXIsProcessTrusted() else {
            AppLogger.log("input pipeline: accessibility permission missing — not starting", subsystem: "input")
            return
        }
        do {
            try capture.start()
            isRunning = true
            AppLogger.log("input pipeline started", subsystem: "input")
        } catch {
            AppLogger.log("input pipeline start failed: \(error)", subsystem: "input")
        }
    }

    public func stop() {
        guard isRunning else { return }
        capture.stop()
        engine.reset()
        isRunning = false
        AppLogger.log("input pipeline stopped", subsystem: "input")
    }
}

extension InputPipeline: EventTapCaptureDelegate {
    func didCapture(_ raw: RawInputEvent) {
        guard let normalized = normalizer.normalize(raw) else { return }
        guard let gesture = engine.process(normalized) else { return }
        guard let intent = router.route(gesture) else { return }
        dispatcher.dispatch(intent)
    }
}
