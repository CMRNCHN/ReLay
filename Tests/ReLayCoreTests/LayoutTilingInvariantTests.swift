import XCTest
@testable import ReLayCore

/// Geometry invariants every snap must satisfy: primary and companion never
/// overlap, both stay on screen, and the pair covers the usable area.
final class LayoutTilingInvariantTests: XCTestCase {

    private let screens: [(String, CGRect)] = [
        ("MacBook 14\"",   CGRect(x: 0, y: 38, width: 1512, height: 907)),
        ("MacBook 16\"",   CGRect(x: 0, y: 38, width: 1728, height: 1079)),
        ("Studio Display", CGRect(x: 0, y: 38, width: 2560, height: 1377)),
        ("Odd offset",     CGRect(x: -1440, y: 25, width: 1440, height: 875)),
    ]
    private let gap: CGFloat = 8
    private let tiled: [WindowLayoutState] = [.leftHalf, .rightHalf, .leftThird, .rightThird]

    private func bounds(_ screen: CGRect) -> CGRect {
        LayoutFrameResolver.frame(for: .fullscreen, in: screen, gap: gap)
    }

    // MARK: - Primary vs companion

    func testPrimaryAndCompanionNeverOverlap() {
        for (name, screen) in screens {
            for layout in tiled {
                let primary = LayoutFrameResolver.frame(for: layout, in: screen, gap: gap)
                guard let companion = LayoutFrameResolver
                    .companionFrames(for: layout, count: 1, in: screen, gap: gap).first else {
                    return XCTFail("\(layout) on \(name) produced no companion frame")
                }
                let overlap = primary.intersection(companion)
                XCTAssertTrue(overlap.isNull || overlap.width * overlap.height == 0,
                              "\(name)/\(layout): primary \(primary) overlaps companion \(companion)")
            }
        }
    }

    /// The resolver takes a `gap` and insets the outer edges by gap/2, but
    /// adjacent tiles are laid out edge-to-edge — the two windows touch.
    func testPrimaryAndCompanionAreSeparatedByTheGap() {
        for (name, screen) in screens {
            for layout in tiled {
                let primary = LayoutFrameResolver.frame(for: layout, in: screen, gap: gap)
                guard let companion = LayoutFrameResolver
                    .companionFrames(for: layout, count: 1, in: screen, gap: gap).first else { continue }
                let seam = primary.minX < companion.minX
                    ? companion.minX - primary.maxX
                    : primary.minX - companion.maxX
                XCTAssertEqual(seam, gap, accuracy: 0.5,
                               "\(name)/\(layout): expected a \(gap)pt seam, got \(seam)pt")
            }
        }
    }

    func testCompanionStaysInsideUsableBounds() {
        for (name, screen) in screens {
            for layout in tiled {
                guard let companion = LayoutFrameResolver
                    .companionFrames(for: layout, count: 1, in: screen, gap: gap).first else { continue }
                XCTAssertTrue(bounds(screen).insetBy(dx: -0.5, dy: -0.5).contains(companion),
                              "\(name)/\(layout): companion \(companion) escapes \(bounds(screen))")
            }
        }
    }

    func testHalvesCoverTheUsableScreen() {
        for (name, screen) in screens {
            let left = LayoutFrameResolver.frame(for: .leftHalf, in: screen, gap: gap)
            let right = LayoutFrameResolver.frame(for: .rightHalf, in: screen, gap: gap)
            XCTAssertEqual(left.union(right), bounds(screen), "\(name): halves must tile the screen")
        }
    }

    func testThirdAndCompanionCoverTheUsableScreen() {
        for (name, screen) in screens {
            for layout: WindowLayoutState in [.leftThird, .rightThird] {
                let primary = LayoutFrameResolver.frame(for: layout, in: screen, gap: gap)
                guard let companion = LayoutFrameResolver
                    .companionFrames(for: layout, count: 1, in: screen, gap: gap).first else { continue }
                let union = primary.union(companion)
                XCTAssertEqual(union.minX, bounds(screen).minX, accuracy: 0.5, "\(name)/\(layout)")
                XCTAssertEqual(union.maxX, bounds(screen).maxX, accuracy: 0.5, "\(name)/\(layout)")
            }
        }
    }

    // MARK: - Every applied frame

    func testEveryLayoutFrameStaysInsideTheUsableScreen() {
        for (name, screen) in screens {
            // `.floating` is covered separately below.
            for layout in WindowLayoutState.allCases where layout != .floating {
                let frame = LayoutFrameResolver.frame(for: layout, in: screen, gap: gap)
                XCTAssertTrue(bounds(screen).insetBy(dx: -0.5, dy: -0.5).contains(frame),
                              "\(name)/\(layout): \(frame) is outside the usable area \(bounds(screen))")
            }
        }
    }

    /// `.floating` resolves to the raw screen rect — larger than `.fullscreen`
    /// and ignoring the gap entirely. The transition graph *does* route into
    /// `.floating` (fullscreen/center/sixth + swipe down), so this frame is
    /// applied to real windows.
    func testFloatingFrameIsNotLargerThanFullscreen() {
        for (name, screen) in screens {
            let floating = LayoutFrameResolver.frame(for: .floating, in: screen, gap: gap)
            let full = LayoutFrameResolver.frame(for: .fullscreen, in: screen, gap: gap)
            XCTAssertLessThanOrEqual(floating.width, full.width, "\(name): floating is wider than fullscreen")
            XCTAssertLessThanOrEqual(floating.height, full.height, "\(name): floating is taller than fullscreen")
        }
    }

    /// A "shrink" gesture must not grow the window.
    func testSwipeDownFromFullscreenShrinksTheWindow() {
        let sim = RuntimeMirror()
        sim.frames[101] = CGRect(x: 400, y: 300, width: 800, height: 500)
        sim.swipe(on: 101, dx: 0, dy: -200)              // up → center
        sim.swipe(on: 101, dx: 0, dy: -200)              // up → fullscreen
        XCTAssertEqual(sim.layout, .fullscreen)
        let full = sim.frames[101]!

        sim.swipe(on: 101, dx: 0, dy: 200)               // down → leftTwoThirds
        let after = sim.frames[101]!
        XCTAssertEqual(sim.layout, .leftTwoThirds)
        XCTAssertLessThan(after.width * after.height, full.width * full.height,
                          "swiping down out of fullscreen should shrink (got \(after))")
    }

    // MARK: - Pixel hygiene

    /// Thirds land on fractional pixels; AppKit rounds them per app, which is
    /// what produces 1pt seams and makes the applied frame differ from the
    /// requested one.
    func testTiledFramesAreIntegral() {
        for (name, screen) in screens {
            for layout in tiled {
                let f = LayoutFrameResolver.frame(for: layout, in: screen, gap: gap)
                for (label, value) in [("minX", f.minX), ("minY", f.minY),
                                       ("width", f.width), ("height", f.height)] {
                    XCTAssertEqual(value, value.rounded(), accuracy: 0.001,
                                   "\(name)/\(layout): \(label) = \(value) is not pixel aligned")
                }
            }
        }
    }

    // MARK: - Degenerate input

    func testZeroScreenProducesNoUsableFrames() {
        for layout in WindowLayoutState.allCases {
            let f = LayoutFrameResolver.frame(for: layout, in: .zero, gap: gap)
            XCTAssertLessThanOrEqual(f.width, 1.0, "\(layout) on a zero screen: \(f)")
            XCTAssertLessThanOrEqual(f.height, 1.0, "\(layout) on a zero screen: \(f)")
        }
    }
}
