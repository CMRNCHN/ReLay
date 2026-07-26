import ApplicationServices
import CoreGraphics

// MARK: - Config

public struct Config {
    public let lockThreshold:   CGFloat
    public let cancelThreshold: CGFloat
    public let actionThreshold: CGFloat
    public let flickVelocity:   CGFloat
    public let snapDuration:    TimeInterval

    public static func load() -> Config {
        Config(
            lockThreshold:   ReLaySettings.lockThreshold,
            cancelThreshold: ReLaySettings.cancelThreshold,
            actionThreshold: ReLaySettings.actionThreshold,
            flickVelocity:   ReLaySettings.flickVelocity,
            snapDuration:    ReLaySettings.snapDuration
        )
    }
}

// MARK: - Input
// WindowIntent enriched with window context. screenFrame is OS state, not interpretation.

struct Input {
    let dx:          CGFloat
    let dy:          CGFloat
    let phase:       WindowIntent.Phase
    let window:      AXUIElement?
    let screenFrame: CGRect
    let startFrame:  CGRect
}

// MARK: - State
// Flat. targetFrame is the fully resolved pixel frame — apply() writes it straight to AX.

struct State {
    var layout:         WindowLayoutState = .floating
    var targetLayout:   WindowLayoutState?
    var accumulatedX:   CGFloat           = 0
    var accumulatedY:   CGFloat           = 0
    var hasCommitted:   Bool              = false
    var progress:       CGFloat           = 0
    var shouldRevert:   Bool              = false
    var shouldMinimize: Bool              = false
    var activeWindow:   AXUIElement?      = nil
    var startFrame:     CGRect            = .zero
    var targetFrame:    CGRect            = .zero
}

// MARK: - Reducer
// Pure. No IO. No config argument. Outputs a fully resolved targetFrame.

private let transitions = LayoutTransitionGraph()

func reduce(_ state: State, _ input: Input, config: Config = .load()) -> State {
    var s = state

    switch input.phase {
    case .began:
        s.accumulatedX   = 0
        s.accumulatedY   = 0
        s.hasCommitted   = false
        s.progress       = 0
        s.shouldRevert   = false
        s.shouldMinimize = false
        s.targetLayout   = nil
        s.targetFrame    = .zero
        s.activeWindow   = input.window
        s.startFrame     = input.startFrame

    case .changed:
        guard !s.hasCommitted else { return s }
        s = accumulateGesture(s, input, config: config)
        guard !s.shouldRevert else { return s }
        s = updateSnapPreview(s, input: input, config: config)

    case .ended:
        guard !s.hasCommitted else { return s }
        s = accumulateGesture(s, input, config: config)
        guard !s.shouldRevert else { return s }

        let dist = max(abs(s.accumulatedX), abs(s.accumulatedY))
        if dist >= config.actionThreshold {
            // Swipe down from floating, leftThird, or rightThird → minimize to dock
            let minimizeLayouts: Set<WindowLayoutState> = [.floating, .leftThird, .rightThird]
            if minimizeLayouts.contains(s.layout),
               let dir = GestureDirection(effectiveX: s.accumulatedX, effectiveY: s.accumulatedY),
               dir == .down {
                s.shouldMinimize = true
                s.hasCommitted   = true
            } else {
                s = commitSnap(s, input: input)
            }
        } else {
            return cleared(s)
        }

    case .cancelled:
        if s.hasCommitted || s.activeWindow == nil { return s }
        return cleared(s)
    }

    return s
}

// MARK: - Gesture accumulation

private func accumulateGesture(_ s: State, _ input: Input, config: Config) -> State {
    var out = s
    let nextX = out.accumulatedX + input.dx
    let nextY = out.accumulatedY + input.dy
    let absX  = abs(nextX), absY = abs(nextY)

    if absX > absY * 1.5 {
        out.accumulatedX = nextX
    } else if absY > absX * 1.5 {
        out.accumulatedY = nextY
    } else {
        out.accumulatedX = nextX
        out.accumulatedY = nextY
        if max(absX, absY) > config.cancelThreshold { return cleared(out) }
    }
    return out
}

// MARK: - Snap preview / commit

private func updateSnapPreview(_ s: State, input: Input, config: Config) -> State {
    var out = s
    let dist = max(abs(out.accumulatedX), abs(out.accumulatedY))
    guard dist > config.lockThreshold else { return out }

    out.progress = min(1, (dist - config.lockThreshold) /
                        max(1, config.actionThreshold - config.lockThreshold))

    guard let dir = GestureDirection(effectiveX: out.accumulatedX, effectiveY: out.accumulatedY),
          let nextLayout = transitions.nextState(from: out.layout, moving: dir)
    else { return out }

    out.targetLayout = nextLayout
    // End frame only — WindowRuntime interpolates once using `progress`.
    out.targetFrame = LayoutFrameResolver.frame(for: nextLayout, in: input.screenFrame)
    return out
}

private func commitSnap(_ s: State, input: Input) -> State {
    var out = s
    guard let dir = GestureDirection(effectiveX: out.accumulatedX, effectiveY: out.accumulatedY),
          let nextLayout = transitions.nextState(from: out.layout, moving: dir)
    else { return cleared(out) }

    out.targetLayout = nextLayout
    out.layout       = nextLayout
    out.targetFrame  = LayoutFrameResolver.frame(for: nextLayout, in: input.screenFrame)
    out.progress     = 1
    out.hasCommitted = true
    return out
}

// MARK: - Helpers

private func cleared(_ s: State) -> State {
    var out = s
    out.accumulatedX   = 0
    out.accumulatedY   = 0
    out.hasCommitted   = false
    out.progress       = 0
    out.targetLayout   = nil
    out.shouldRevert   = true
    out.shouldMinimize = false
    return out
}
