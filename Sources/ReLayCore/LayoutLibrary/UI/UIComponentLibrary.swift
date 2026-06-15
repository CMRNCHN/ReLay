import AppKit

// MARK: - AnimationTiming

public struct AnimationTiming {
    /// Snap animation duration for quick interactions
    public static let snap: TimeInterval = 0.22

    /// Hover animation duration for state changes
    public static let hover: TimeInterval = 0.1

    /// Drag animation duration for drag operations
    public static let drag: TimeInterval = 0.12

    /// Transition animation duration for view transitions
    public static let transition: TimeInterval = 0.26
}

// MARK: - Panel Creation

/// Creates a styled library panel with standard appearance.
/// - Returns: A configured NSPanel with floating level, borderless style, and rounded corners.
public func makeLibraryPanel() -> NSPanel {
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    // Apply corner radius via content view
    if let contentView = panel.contentView {
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 16
        contentView.layer?.masksToBounds = true
    }

    return panel
}

// MARK: - Button Creation

/// Creates an accent-colored button with standard styling.
/// - Parameters:
///   - title: The button's display title
///   - target: The target object for the action
///   - action: The selector to call when clicked
/// - Returns: A configured NSButton with blue background and white text.
public func makeAccentButton(title: String, target: Any?, action: Selector?) -> NSButton {
    let btn = NSButton(title: title, target: target, action: action)
    btn.bezelStyle = .roundRect
    btn.wantsLayer = true
    btn.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
    btn.layer?.cornerRadius = 8
    btn.contentTintColor = .white
    btn.font = .systemFont(ofSize: 13, weight: .medium)
    btn.translatesAutoresizingMaskIntoConstraints = false
    return btn
}

// MARK: - Animation Context

/// Executes an animation block with standard AppKit animation context.
/// - Parameters:
///   - duration: Animation duration in seconds
///   - timingFunc: CAMediaTimingFunction for the animation (optional)
///   - block: The closure containing the animation code
public func makeAnimationContext(
    duration: TimeInterval,
    timingFunc: CAMediaTimingFunction? = nil,
    _ block: @escaping () -> Void
) {
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = duration
        if let timing = timingFunc {
            ctx.timingFunction = timing
        }
        block()
    }
}

/// Creates a standard easeInOut timing function (cubic bezier 0.25, 0.46, 0.45, 0.94).
/// This is commonly used for smooth transitions.
/// - Returns: A CAMediaTimingFunction configured with easeInOut control points.
public func makeEaseInOutTiming() -> CAMediaTimingFunction {
    CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
}

/// Creates a standard easeIn timing function.
/// - Returns: A CAMediaTimingFunction configured with easeIn.
public func makeEaseInTiming() -> CAMediaTimingFunction {
    CAMediaTimingFunction(name: .easeIn)
}
