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

    // Tracks whether we're currently active so tap-disabled events can re-enable
    private var isRunning = false

    func start() throws {
        guard AXIsProcessTrusted() else {
            AppLogger.log("input capture: accessibility not granted", subsystem: "input")
            throw CaptureError.accessibilityNotGranted
        }

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
                let capture = Unmanaged<EventTapCapture>.fromOpaque(refcon).takeUnretainedValue()
                capture.handleCGEvent(type: type, event: event)
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
        isRunning = true

        // NSEvent gesture monitor for pinch scale (type 29 / NSEventType.gesture)
        gestureMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: NSEvent.EventTypeMask(rawValue: 1 << 29)
        ) { [weak self] event in
            self?.handleGestureEvent(event)
        }

        AppLogger.log("input capture started", subsystem: "input")
    }

    func stop() {
        isRunning = false
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        if let monitor = gestureMonitor {
            NSEvent.removeMonitor(monitor)
            gestureMonitor = nil
        }
        AppLogger.log("input capture stopped", subsystem: "input")
    }

    // MARK: - Private

    private func handleCGEvent(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        guard let nsEvent = NSEvent(cgEvent: event) else { return }

        let raw = RawInputEvent(
            timestamp: event.timestamp.toSeconds(),
            deltaX: Double(nsEvent.scrollingDeltaX),
            deltaY: Double(nsEvent.scrollingDeltaY),
            phase: nsEvent.phase.debugDescription,
            gestureScale: nil
        )
        delegate?.didCapture(raw)
    }

    private func handleGestureEvent(_ event: NSEvent) {
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
