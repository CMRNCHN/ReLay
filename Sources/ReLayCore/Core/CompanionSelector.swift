import CoreGraphics

// MARK: - Companion Selector
// Pure: candidate window descriptors → the one window that should fill the
// leftover region after a snap. No AX, no NSScreen.

enum CompanionSelector {

    struct Candidate {
        let id: Int
        let frame: CGRect
        let bundleID: String
        /// Front-to-back index from the window server; 0 is frontmost.
        let zOrder: Int

        init(id: Int, frame: CGRect, bundleID: String, zOrder: Int) {
            self.id = id
            self.frame = frame
            self.bundleID = bundleID
            self.zOrder = zOrder
        }
    }

    /// A window must show at least this much of itself on the target screen to
    /// be considered — filters palettes, inspectors and off-screen windows.
    static let minOverlapEdge: CGFloat = 120
    static let minOverlapArea: CGFloat = 40_000

    /// The frontmost eligible window — the one the user was most recently
    /// looking at. Picking by area instead selects whatever happens to be
    /// biggest, which is usually a window the gesture had nothing to do with.
    static func best(
        from candidates: [Candidate],
        on screen: CGRect,
        excludingBundleIDs excluded: Set<String> = []
    ) -> Candidate? {
        candidates
            .filter { isEligible($0, on: screen, excludingBundleIDs: excluded) }
            .min { $0.zOrder < $1.zOrder }
    }

    static func isEligible(
        _ candidate: Candidate,
        on screen: CGRect,
        excludingBundleIDs excluded: Set<String> = []
    ) -> Bool {
        let overlap = candidate.frame.intersection(screen)
        guard overlap.width > minOverlapEdge,
              overlap.height > minOverlapEdge,
              overlap.width * overlap.height > minOverlapArea
        else { return false }
        guard !excluded.contains(candidate.bundleID) else { return false }
        return WindowMutabilityPolicy.decision(for: candidate.bundleID) == .allow
    }
}
