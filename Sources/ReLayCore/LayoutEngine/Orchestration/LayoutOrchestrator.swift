import ApplicationServices
import Cocoa
import Accessibility

// ONLY VALID FRAME WRITER — all AX frame writes in the system must go through this file.
// Do not call AXUIElementSetAttributeValue for position/size from any other layer.

/// Low-level animation and AX primitive layer.
/// No layout semantics, no state machine — pure window manipulation.
class LayoutOrchestrator {
    static let shared = LayoutOrchestrator()

    private var activeAnimations: [WindowID: Timer] = [:]
    private let windowGap: CGFloat = 2.0

    private init() {}

    // MARK: - Tiling

    /// Tiles `windows` inside `screen`. `columns` fixes the column count;
    /// nil computes a square-ish grid automatically.
    func tileWindows(_ windows: [AXUIElement], in screen: CGRect, columns: Int? = nil, gap: CGFloat = 2, sessionID: String) {
        let count = windows.count
        guard count > 0 else { return }

        if count == 1 {
            animateWindowFrame(windows[0], to: screen, sessionID: sessionID)
            return
        }

        let cols   = columns ?? Int(ceil(sqrt(Double(count))))
        let rows   = Int(ceil(Double(count) / Double(cols)))
        let cellW  = screen.width  / CGFloat(cols)
        let cellH  = screen.height / CGFloat(rows)
        let half   = gap / 2

        for (i, window) in windows.enumerated() {
            let col = i % cols
            let row = i / cols
            let frame = CGRect(
                x: screen.origin.x + CGFloat(col) * cellW + half,
                y: screen.origin.y + CGFloat(row) * cellH + half,
                width:  max(1, cellW - gap),
                height: max(1, cellH - gap)
            )
            animateWindowFrame(window, to: frame, sessionID: sessionID)
        }
    }

    // MARK: - Window Enumeration

    func getAllVisibleWindows() -> [AXUIElement] {
        var result: [AXUIElement] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)

