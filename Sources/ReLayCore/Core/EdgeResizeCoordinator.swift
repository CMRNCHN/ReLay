import AppKit
import ApplicationServices
import CoreGraphics
import QuartzCore

// MARK: - Edge Resize Coordinator (Linked Edge Resize)
// Drag a shared edge between tiled windows → keep every window on that seam
// flush (halves, thirds, 2×2 — up to 4). macOS owns the primary resize; ReLay
// rewrites the other seam participants.

final class EdgeResizeCoordinator {

    private struct Participant {
        let window: AXUIElement
        let index: Int
        var lastWritten: CGRect
    }

    private struct Session {
        let primary: AXUIElement
        let edge: WindowEdge
        let axis: SeamAxis
        let startCenter: CGFloat
        let startFrames: [CGRect]
        let gap: CGFloat
        let minSize: CGFloat
        var others: [Participant]
        var lastPrimaryFrame: CGRect
        var lastWriteTime: CFTimeInterval
        /// True when seam-line geometry is valid; otherwise pairwise fallback.
        let useSeamLine: Bool
    }

    private var session: Session?
    private let minWriteInterval: CFTimeInterval = 1.0 / 120.0

    var isActive: Bool { session != nil }

    @discardableResult
    func begin(at location: CGPoint) -> Bool {
        end()

        let gap = max(0, ReLaySettings.layoutPadding)
        // Detection allows slack so slightly drifted tiles still link.
        let detectGap = max(gap, LinkedResize.defaultGap)

        let order = WindowServerList.onScreenOrder()
        guard let hit = WindowServerList.topmost(
                at: location, in: order, expandBy: LinkedResize.edgeThickness
              ),
              let cgEdge = LinkedResize.edge(at: location, of: hit.bounds)
        else {
            return false
        }

        // Deeper title-bar hits are for snap gestures / window moves, not resize.
        if cgEdge == .top,
           location.y > hit.bounds.minY + LinkedResize.edgeThickness,
           TitleBarHitTest.titleBarRect(for: hit.bounds).contains(location) {
            return false
        }

        guard let primary = AXWindowOps.window(pid: hit.pid, matching: hit.bounds)
                ?? AXWindowOps.window(at: location)
                ?? AXWindowOps.frontmost(),
              let primaryFrame = AXWindowOps.frame(primary)
        else {
            Logger.log("linked-edge abort: no AX primary", subsystem: "layout")
            return false
        }

        // Prefer live AX edge; keep CG edge if AX lag disagrees (do NOT hard-fail).
        let edge = LinkedResize.edge(at: location, of: primaryFrame) ?? cgEdge
        let axis = SeamGeometry.axis(for: edge)
        let minSize: CGFloat = axis == .vertical
            ? AXWindowOps.minWritableWidth
            : AXWindowOps.minWritableHeight

        let desk = collectDeskWindows(
            order: order,
            screen: WindowRuntime.usableScreen(containing: primaryFrame),
            primary: primary,
            primaryFrame: primaryFrame,
            primaryPID: hit.pid
        )
        guard desk.windows.count >= 2 else {
            Logger.log("linked-edge abort: solo on screen", subsystem: "layout")
            return false
        }

        guard let plan = resolvePlan(
            desk: desk,
            primaryFrame: primaryFrame,
            edge: edge,
            axis: axis,
            detectGap: detectGap,
            applyGap: gap,
            minSize: minSize
        ) else {
            Logger.log("linked-edge abort: no neighbor edge=\(edge)", subsystem: "layout")
            return false
        }

        AXWindowOps.disableEnhancedUserInterface(owning: primary)
        var others: [Participant] = []
        for index in plan.otherIndices {
            let window = desk.windows[index]
            AXWindowOps.disableEnhancedUserInterface(owning: window)
            others.append(Participant(
                window: window,
                index: index,
                lastWritten: desk.frames[index]
            ))
        }
        guard !others.isEmpty else { return false }

        session = Session(
            primary: primary,
            edge: edge,
            axis: axis,
            startCenter: plan.startCenter,
            startFrames: desk.frames,
            gap: plan.applyGap,
            minSize: minSize,
            others: others,
            lastPrimaryFrame: primaryFrame,
            lastWriteTime: 0,
            useSeamLine: plan.useSeamLine
        )
        Logger.log(
            "linked-edge begin edge=\(edge) others=\(others.count) seam=\(plan.useSeamLine) gap=\(Int(plan.applyGap))",
            subsystem: "layout"
        )
        return true
    }

