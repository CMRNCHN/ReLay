import Cocoa
import ApplicationServices

protocol EventTapCaptureDelegate: AnyObject {
    func didCapture(_ event: RawInputEvent)
}

final class EventTapCapture {
    weak var delegate: EventTapCaptureDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var gestureMonitor: Any?
    private var watchdogTimer: Timer?
    private var isRunning = false

    // Maximum time before watchdog re-validates the tap (seconds).
    private static let watchdogInterval: TimeInterval = 5

    func start() throws {
        guard AXIsProcessTrusted() else {
            AppLogger.log("input capture: accessibility not granted", subsystem: "input")
            throw CaptureError.accessibilityNotGranted
        }
        try installTap()
        installGestureMonitor()
        installWatchdog()
        isRunning = true
        AppLogger.log("input capture started", subsystem: "input")
    }

    func stop() {
        isRunning = false
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        removeTap()
        if let monitor = gestureMonitor {
            NSEvent.removeMonitor(monitor)
            gestureMonitor = nil
        }
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

        eventTap = tap
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
            eventTap = nil
            runLoopSource = nil
        }
    }

    private func installGestureMonitor() {
        gestureMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: NSEvent.EventTypeMask(rawValue: 1 << 29)
        ) { [weak self] event in
            self?.handleGestureEvent(event)
        }
    }

    // Watchdog: detects silent tap death (accessibility reset, system event rejects)
    // and attempts a single re-install rather than looping blindly.
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
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            AppLogger.log("input capture: tap disabled by system (\(type == .tapDisabledByTimeout ? "timeout" : "user input")); re-enabling", subsystem: "input")
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        guard let nsEvent = NSEvent(cgEvent: event) else { return }

        // Suppress inertia (momentum) events — they produce false swipe classifications.
        let momentum = nsEvent.momentumPhase
        if momentum == .began || momentum == .changed || momentum == .ended { return }

        let raw = RawInputEvent(
            timestamp: event.timestamp.toSeconds(),
            deltaX: Double(nsEvent.scrollingDeltaX),
            deltaY: Double(nsEvent.scrollingDeltaY),
            phase: nsEvent.phase.phaseString,
            gestureScale: nil
        )
        delegate?.didCapture(raw)
    }

    private func handleGestureEvent(_ event: NSEvent) {
        guard event.magnification != 0 else { return }
        let raw = RawInputEvent(
            timestamp: event.timestamp,
            deltaX: 0,
            deltaY: 0,
            phase: nil,
            gestureScale: Double(event.magnification)
        )
        delegate?.didCapture(raw)
    }

    enum CaptureError: Error {
        case accessibilityNotGranted
        case tapCreationFailed
    }
}

private extension UInt64 {
    func toSeconds() -> Double { Double(self) / 1_000_000_000 }
}

private extension NSEvent.Phase {
    var phaseString: String {
        switch self {
        case .began:     return "began"
        case .changed:   return "changed"
        case .ended:     return "ended"
        case .cancelled: return "cancelled"
        case .stationary: return "stationary"
        default:         return "none"
        }
    }
}
