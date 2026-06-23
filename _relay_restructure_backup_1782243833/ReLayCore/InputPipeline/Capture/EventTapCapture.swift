import Cocoa
import ApplicationServices

// MARK: - Output contract

struct WindowIntent {
    enum Phase { case began, changed, ended, cancelled }
    let dx:    CGFloat
    let dy:    CGFloat
    let phase: Phase
}

// MARK: - Delegate

protocol EventTapCaptureDelegate: AnyObject {
    func didReceive(_ intent: WindowIntent)
}

// MARK: - Capture

final class EventTapCapture {
    weak var delegate: EventTapCaptureDelegate?

    private var eventTap:      CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var watchdogTimer: Timer?
    private var isRunning = false

    private static let watchdogInterval: TimeInterval = 5

    func start() throws {
        guard AXIsProcessTrusted() else {
            AppLogger.log("input capture: accessibility not granted", subsystem: "input")
            throw CaptureError.accessibilityNotGranted
        }
        try installTap()
        installWatchdog()
        isRunning = true
        AppLogger.log("input capture started", subsystem: "input")
    }

    func stop() {
        isRunning = false
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        removeTap()
        AppLogger.log("input capture stopped", subsystem: "input")
    }

    // MARK: - Tap lifecycle

    private func installTap() throws {
        let mask: CGEventMask =
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue)

        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                Unmanaged<EventTapCapture>.fromOpaque(refcon).takeUnretainedValue()
                    .handleCGEvent(type: type, event: event)
                return Unmanaged.passRetained(event)
            },
            userInfo: observer
        )

        guard let tap else {
            AppLogger.log("input capture: CGEventTap creation failed", subsystem: "input")
            throw CaptureError.tapCreationFailed
        }

        eventTap      = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
            }
            eventTap      = nil
            runLoopSource = nil
        }
    }

    private func installWatchdog() {
        watchdogTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.watchdogInterval, repeats: true) { [weak self] _ in
            self?.checkTapHealth()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    private func checkTapHealth() {
        guard isRunning else { return }
        if let tap = eventTap, CFMachPortIsValid(tap) { return }
        AppLogger.log("input capture: tap died; attempting restart", subsystem: "input")
        removeTap()
        do {
            try installTap()
            AppLogger.log("input capture: tap restarted successfully", subsystem: "input")
        } catch {
            AppLogger.log("input capture: tap restart failed: \(error)", subsystem: "input")
        }
    }

    // MARK: - Event handling

    private func handleCGEvent(type: CGEventType, event: CGEvent) {
        AppLogger.log("input capture: event received type=\(type)", subsystem: "input")

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            AppLogger.log("input capture: tap disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input")); re-enabling", subsystem: "input")
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        guard let nsEvent = NSEvent(cgEvent: event) else {
            AppLogger.log("input capture: failed to convert CGEvent to NSEvent", subsystem: "input")
            return
        }

        guard let phase = nsEvent.phase.asWindowIntentPhase else {
            AppLogger.log("input capture: phase conversion failed for phase=\(nsEvent.phase) type=\(type)", subsystem: "input")
            return
        }

        // Suppress inertia (momentum) events — false swipe classifications.
        let momentum = nsEvent.momentumPhase
        if momentum == .began || momentum == .changed || momentum == .ended { return }

        AppLogger.log("input capture: intent dx=\(nsEvent.scrollingDeltaX) dy=\(nsEvent.scrollingDeltaY) phase=\(phase)", subsystem: "input")
        delegate?.didReceive(WindowIntent(
            dx: CGFloat(nsEvent.scrollingDeltaX),
            dy: CGFloat(nsEvent.scrollingDeltaY),
            phase: phase
        ))
    }

    enum CaptureError: Error {
        case accessibilityNotGranted
        case tapCreationFailed
    }
}

private extension NSEvent.Phase {
    var asWindowIntentPhase: WindowIntent.Phase? {
        switch self {
        case .began:     return .began
        case .changed:   return .changed
        case .ended:     return .ended
        case .cancelled: return .cancelled
        default:         return nil
        }
    }
}