    func update() {
        guard var session else { return }
        let now = CACurrentMediaTime()
        if session.lastWriteTime > 0, now - session.lastWriteTime < minWriteInterval {
            return
        }

        guard let primaryNow = AXWindowOps.frame(session.primary) else { return }
        if framesNearlyEqual(primaryNow, session.lastPrimaryFrame) { return }
        session.lastPrimaryFrame = primaryNow

        if session.useSeamLine {
            let newCenter = SeamGeometry.center(
                fromPrimary: primaryNow, edge: session.edge, gap: session.gap
            )
            if let nextFrames = SeamGeometry.applySeamLine(
                frames: session.startFrames,
                axis: session.axis,
                startCenter: session.startCenter,
                newCenter: newCenter,
                gap: session.gap,
                minSize: session.minSize
            ) {
                writeParticipants(&session, nextFrames: nextFrames, now: now)
                self.session = session
                return
            }
        }

        // Pairwise fallback — direct neighbors from the live primary edge.
        var wrote = false
        for i in session.others.indices {
            let start = session.startFrames[session.others[i].index]
            guard let next = LinkedResize.resizedNeighbor(
                start,
                sharing: session.edge,
                primaryNow: primaryNow,
                gap: session.gap,
                minSize: session.minSize
            ) else { continue }
            if framesNearlyEqual(next, session.others[i].lastWritten) { continue }
            if AXWindowOps.setFrame(session.others[i].window, next, prepareApp: false) {
                session.others[i].lastWritten = next
                wrote = true
            }
        }
        if wrote { session.lastWriteTime = now }
        self.session = session
    }

    func end() {
        if session != nil {
            Logger.log("linked-edge end", subsystem: "layout")
        }
        session = nil
    }

    // MARK: - Plan

    private struct Plan {
        let startCenter: CGFloat
        let applyGap: CGFloat
        let otherIndices: [Int]
        let useSeamLine: Bool
    }

    private func resolvePlan(
        desk: Desk,
        primaryFrame: CGRect,
        edge: WindowEdge,
        axis: SeamAxis,
        detectGap: CGFloat,
        applyGap: CGFloat,
        minSize: CGFloat
    ) -> Plan? {
        let primaryIndex = desk.primaryIndex

        // 1) Direct neighbors that share this edge (proven path).
        var neighborIndices: [Int] = []
        for i in desk.frames.indices where i != primaryIndex {
            if LinkedResize.shares(
                edge, of: primaryFrame, with: desk.frames[i],
                gap: detectGap, tolerance: LinkedResize.shareTolerance
            ) {
                neighborIndices.append(i)
            }
        }
        guard !neighborIndices.isEmpty else { return nil }

        let peer = desk.frames[neighborIndices[0]]
        let measured = measuredGapAcross(primary: primaryFrame, peer: peer, edge: edge)
        let useGap = measured > 0.5 ? measured : applyGap
        let startCenter = SeamGeometry.center(
            fromPrimary: primaryFrame, edge: edge, gap: useGap
        )

        // 2) Expand to full seam line (2×2 cross) when geometry allows.
        var indices = Set(neighborIndices)
        let sides = SeamGeometry.participants(
            among: desk.frames, axis: axis, center: startCenter, gap: useGap
        )
        for i in sides.leading + sides.trailing where i != primaryIndex {
            indices.insert(i)
        }

        let useSeamLine = SeamGeometry.applySeamLine(
            frames: desk.frames,
            axis: axis,
            startCenter: startCenter,
            newCenter: startCenter,
            gap: useGap,
            minSize: minSize
        ) != nil

        return Plan(
            startCenter: startCenter,
            applyGap: useGap,
            otherIndices: Array(indices).sorted(),
            useSeamLine: useSeamLine
        )
    }

