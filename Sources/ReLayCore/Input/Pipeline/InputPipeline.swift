import Foundation

/// Wires all input subsystem components together.
/// Start/stop from the main RunLoop. All processing is synchronous on the RunLoop thread.
/// Concrete pipeline stages are injected for testability; production callers use the shared singleton.
public final class InputPipeline {
    public static let shared = InputPipeline()

    private let capture:    EventTapCapture
    private let normalizer: EventNormalizing
    private let engine:     GestureProcessing
    private let router:     GestureRouting
    private let dispatcher: IntentDispatching

    private var isRunning = false

    // Production singleton with default concrete implementations.
    private convenience init() {
        self.init(
            capture:    EventTapCapture(),
            normalizer: EventNormalizer(),
            engine:     InputGestureEngine(),
            router:     GestureRouter(),
            dispatcher: ActionDispatcher()
        )
    }

    // Designated initializer for dependency injection (tests, previews).
    init(
        capture:    EventTapCapture,
        normalizer: EventNormalizing,
        engine:     GestureProcessing,
        router:     GestureRouting,
        dispatcher: IntentDispatching
    ) {
        self.capture    = capture
        self.normalizer = normalizer
        self.engine     = engine
        self.router     = router
        self.dispatcher = dispatcher
        self.capture.delegate = self
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
        guard let gesture    = engine.process(normalized) else { return }
        guard let intent     = router.route(gesture) else { return }
        dispatcher.dispatch(intent)
    }
}
