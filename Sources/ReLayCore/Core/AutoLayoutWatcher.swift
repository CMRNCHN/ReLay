import AppKit
import ApplicationServices

// MARK: - Auto Layout Watcher
// Detects a *stable* new on-screen window (dock launch / Stage Manager) and
// tiles when that screen has 2–4 standard windows (halves → thirds → 2×2).
//
// Menu-bar dropdowns, floating panels, and popups are filtered out via
// WindowEligibility so they never inflate the tile count or get resized.
//
// Deliberately does NOT expand to fullscreen when a window disappears —
// CGWindowList flickers constantly (overlays, Spaces, Stage Manager), and
// that path was randomly blowing windows up to fill-screen. Solo expand
// stays on the explicit minimize gesture in WindowRuntime.
//
// Only windows on the *same* usable screen as the newcomer are counted, so a
// second display does not inflate the tile count.

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
        suspend(for: cooldown)
    }

    func suspend(for duration: TimeInterval) {
        suspendedUntil = Date().addingTimeInterval(duration)
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
            // Only care about added IDs that look like real tileable windows.
            let realAdds = Set(
                snapshot
                    .filter { added.contains($0.id) && isTileableCG($0) }
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
        // Anchor the screen to a newly appeared window so we only retile that display.
        guard let newcomer = snapshot.first(where: { newIDs.contains($0.id) && isTileableCG($0) })
                ?? snapshot.first(where: { newIDs.contains($0.id) })
        else { return }

        let screen = WindowRuntime.usableScreen(containing: newcomer.axBounds)
        guard screen != .zero else { return }

        // Resolve AX and drop popups / accessory apps / non-resizable floaters.
        let resolved = resolveTileable(from: snapshot, on: screen)
        guard (2...AutoLayoutEngine.maxTileCount).contains(resolved.count) else { return }

        // At least one settled new ID must still be among the tileable set.
        let resolvedIDs = Set(resolved.map(\.entry.id))
        guard !newIDs.isDisjoint(with: resolvedIDs) else {
            Logger.log("auto-layout skip — newcomer not tileable", subsystem: "layout")
            return
        }

        let gap = ReLaySettings.layoutPadding
        guard let frames = AutoLayoutEngine.frames(for: resolved.count, in: screen, gap: gap),
              frames.count == resolved.count
        else { return }

        // Skip if the desk already matches the target tile (within tolerance).
        if alreadyTiled(resolved.map(\.entry), frames: frames) {
            Logger.log("auto-layout skip — already tiled", subsystem: "layout")
            return
        }

        // resolved is front-to-back; frames expect oldest → newest.
        let windows = resolved.map(\.window).reversed()
        Logger.log("auto-layout tile count=\(windows.count)", subsystem: "layout")
        onApply?(Array(windows), frames, screen)
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

    private func isTileableCG(_ entry: Entry) -> Bool {
        let screen = WindowRuntime.usableScreen(containing: entry.axBounds)
        guard screen != .zero else { return false }
        return WindowEligibility.isTileableCGEntry(
            pid: entry.pid, bounds: entry.axBounds, on: screen
        )
    }

    private struct Resolved {
        let entry: Entry
        let window: AXUIElement
    }

    /// Front-to-back tileable windows on `screen`. Non-tileable overlays are
    /// skipped — they keep their original size and never take a tile slot.
    private func resolveTileable(from snapshot: [Entry], on screen: CGRect) -> [Resolved] {
        var result: [Resolved] = []
        for entry in snapshot {
            guard WindowEligibility.isTileableCGEntry(
                pid: entry.pid, bounds: entry.axBounds, on: screen
            ) else { continue }

            guard let win = AXWindowOps.window(pid: entry.pid, matching: entry.axBounds)
                    ?? AXWindowOps.window(pid: entry.pid, matching: entry.axBounds, tolerance: 24)
            else { continue }

            guard WindowEligibility.isTileableWindow(win, on: screen) else { continue }
            if result.contains(where: { CFEqual($0.window, win) }) { continue }
            result.append(Resolved(entry: entry, window: win))
            if result.count >= AutoLayoutEngine.maxTileCount { break }
        }
        return result
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
            if let alpha = dict[kCGWindowAlpha as String] as? CGFloat, alpha < 0.05 {
                return nil
            }
            // Cheap early reject: accessory / menu-bar apps never tile.
            guard WindowEligibility.isRegularApp(pid: pid) else { return nil }
            return Entry(id: id, pid: pid, axBounds: CGRect(x: x, y: y, width: w, height: h))
        }
    }
}