            // Some apps (Electron, custom-chrome) require AXEnhancedUserInterface before
            // their window list and frame attributes become accessible via AX.
            AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)

            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
                  let list = ref as? [AXUIElement] else { continue }
            for window in list {
                // Skip minimized
                var minRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minRef) == .success,
                   let isMin = minRef as? Bool, isMin { continue }
                // Skip fullscreen
                var fsRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fsRef) == .success,
                   let isFS = fsRef as? Bool, isFS { continue }
                // Skip Finder desktop window (subrole AXUnknown + covers full screen)
                var subroleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef) == .success,
                   let subrole = subroleRef as? String,
                   subrole == "AXUnknown" {
                    // Check if it's screen-sized (desktop window)
                    if let frame = getWindowFrame(window),
                       let screen = NSScreen.screens.first,
                       frame.width >= screen.frame.width * 0.95 {
                        continue
                    }
                }
                result.append(window)
            }
        }
        AppLogger.log("expose: enumerated \(result.count) visible windows across \(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.count) apps", subsystem: "expose")
        return result
    }

    func windowTitle(for window: AXUIElement) -> String {
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
           let title = titleRef as? String,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }

        var appRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXParentAttribute as CFString, &appRef) == .success,
           let app = appRef {
            var appTitleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(app as! AXUIElement, kAXTitleAttribute as CFString, &appTitleRef) == .success,
               let appTitle = appTitleRef as? String,
               !appTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return appTitle
            }
        }

        return "Window"
    }

    // MARK: - Stage Manager

    func isStageManagerEnabled() -> Bool {
        UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
    }

    func setStageManager(_ enabled: Bool) {
        CFPreferencesSetValue(
            "GloballyEnabled" as CFString,
            enabled as CFTypeRef,
            "com.apple.WindowManager" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(
            "com.apple.WindowManager" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        let p = Process()
        p.launchPath = "/usr/bin/killall"
        p.arguments  = ["-HUP", "WindowManager"]
        try? p.run()
    }

    // MARK: - Screen Frame

    func getUsableScreenFrame(for window: AXUIElement, at point: CGPoint? = nil) -> CGRect {
        guard let primary = NSScreen.screens.first else { return .zero }
        var target = NSScreen.main ?? primary

        if let point = point {
            for screen in NSScreen.screens {
                let axY = primary.frame.height - (screen.frame.origin.y + screen.frame.height)
                let axFrame = CGRect(x: screen.frame.origin.x, y: axY,
                                     width: screen.frame.width, height: screen.frame.height)
                if axFrame.contains(point) { target = screen; break }
            }
        } else if let frame = getWindowFrame(window) {
            var maxArea: CGFloat = -1
            for screen in NSScreen.screens {
                let axY = primary.frame.height - (screen.frame.origin.y + screen.frame.height)
                let axFrame = CGRect(x: screen.frame.origin.x, y: axY,
                                     width: screen.frame.width, height: screen.frame.height)
                let intersection = axFrame.intersection(frame)
                let area = intersection.width * intersection.height
                if area > maxArea {
                    maxArea = area
                    target = screen
                }
            }
        }

        let vf      = target.visibleFrame
        let flipped = primary.frame.height - (vf.origin.y + vf.height)
        return CGRect(x: vf.origin.x, y: flipped, width: vf.width, height: vf.height)
    }

    // MARK: - AX Frame Primitives

    func getWindowFrame(_ window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Writes `frame` to `window`. Returns false if the AX element is no longer
    /// valid (e.g. window closed mid-gesture) so callers can mark it stale.
    @discardableResult
    func setWindowFrame(_ window: AXUIElement, frame: CGRect, source: String = "unknown") -> Bool {
#if DEBUG
        // GUARD 3 — execution path enforcement
        // Every frame write should originate from "gesture" or "expose".
        if source != "gesture" && source != "expose" {
            AppLogger.log("STRICT: setWindowFrame called with untagged source=\(source)", subsystem: "orchestrator")
        }
#endif
        var pos = frame.origin, size = frame.size
        guard let posVal  = AXValueCreate(.cgPoint, &pos),
              let sizeVal = AXValueCreate(.cgSize,  &size) else { return false }
        // size → position → size avoids macOS off-screen clamping
        let r1 = AXUIElementSetAttributeValue(window, kAXSizeAttribute     as CFString, sizeVal)
        let r2 = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        let r3 = AXUIElementSetAttributeValue(window, kAXSizeAttribute     as CFString, sizeVal)
        return r1 == .success && r2 == .success && r3 == .success
    }

    // MARK: - Spring Animation

    private var snapDuration: TimeInterval {
        let v = UserDefaults.standard.double(forKey: "snapDuration")
        return v > 0 ? v : 0.220
    }

    func animateWindowFrame(_ window: AXUIElement, to target: CGRect, duration: TimeInterval? = nil, sessionID: String? = nil, source: String = "unknown") {
#if DEBUG
        // GUARD 3 — execution path enforcement
        if source != "gesture" && source != "expose" {
            AppLogger.log("STRICT: animateWindowFrame called with untagged source=\(source)", subsystem: "orchestrator")
        }
#endif
        let duration = duration ?? snapDuration
        let id = WindowID(element: window)
        activeAnimations[id]?.invalidate()

        AppLogger.log("animation start target=\(target.debugDescription) duration=\(duration)", subsystem: "orchestrator")

        guard let start = getWindowFrame(window) else {
            AppLogger.log("animation immediate frame set (no current frame)", subsystem: "orchestrator")
            setWindowFrame(window, frame: target)
            return
        }

        AppLogger.log("animation easing from \(start.debugDescription) to \(target.debugDescription)", subsystem: "orchestrator")

        let t0 = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { return }
            var t = CGFloat(Date().timeIntervalSince(t0) / duration)
            if t >= 1.0 {
                t = 1.0; timer.invalidate(); self.activeAnimations.removeValue(forKey: id)
                AppLogger.log("animation complete", subsystem: "orchestrator")
            }
            let p = self.spring(t)
            self.setWindowFrame(window, frame: CGRect(
                x:      start.origin.x + (target.origin.x - start.origin.x) * p,
                y:      start.origin.y + (target.origin.y - start.origin.y) * p,
                width:  start.width    + (target.width     - start.width)    * p,
                height: start.height   + (target.height    - start.height)   * p
            ))
        }
        RunLoop.main.add(timer, forMode: .common)
        activeAnimations[id] = timer
    }

    // Critically-damped spring: settles without oscillation, fast and native-feeling.
    private func spring(_ t: CGFloat, damping: CGFloat = 26, stiffness: CGFloat = 170) -> CGFloat {
        if t <= 0 { return 0 }; if t >= 1 { return 1 }
        let mass: CGFloat = 1
        let w0   = sqrt(stiffness / mass)
        let zeta = damping / (2 * sqrt(stiffness * mass))
        let pt   = t * 9.0  // scale to settle fully at t=1
        if zeta < 1 {
            let wd = w0 * sqrt(1 - zeta * zeta)
            let e  = exp(-zeta * w0 * pt)
            return 1 - e * (cos(wd * pt) + (zeta * w0 / wd) * sin(wd * pt))
        } else {
            let e = exp(-w0 * pt)
            return 1 - e * (1 + w0 * pt)
        }
    }
}
