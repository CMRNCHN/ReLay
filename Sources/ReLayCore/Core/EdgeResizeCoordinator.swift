import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - Edge Resize Coordinator
// When the user drags a window edge shared with another on-screen window,
// keep the neighbor flush. macOS still owns the primary resize; we only
// rewrite companions.
//
// Hot path: mouse-down uses CGWindowList for a cheap edge probe, then AX only
// for the primary + geometric neighbors. Drag updates read one AX frame and
// write neighbors only when the result actually changes.

final class EdgeResizeCoordinator {

    private struct Neighbor {
        let window: AXUIElement
        let startFrame: CGRect
        var lastWritten: CGRect
    }

    private struct Session {
        let primary: AXUIElement
        let edge: WindowEdge
        var neighbors: [Neighbor]
        var lastPrimaryFrame: CGRect
    }

    private var session: Session?

    var isActive: Bool { session != nil }

    /// Begin a linked resize if `location` is on a window edge that has neighbors.
    @discardableResult
    func begin(at location: CGPoint) -> Bool {
        end()

        // Cheap gate: CG bounds only — most clicks never need AX.
        let order = WindowServerList.onScreenOrder()
        guard let hit = WindowServerList.topmost(
                at: location, in: order, expandBy: LinkedResize.edgeThickness
              ),
              let edge = LinkedResize.edge(at: location, of: hit.bounds)
        else { return false }

        // Deeper title-bar hits are for snap gestures / window moves, not resize.
        if edge == .top,
           location.y > hit.bounds.minY + LinkedResize.edgeThickness,
           TitleBarHitTest.titleBarRect(for: hit.bounds).contains(location) {
            return false
        }

        guard let primary = AXWindowOps.window(pid: hit.pid, matching: hit.bounds)
                ?? AXWindowOps.window(at: location)
                ?? AXWindowOps.frontmost(),
              let frame = AXWindowOps.frame(primary)
        else { return false }

        // Re-check edge against the live AX frame (CG bounds can lag by a few px).
        guard LinkedResize.edge(at: location, of: frame) == edge else { return false }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let screen = WindowRuntime.usableScreen(containing: frame)

        var neighborWindows: [AXUIElement] = []
        var neighborFrames: [CGRect] = []

        for entry in order {
            if entry.pid == hit.pid, WindowServerList.framesMatch(entry.bounds, hit.bounds) {
                continue
            }
            if entry.pid == ownPID { continue }

            let overlap = entry.bounds.intersection(screen)
            guard overlap.width > 40, overlap.height > 40 else { continue }
            guard LinkedResize.shares(edge, of: frame, with: entry.bounds) else { continue }

            let bid = NSRunningApplication(processIdentifier: entry.pid)?.bundleIdentifier ?? ""
            guard WindowMutabilityPolicy.decision(for: bid) == .allow else { continue }
            guard let win = AXWindowOps.window(pid: entry.pid, matching: entry.bounds),
                  let live = AXWindowOps.frame(win)
            else { continue }
            // Confirm share against live AX geometry before committing.
            guard LinkedResize.shares(edge, of: frame, with: live) else { continue }

            AXWindowOps.disableEnhancedUserInterface(owning: win)
            neighborWindows.append(win)
            neighborFrames.append(live)
        }

        guard !neighborWindows.isEmpty else { return false }

        let neighbors = zip(neighborWindows, neighborFrames).map {
            Neighbor(window: $0.0, startFrame: $0.1, lastWritten: $0.1)
        }
        AXWindowOps.disableEnhancedUserInterface(owning: primary)
        session = Session(primary: primary, edge: edge, neighbors: neighbors, lastPrimaryFrame: frame)
        return true
    }

    func update() {
        guard var session else { return }
        guard let primaryNow = AXWindowOps.frame(session.primary) else { return }
        // Ignore sub-pixel AX chatter.
        if abs(primaryNow.minX - session.lastPrimaryFrame.minX) < 1,
           abs(primaryNow.minY - session.lastPrimaryFrame.minY) < 1,
           abs(primaryNow.width - session.lastPrimaryFrame.width) < 1,
           abs(primaryNow.height - session.lastPrimaryFrame.height) < 1 {
            return
        }
        session.lastPrimaryFrame = primaryNow

        for i in session.neighbors.indices {
            guard let next = LinkedResize.resizedNeighbor(
                session.neighbors[i].startFrame,
                sharing: session.edge,
                primaryNow: primaryNow
            ) else { continue }
            let prev = session.neighbors[i].lastWritten
            if abs(next.minX - prev.minX) < 0.5,
               abs(next.minY - prev.minY) < 0.5,
               abs(next.width - prev.width) < 0.5,
               abs(next.height - prev.height) < 0.5 {
                continue
            }
            // EUI already disabled in begin().
            if AXWindowOps.setFrame(session.neighbors[i].window, next, prepareApp: false) {
                session.neighbors[i].lastWritten = next
            }
        }
        self.session = session
    }

    func end() {
        session = nil
    }
}
