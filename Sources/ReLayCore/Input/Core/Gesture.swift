import CoreGraphics

enum InputGesture {
    case twoFingerSwipeLeft
    case twoFingerSwipeRight
    case pinchZoomIn
    case pinchZoomOut
    case threeFingerDrag(delta: CGPoint)
}
