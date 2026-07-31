import XCTest
@testable import ReLayCore

/// Structural properties of the (state × direction) → state table.
final class LayoutTransitionGraphTests: XCTestCase {

    private let graph = LayoutTransitionGraph()
    private let directions: [GestureDirection] = [.left, .right, .up, .down]

    private func next(_ s: WindowLayoutState, _ d: GestureDirection) -> WindowLayoutState? {
        graph.nextState(from: s, moving: d)
    }

    private func opposite(_ d: GestureDirection) -> GestureDirection {
        switch d {
        case .left:  return .right
        case .right: return .left
        case .up:    return .down
        case .down:  return .up
        }
    }

    // MARK: - Reachability

    /// Every layout the app models should be reachable by swiping. The four
    /// sixth states are only ever reachable *from each other*, so no gesture
    /// sequence can ever produce them — a quarter of the layout vocabulary is
    /// dead code.
    func testEveryLayoutIsReachableFromFloating() {
        XCTExpectFailure("Known gap: the four sixth layouts have no inbound transition. "
                       + "See storage/diagnostics/snap-messiness-report.md")
        var seen: Set<WindowLayoutState> = [.floating]
        var queue: [WindowLayoutState] = [.floating]
        while let state = queue.popLast() {
            for d in directions {
                guard let n = next(state, d), !seen.contains(n) else { continue }
                seen.insert(n)
                queue.append(n)
            }
        }
        let unreachable = WindowLayoutState.allCases.filter { !seen.contains($0) }
        XCTAssertEqual(unreachable, [], "unreachable layouts: \(unreachable)")
    }

    /// Once a window is snapped the user should be able to get back to where
    /// they started with the opposite swipe. Several transitions are one-way.
    func testTransitionsAreReversible() {
        XCTExpectFailure("Known gap: 23 of 35 transitions cannot be undone by the opposite swipe. "
                       + "See storage/diagnostics/snap-messiness-report.md")
        var oneWay: [String] = []
        for state in WindowLayoutState.allCases {
            for d in directions {
                guard let n = next(state, d) else { continue }
                if next(n, opposite(d)) != state {
                    oneWay.append("\(state) --\(d)--> \(n), but \(n) --\(opposite(d))--> \(String(describing: next(n, opposite(d))))")
                }
            }
        }
        XCTAssertEqual(oneWay, [], "one-way transitions:\n" + oneWay.joined(separator: "\n"))
    }

    // MARK: - Documented behaviour

    func testHorizontalSnapLadderFromFloating() {
        XCTAssertEqual(next(.floating, .left), .leftHalf)
        XCTAssertEqual(next(.leftHalf, .left), .leftThird)
        XCTAssertNil(next(.leftThird, .left), "third resists further left swipes")
        XCTAssertEqual(next(.floating, .right), .rightHalf)
        XCTAssertEqual(next(.rightHalf, .right), .rightThird)
        XCTAssertNil(next(.rightThird, .right))
    }

    /// Both `.left` and `.down` collapse a half into a third, so the same
    /// visual result has two very different follow-up behaviours (left resists,
    /// down minimizes).
    func testHalfCollapsesToThirdOnTwoDifferentDirections() {
        XCTAssertEqual(next(.leftHalf, .left), .leftThird)
        XCTAssertEqual(next(.leftHalf, .down), .leftThird)
    }

    /// Half grows through two-thirds before fullscreen; other columns still
    /// jump straight to fullscreen.
    func testUpLadderFromHalfGoesThroughTwoThirds() {
        XCTAssertEqual(next(.leftHalf, .up), .leftTwoThirds)
        XCTAssertEqual(next(.leftTwoThirds, .up), .fullscreen)
        XCTAssertEqual(next(.rightHalf, .up), .rightTwoThirds)
        XCTAssertEqual(next(.rightTwoThirds, .up), .fullscreen)
        XCTAssertEqual(next(.leftThird, .up), .fullscreen)
        XCTAssertEqual(next(.fullscreen, .up), .center, "a second up swipe from fullscreen shrinks when alone")
    }

    /// With neighbors on screen, center is skipped: floating jumps straight to
    /// fullscreen, and fullscreen no longer shrinks back through center.
    func testCenterSkippedWhenNotSolo() {
        XCTAssertEqual(
            graph.nextState(from: .floating, moving: .up, allowCenter: false),
            .fullscreen
        )
        XCTAssertNil(
            graph.nextState(from: .fullscreen, moving: .up, allowCenter: false)
        )
        // Solo still gets center.
        XCTAssertEqual(
            graph.nextState(from: .floating, moving: .up, allowCenter: true),
            .center
        )
        // Already in center: exits still work even with neighbors.
        XCTAssertEqual(
            graph.nextState(from: .center, moving: .up, allowCenter: false),
            .fullscreen
        )
        XCTAssertEqual(
            graph.nextState(from: .center, moving: .down, allowCenter: false),
            .floating
        )
    }

    func testDownFromFullscreenStepsThroughTwoThirds() {
        XCTAssertEqual(next(.fullscreen, .down), .leftTwoThirds)
        XCTAssertEqual(next(.leftTwoThirds, .down), .leftHalf)
        XCTAssertEqual(next(.rightTwoThirds, .down), .rightHalf)
    }

    /// There is no direct route back to an unmanaged window from a half or a
    /// third: down shrinks and then minimizes.
    func testNoDirectEscapeFromColumnsToFloating() {
        for state: WindowLayoutState in [.leftHalf, .rightHalf, .leftThird, .rightThird,
                                         .leftTwoThirds, .rightTwoThirds] {
            XCTAssertNotEqual(next(state, .down), .floating, "\(state)")
        }
        XCTAssertNil(next(.leftThird, .down), "thirds fall through to the reducer's minimize path")
        XCTAssertNil(next(.rightThird, .down))
    }

    func testCrossScreenJumpsBetweenHalves() {
        XCTAssertEqual(next(.leftHalf, .right), .rightHalf)
        XCTAssertEqual(next(.rightHalf, .left), .leftHalf)
    }

    /// Table snapshot — any change to the gesture model has to update this.
    func testTransitionTableSnapshot() {
        var lines: [String] = []
        for state in WindowLayoutState.allCases {
            for d in directions {
                lines.append("\(state).\(d) = \(next(state, d).map(String.init(describing:)) ?? "—")")
            }
        }
        XCTAssertEqual(lines.count, WindowLayoutState.allCases.count * 4)
        let defined = lines.filter { !$0.hasSuffix("—") }.count
        // 13 states × some directions; assert the current table size explicitly.
        XCTAssertEqual(defined, 43, "transition table size changed:\n" + lines.joined(separator: "\n"))
    }

    // MARK: - Direction classification

    func testGestureDirectionFromDeltas() {
        XCTAssertEqual(GestureDirection(effectiveX: -10, effectiveY: 0), .left)
        XCTAssertEqual(GestureDirection(effectiveX: 10, effectiveY: 0), .right)
        XCTAssertEqual(GestureDirection(effectiveX: 0, effectiveY: 10), .down)
        XCTAssertEqual(GestureDirection(effectiveX: 0, effectiveY: -10), .up)
        XCTAssertNil(GestureDirection(effectiveX: 0, effectiveY: 0))
    }

    /// Exactly diagonal input silently resolves to a vertical gesture — and
    /// vertical from `.floating` means minimize.
    func testPerfectDiagonalResolvesVertically() {
        XCTAssertEqual(GestureDirection(effectiveX: 10, effectiveY: 10), .down)
        XCTAssertEqual(GestureDirection(effectiveX: -10, effectiveY: 10), .down)
    }
}
