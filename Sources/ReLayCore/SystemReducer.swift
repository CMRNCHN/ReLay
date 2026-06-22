import ApplicationServices
import CoreGraphics

// MARK: - Config
// Loaded once at startup. snapDuration is the only runtime-tunable value.

public struct Config {
    public let snapDuration: TimeInterval

    public static func load() -> Config {
        let v = UserDefaults.standard.double(forKey: "snapDuration")
        return Config(snapDuration: v > 0 ? v : 0.220)
    }
}

// MARK: - Gesture thresholds (compile-time)

private let kLockThreshold:   CGFloat = 20
private let kCancelThreshold: CGFloat = 25
private let kActionThreshold: CGFloat = 100

// MARK: - Input
// WindowIntent enriched with window context. screenFrame is OS state, not interpretation.

struct Input {
    let dx:          CGFloat
    let dy:          CGFloat
    let phase:       WindowIntent.Phase
    let window:      AXUIElement?
    let screenFrame: CGRect
}

// MARK: - State
// Flat. targetFrame is the fully resolved pixel frame — apply() writes it straight to AX.

struct State {
    var layout:       WindowLayoutState = .floating
    var accumulatedX: CGFloat           = 0
    var accumulatedY: CGFloat           = 0
    var hasCommitted: Bool              = false
    var progress:     CGFloat           = 0
    var activeWindow: AXUIElement?      = nil
    var startFrame:   CGRect            = .zero
    var targetFrame:  CGRect            = .zero
}

// MARK: - Reducer
// Pure. No IO. No config argument. Outputs a fully resolved targetFrame.

private let transitions = LayoutTransitionGraph()

func reduce(_ state: State, _ input: Input) -> State {
    var s = state

    switch input.phase {
    case .began:
        s.accumulatedX = 0
        s.accumulatedY = 0
        s.hasCommitted = false
        s.progress     = 0
        s.activeWindow = input.window

    case .changed:
        guard !s.hasCommitted else { return s }

        let nextX = s.accumulatedX + input.dx
        let nextY = s.accumulatedY + input.dy
        let absX  = abs(nextX), absY = abs(nextY)

        if absX > absY * 1.5 {
            s.accumulatedX = nextX
        } else if absY > absX * 1.5 {
            s.accumulatedY = nextY
        } else {
            s.accumulatedX = nextX
            s.accumulatedY = nextY
            if max(absX, absY) > kCancelThreshold { return cleared(s) }
        }

        let dist = max(abs(s.accumulatedX), abs(s.accumulatedY))
        if dist > kLockThreshold {
            s.progress = min(1, (dist - kLockThreshold) /
                             max(1, kActionThreshold - kLockThreshold))
            if let dir = GestureDirection(effectiveX: s.accumulatedX, effectiveY: s.accumulatedY) {
                let next = resolvedLayout(from: state.layout, direction: dir)
                s.layout      = next
                s.targetFrame = frameForLayout(next, on: input.screenFrame, floatingFrame: s.startFrame)
            }
        }

    case .ended:
        guard !s.hasCommitted else { return s }
        let dist = max(abs(s.accumulatedX), abs(s.accumulatedY))
        if dist >= kActionThreshold {
            if let dir = GestureDirection(effectiveX: s.accumulatedX, effectiveY: s.accumulatedY) {
                let next = resolvedLayout(from: state.layout, direction: dir)
                s.layout      = next
                s.targetFrame = frameForLayout(next, on: input.screenFrame, floatingFrame: s.startFrame)
            }
            s.hasCommitted = true
        } else {
            return cleared(s)
        }

    case .cancelled:
        return cleared(s)
    }

    return s
}

// MARK: - Layout resolution

private func resolvedLayout(from current: WindowLayoutState, direction: GestureDirection) -> WindowLayoutState {
    switch direction {
    case .up:   return .fullscreen
    case .down: return current
    default:    return transitions.nextState(from: current, moving: direction) ?? current
    }
}

// MARK: - Frame computation (pure math)

private func frameForLayout(_ layout: WindowLayoutState, on screen: CGRect, floatingFrame: CGRect = .zero) -> CGRect {
    let W = screen.width, H = screen.height
    let X = screen.origin.x, Y = screen.origin.y

    switch layout {
    case .floating:
        return floatingFrame.isEmpty ? screen : floatingFrame
    case .fullscreen:
        return screen
    case .center:
        let w = round(W * 0.72)
        return CGRect(x: X + round((W - w) / 2), y: Y, width: w, height: H)
    case .leftHalf:
        return CGRect(x: X, y: Y, width: round(W * 0.5), height: H)
    case .rightHalf:
        let w = round(W * 0.5)
        return CGRect(x: X + (W - w), y: Y, width: w, height: H)
    case .leftThird:
        return CGRect(x: X, y: Y, width: round(W / 3), height: H)
    case .rightThird:
        let w = round(W / 3)
        return CGRect(x: X + W - w, y: Y, width: w, height: H)
    case .leftTopSixth:
        return CGRect(x: X, y: Y, width: round(W / 3), height: round(H / 2))
    case .leftBottomSixth:
        let h = round(H / 2)
        return CGRect(x: X, y: Y + h, width: round(W / 3), height: h)
    case .rightTopSixth:
        let w = round(W / 3)
        return CGRect(x: X + W - w, y: Y, width: w, height: round(H / 2))
    case .rightBottomSixth:
        let w = round(W / 3), h = round(H / 2)
        return CGRect(x: X + W - w, y: Y + h, width: w, height: h)
    }
}

// MARK: - Helpers

private func cleared(_ s: State) -> State {
    var out = s
    out.accumulatedX = 0
    out.accumulatedY = 0
    out.hasCommitted = false
    out.progress     = 0
    return out
}