    private func measuredGapAcross(primary: CGRect, peer: CGRect, edge: WindowEdge) -> CGFloat {
        switch edge {
        case .right:  return max(0, peer.minX - primary.maxX)
        case .left:   return max(0, primary.minX - peer.maxX)
        case .bottom: return max(0, peer.minY - primary.maxY)
        case .top:    return max(0, primary.minY - peer.maxY)
        }
    }

    private func writeParticipants(
        _ session: inout Session,
        nextFrames: [CGRect],
        now: CFTimeInterval
    ) {
        var wrote = false
        for i in session.others.indices {
            let next = nextFrames[session.others[i].index]
            if framesNearlyEqual(next, session.others[i].lastWritten) { continue }
            if AXWindowOps.setFrame(session.others[i].window, next, prepareApp: false) {
                session.others[i].lastWritten = next
                wrote = true
            }
        }
        if wrote { session.lastWriteTime = now }
    }

    private func framesNearlyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5
            && abs(a.minY - b.minY) < 0.5
            && abs(a.width - b.width) < 0.5
            && abs(a.height - b.height) < 0.5
    }

    // MARK: - Desk

    private struct Desk {
        var windows: [AXUIElement]
        var frames: [CGRect]
        var primaryIndex: Int
    }

    /// Collect on-screen standard windows. Prefer edge-sharers with the primary
    /// so chrome/tooltips higher in z-order cannot crowd out real tiles.
    private func collectDeskWindows(
        order: [WindowServerList.Entry],
        screen: CGRect,
        primary: AXUIElement,
        primaryFrame: CGRect,
        primaryPID: pid_t
    ) -> Desk {
        var windows: [AXUIElement] = [primary]
        var frames: [CGRect] = [primaryFrame]
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let gap = max(ReLaySettings.layoutPadding, LinkedResize.defaultGap)

        struct Candidate {
            let window: AXUIElement
            let frame: CGRect
            let sharesEdge: Bool
        }
        var candidates: [Candidate] = []

        for entry in order {
            if entry.pid == ownPID { continue }
            if entry.pid == primaryPID,
               WindowServerList.framesMatch(entry.bounds, primaryFrame, tolerance: 24) {
                continue
            }
            guard WindowEligibility.isTileableCGEntry(
                pid: entry.pid, bounds: entry.bounds, on: screen
            ) else { continue }

            guard let win = AXWindowOps.window(pid: entry.pid, matching: entry.bounds)
                    ?? AXWindowOps.window(pid: entry.pid, matching: entry.bounds, tolerance: 24),
                  WindowEligibility.isTileableWindow(win, on: screen),
                  let live = AXWindowOps.frame(win)
            else { continue }

            if windows.contains(where: { CFEqual($0, win) }) { continue }
            if candidates.contains(where: { CFEqual($0.window, win) }) { continue }

            let shares = WindowEdge.allCases.contains {
                LinkedResize.shares($0, of: primaryFrame, with: live, gap: gap)
            }
            candidates.append(Candidate(window: win, frame: live, sharesEdge: shares))
        }

        // Edge-sharing tiles first, then other large windows (for seam expansion).
        candidates.sort { a, b in
            if a.sharesEdge != b.sharesEdge { return a.sharesEdge && !b.sharesEdge }
            return false
        }

        for candidate in candidates {
            windows.append(candidate.window)
            frames.append(candidate.frame)
            if windows.count >= AutoLayoutEngine.maxTileCount { break }
        }

        return Desk(windows: windows, frames: frames, primaryIndex: 0)
    }
}
