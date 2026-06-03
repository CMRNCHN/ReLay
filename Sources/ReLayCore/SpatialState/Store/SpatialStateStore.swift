import Foundation

/// The single write gate for all spatial state mutations.
/// Thread-safe: all reads and writes are serialised through a dedicated queue.
public final class SpatialStateStore {

    private var state: SpatialState
    private let queue = DispatchQueue(label: "com.relay.SpatialStateStore", qos: .userInteractive)

    /// Observers notified on the main queue after each mutation.
    private var observers: [(SpatialState) -> Void] = []

    public init(initial: SpatialState) {
        self.state = initial
    }

    // MARK: - Read

    public func read() -> SpatialState {
        queue.sync { state }
    }

    // MARK: - Write

    public func write(_ newState: SpatialState) {
        queue.sync { state = newState }
        notifyObservers()
    }

    /// Apply an in-place transform; version is managed by the reducer.
    public func mutate(_ transform: (inout SpatialState) -> Void) {
        queue.sync { transform(&state) }
        notifyObservers()
    }

    // MARK: - Observation

    public func addObserver(_ observer: @escaping (SpatialState) -> Void) {
        observers.append(observer)
    }

    private func notifyObservers() {
        let snapshot = read()
        DispatchQueue.main.async { [observers] in
            observers.forEach { $0(snapshot) }
        }
    }
}
