import Foundation

struct RawInputEvent {
    let timestamp: Double
    let deltaX: Double
    let deltaY: Double
    let phase: String?
    let gestureScale: Double?
}
