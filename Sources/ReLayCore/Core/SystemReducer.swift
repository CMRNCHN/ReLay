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
                s.targetFrame = computeTargetFrame(
                    for: dir,
                    startFrame: s.startFrame,
                    screenFrame: input.screenFrame,
                    progress: s.progress
                )
            }
        }

    case .ended:
        guard !s.hasCommitted else { return s }
        let dist = max(abs(s.accumulatedX), abs(s.accumulatedY))
        if dist >= kActionThreshold {
            if let dir = GestureDirection(effectiveX: s.accumulatedX, effectiveY: s.accumulatedY) {
                s.targetFrame = computeTargetFrame(
                    for: dir,
                    startFrame: s.startFrame,
                    screenFrame: input.screenFrame,
                    progress: 1.0
                )
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

// MARK: - Frame computation for continuous gestures

private func computeTargetFrame(
    for direction: GestureDirection,
    startFrame: CGRect,
    screenFrame: CGRect,
    progress: CGFloat
) -> CGRect {
    let start = startFrame
    let S = screenFrame

    switch direction {
    case .up:
        // Expand upward: move top edge up, increase height
        let maxUpShift = max(0, start.minY - S.minY)
        let topShift = progress * maxUpShift
        let maxHeight = S.height - (start.minY - topShift - S.minY)
        let heightGain = progress * (maxHeight - start.height)
        return CGRect(
            x: start.minX,
            y: start.minY - topShift,
            width: start.width,
            height: start.height + topShift + heightGain
        )

    case .down:
        // Shrink downward: reduce height, move top down
        let minHeight = max(100, start.height * 0.2)
        let heightLoss = progress * (start.height - minHeight)
        return CGRect(
            x: start.minX,
            y: start.minY + heightLoss * 0.5,
            width: start.width,
            height: start.height - heightLoss
        )

    case .left:
        // Move left while maintaining size, constrained by screen bounds
        let maxLeftShift = start.minX - S.minX
        let shift = progress * maxLeftShift
        let newX = max(S.minX, start.minX - shift)
        return CGRect(
            x: newX,
            y: start.minY,
            width: start.width,
            height: start.height
        )

    case .right:
        // Move right while maintaining size, constrained by screen bounds
        let maxRightShift = S.maxX - start.maxX
        let shift = progress * maxRightShift
        let newX = min(S.maxX - start.width, start.minX + shift)
        return CGRect(
            x: newX,
            y: start.minY,
            width: start.width,
            height: start.height
        )
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
