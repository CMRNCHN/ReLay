import CoreGraphics

// Protocol boundaries for the input pipeline stages.
// Each concrete type can be swapped or mocked independently in tests.

protocol GestureRouting {
    func route(_ gesture: InputGesture) -> AppIntent?
}

protocol IntentDispatching {
    func dispatch(_ intent: AppIntent)
}

protocol EventNormalizing {
    func normalize(_ raw: RawInputEvent) -> NormalizedEvent?
}

protocol GestureProcessing {
    func process(_ event: NormalizedEvent) -> InputGesture?
    func reset()
}
