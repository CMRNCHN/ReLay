import AppKit
import ApplicationServices

// MARK: - Auto Layout Watcher
// Detects a *stable* new on-screen window (dock launch / Stage Manager) and
// tiles when the desk has 2 or 3 standard windows.
//
// Deliberately does NOT expand to fullscreen when a window disappears —
// CGWindowList flickers constantly (overlays, Spaces, Stage Manager), and
// that path was randomly blowing windows up to fill-screen. Solo expand
// stays on the explicit minimize gesture in WindowRuntime.

final class AutoLayoutWatcher {

    typealias ApplyHandler = (_ windows: [AXUIElement], _ frames: [CGRect], _ screen: CGRect) -> Void

    private var timer: Timer?
    private var knownWindowIDs: Set<CGWindowID> = []
    private var isPrimed = false
    private var onApply: ApplyHandler?
    private var suspendedUntil: Date = .distantPast

    /// Candidate new window IDs waiting to prove they are stable.
    private var pendingAdded: Set<CGWindowID> = []
    private var pendingAddedSince: Date?

    /// Ignore auto-layout for this long after a gesture commit (avoids fighting
    /// the user mid-snap).
    var cooldown: TimeInterval = 1.0

    /// A newly seen window must stick around this long before we tile.
    /// Short enough to avoid a visible "thinking" pause; long enough to ignore
    /// CGWindowList flicker.
    var settleDelay: TimeInterval = 0.35

    func start(onApply: @escaping ApplyHandler, onSolo: ((AXUIElement, CGRect) -> Void)? = nil) {
        // onSolo kept in the signature for call-site compatibility; unused.
        _ = onSolo
        self.onApply = onApply
        knownWindowIDs = currentWindowIDs()
        pendingAdded = []
        pendingAddedSince = nil
        isPrimed = true
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        onApply = nil
        isPrimed = false
        knownWindowIDs = []
        pendingAdded = []
        pendingAddedSince = nil
    }

    func suspendBriefly() {
        suspendedUntil = Date().addingTimeInterval(cooldown)
        pendingAdded = []
        pendingAddedSince = nil
    }

    // MARK: - Poll

    private func tick() {
        guard isPrimed else { return }

        let snapshot = currentEntries()
        let ids = Set(snapshot.map(\.id))
        let added = ids.subtracting(knownWindowIDs)
        let removed = knownWindowIDs.subtracting(ids)

        // Drop pending candidates that vanished; accept ones that stayed.
        if !pendingAdded.isEmpty {
            pendingAdded = pendingAdded.intersection(ids)
            if pendingAdded.isEmpty {
                pendingAddedSince = nil
            }
        }

        if !added.isEmpty {
            // Only care about added IDs that look like real windows.
            let realAdds = Set(
                snapshot
                    .filter { added.contains($0.id) && isEligibleSize($0.axBounds) }
                    .map(\.id)
            )
            if !realAdds.isEmpty {
                if pendingAdded.isEmpty {
                    pendingAddedSince = Date()
                }
                pendingAdded.formUnion(realAdds)
            }
        }

        // Forget removed IDs so a later reappearance is treated as new — but
        // never auto-expand on removal (that was the random-resize bug).
        knownWindowIDs = ids
        _ = removed

        guard Date() >= suspendedUntil else { return }

        guard let since = pendingAddedSince,
              Date().timeIntervalSince(since) >= settleDelay,
              !pendingAdded.isEmpty
        else { return }

        // Consume the pending set whether or not we tile, so a failed match
        // does not retry every tick forever.
        let pending = pendingAdded
        pendingAdded = []
        pendingAddedSince = nil

        tryTile(snapshot, requiringNewIDs: pending)
    }

    private func tryTile(_ snapshot: [Entry], requiringNewIDs newIDs: Set<CGWindowID>) {
        let eligible = eligibleEntries(from: snapshot)
        guard eligible.count == 2 || eligible.count == 3 else { return }
        // At least one of the settled new IDs must still be among the eligible
        // set — otherwise this was a transient overlay, not a real window.
        let eligibleIDs = Set(eligible.map(\.id))
        guard !newIDs.isDisjoint(with: eligibleIDs) else { return }

        let screen = WindowRuntime.usableScreen(containing: eligible[0].axBounds)
        guard let frames = AutoLayoutEngine.frames(for: eligible.count, in: screen),
              frames.count == eligible.count
        else { return }

        // Skip if the desk already matches the target tile (within tolerance).
        if alreadyTiled(eligible, frames: frames) {
            Logger.log("auto-layout skip — already tiled", subsystem: "layout")
            return
        }

        var windows: [AXUIElement] = []
        for entry in eligible.reversed() {
            let bid = NSRunningApplication(processIdentifier: entry.pid)?.bundleIdentifier ?? ""
            guard WindowMutabilityPolicy.decision(for: bid) == .allow else { return }
            guard let win = AXWindowOps.window(pid: entry.pid, matching: entry.axBounds)
                    ?? AXWindowOps.window(pid: entry.pid, matching: entry.axBounds, tolerance: 24)
            else { return }
            // Confirm it's a real standard window before moving anything.
            guard AXWindowOps.isStandardWindow(win) else { return }
            windows.append(win)
        }
        guard windows.count == frames.count else { return }

        Logger.log("auto-layout tile count=\(windows.count)", subsystem: "layout")
        onApply?(windows, frames, screen)
        suspendBriefly()
    }

    private func alreadyTiled(_ entries: [Entry], frames: [CGRect], tolerance: CGFloat = 24) -> Bool {
        // entries are front-to-back; frames expect oldest→newest (reversed).
        let ordered = Array(entries.reversed())
        guard ordered.count == frames.count else { return false }
        for (entry, frame) in zip(ordered, frames) {
            if abs(entry.axBounds.minX - frame.minX) > tolerance
                || abs(entry.axBounds.minY - frame.minY) > tolerance
                || abs(entry.axBounds.width - frame.width) > tolerance
                || abs(entry.axBounds.height - frame.height) > tolerance {
                return false
            }
        }
        return true
    }

    private func isEligibleSize(_ bounds: CGRect) -> Bool {
        bounds.width > 200 && bounds.height > 200
    }

    private func eligibleEntries(from snapshot: [Entry]) -> [Entry] {
        snapshot.filter { isEligibleSize($0.axBounds) }
    }

    // MARK: - CG snapshot

    private struct Entry {
        let id: CGWindowID
        let pid: pid_t
        let axBounds: CGRect
    }

    private func currentWindowIDs() -> Set<CGWindowID> {
        Set(currentEntries().map(\.id))
    }

    private func currentEntries() -> [Entry] {
        let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        let ownPID = ProcessInfo.processInfo.processIdentifier

        return info.compactMap { dict in
            guard let id = dict[kCGWindowNumber as String] as? CGWindowID,
                  let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ownPID,
                  let b = dict[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"],
                  w >= 80, h >= 80
            else { return nil }
            if let layer = dict[kCGWindowLayer as String] as? Int, layer != 0 {
                return nil
            }
            return Entry(id: id, pid: pid, axBounds: CGRect(x: x, y: y, width: w, height: h))
        }
    }
}
