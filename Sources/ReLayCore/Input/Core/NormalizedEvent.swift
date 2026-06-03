import Foundation

enum Direction {
    case left, right, up, down
}

enum NormalizedEvent {
    case scroll(dx: Double, dy: Double)
    case swipe(direction: Direction, velocity: Double)
    case pinch(scale: Double)
}
