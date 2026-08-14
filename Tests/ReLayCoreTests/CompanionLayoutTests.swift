import XCTest
@testable import ReLayCore

final class CompanionLayoutTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
    private let gap: CGFloat = 8

    func testLeftHalfFillsRightHalf() {
        let frames = LayoutFrameResolver.companionFrames(for: .leftHalf, count: 1, in: screen, gap: gap)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0], LayoutFrameResolver.frame(for: .rightHalf, in: screen, gap: gap))
    }

    func testRightHalfFillsLeftHalf() {
        let frames = LayoutFrameResolver.companionFrames(for: .rightHalf, count: 1, in: screen, gap: gap)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0], LayoutFrameResolver.frame(for: .leftHalf, in: screen, gap: gap))
    }

    func testLeftThirdFillsRemainingTwoThirds() {
        let frames = LayoutFrameResolver.companionFrames(for: .leftThird, count: 1, in: screen, gap: gap)
        XCTAssertEqual(frames.count, 1)
        let primary = LayoutFrameResolver.frame(for: .leftThird, in: screen, gap: gap)
        XCTAssertEqual(frames[0].minX, primary.maxX + gap, accuracy: 0.5)
        XCTAssertEqual(frames[0].maxX, LayoutFrameResolver.frame(for: .fullscreen, in: screen, gap: gap).maxX, accuracy: 0.5)
        XCTAssertEqual(frames[0].height, primary.height, accuracy: 0.5)
    }

    func testMultipleCompanionsStackVertically() {
        let frames = LayoutFrameResolver.companionFrames(for: .leftHalf, count: 2, in: screen, gap: gap)
        XCTAssertEqual(frames.count, 2)
        let region = LayoutFrameResolver.frame(for: .rightHalf, in: screen, gap: gap)
        XCTAssertEqual(frames[0].minY, region.minY, accuracy: 0.5)
        XCTAssertEqual(frames[1].maxY, region.maxY, accuracy: 0.5)
        XCTAssertEqual(frames[0].width, region.width, accuracy: 0.5)
        XCTAssertEqual(frames[1].width, region.width, accuracy: 0.5)
        XCTAssertLessThan(frames[0].maxY, frames[1].minY + 0.5)
    }

    func testFullscreenAndCenterLeaveCompanionsAlone() {
        XCTAssertTrue(LayoutFrameResolver.companionFrames(for: .fullscreen, count: 2, in: screen).isEmpty)
        XCTAssertTrue(LayoutFrameResolver.companionFrames(for: .center, count: 2, in: screen).isEmpty)
        XCTAssertTrue(LayoutFrameResolver.companionFrames(for: .floating, count: 2, in: screen).isEmpty)
    }

    func testZeroCountReturnsEmpty() {
        XCTAssertTrue(LayoutFrameResolver.companionFrames(for: .leftHalf, count: 0, in: screen).isEmpty)
    }

    func testManyCompanionsNeverMicroStack() {
        let frames = LayoutFrameResolver.companionFrames(for: .leftHalf, count: 6, in: screen, gap: gap)
        XCTAssertLessThanOrEqual(frames.count, LayoutFrameResolver.maxStackedCompanions)
        for frame in frames {
            XCTAssertGreaterThanOrEqual(frame.height, AXWindowOps.minWritableHeight)
            XCTAssertGreaterThanOrEqual(frame.width, AXWindowOps.minWritableWidth)
        }
    }

    func testLeavingFullscreenWithManyPeersRestoresSavedFrames() {
        let sim = RuntimeMirror()
        let left = LayoutFrameResolver.frame(for: .leftHalf, in: sim.screen)
        sim.frames[101] = left
        // Five peers with healthy sizes before fullscreen.
        for (i, pid) in [102, 103, 104, 105, 106].enumerated() {
            sim.frames[pid] = CGRect(x: 600, y: CGFloat(40 + i * 40), width: 500, height: 400)
            sim.bundleIDs[pid] = "com.example.\(pid)"
        }
        sim.bundleIDs[101] = "com.example.a"

        sim.swipe(on: 101, dx: 0, dy: -200) // → twoThirds
        sim.swipe(on: 101, dx: 0, dy: -200) // → fullscreen
        XCTAssertEqual(sim.layout, .fullscreen)
        XCTAssertEqual(Set(sim.minimized), Set([102, 103, 104, 105, 106]))

        sim.swipe(on: 101, dx: 0, dy: 200) // leave fullscreen → twoThirds
        XCTAssertEqual(sim.layout, .leftTwoThirds)
        // No peer should be crushed below the writable floor.
        for pid in [102, 103, 104, 105, 106] as [pid_t] {
            let frame = sim.frames[pid]!
            XCTAssertGreaterThanOrEqual(frame.height, AXWindowOps.minWritableHeight, "pid \(pid)")
            XCTAssertGreaterThanOrEqual(frame.width, AXWindowOps.minWritableWidth, "pid \(pid)")
        }
    }

    func testThirdToFullscreenMinimizesOthers() {
        XCTAssertTrue(WindowRuntime.shouldMinimizeOthers(from: .leftThird, to: .fullscreen))
        XCTAssertTrue(WindowRuntime.shouldMinimizeOthers(from: .rightThird, to: .fullscreen))
        XCTAssertTrue(WindowRuntime.shouldMinimizeOthers(from: .leftHalf, to: .fullscreen))
        XCTAssertTrue(WindowRuntime.shouldMinimizeOthers(from: .leftTwoThirds, to: .fullscreen))
        XCTAssertTrue(WindowRuntime.shouldMinimizeOthers(from: .floating, to: .fullscreen))
        XCTAssertFalse(WindowRuntime.shouldMinimizeOthers(from: .leftThird, to: .leftHalf))
        XCTAssertFalse(WindowRuntime.shouldMinimizeOthers(from: .fullscreen, to: .fullscreen))
    }

    func testSwipeFromThirdToFullscreenMinimizesCompanions() {
        let sim = RuntimeMirror()
        let left = LayoutFrameResolver.frame(for: .leftThird, in: sim.screen)
        let right = LayoutFrameResolver.frame(for: .rightThird, in: sim.screen)
        let mid = LayoutFrameResolver.frame(for: .leftHalf, in: sim.screen) // another on-screen window
        sim.frames[101] = left
        sim.frames[102] = right
        sim.frames[103] = mid
        sim.bundleIDs = [
            101: "com.example.a",
            102: "com.example.b",
            103: "com.example.c",
        ]
        // Would otherwise try to place a companion — must not, for this path.
        sim.companionPicker = { _, _ in 102 }

        sim.swipe(on: 101, dx: 0, dy: -200) // up → fullscreen

        XCTAssertEqual(sim.layout, .fullscreen)
        XCTAssertEqual(sim.frames[101], LayoutFrameResolver.frame(for: .fullscreen, in: sim.screen))
        XCTAssertEqual(Set(sim.minimized), Set([102, 103]))
        XCTAssertFalse(sim.writes.contains { $0.window == 102 },
                       "companions should be minimized, not retiled")
    }

    func testSwipeFromHalfToFullscreenMinimizesCompanions() {
        let sim = RuntimeMirror()
        sim.frames[101] = LayoutFrameResolver.frame(for: .leftHalf, in: sim.screen)
        sim.frames[102] = LayoutFrameResolver.frame(for: .rightHalf, in: sim.screen)
        sim.bundleIDs = [101: "com.example.a", 102: "com.example.b"]
        // half → twoThirds (no minimize), then twoThirds → fullscreen (minimize)
        sim.swipe(on: 101, dx: 0, dy: -200)
        XCTAssertEqual(sim.layout, .leftTwoThirds)
        XCTAssertTrue(sim.minimized.isEmpty)

        sim.swipe(on: 101, dx: 0, dy: -200)
        XCTAssertEqual(sim.layout, .fullscreen)
        XCTAssertEqual(sim.minimized, [102])
    }

    func testMinimizingOneOfTwoExpandsTheOther() {
        let sim = RuntimeMirror()
        sim.frames[101] = LayoutFrameResolver.frame(for: .leftThird, in: sim.screen)
        sim.frames[102] = LayoutFrameResolver.frame(for: .rightTwoThirds, in: sim.screen)
        sim.bundleIDs = [101: "com.example.a", 102: "com.example.b"]

        // Down from third → minimize 101; peer 102 should fill the screen.
        sim.swipe(on: 101, dx: 0, dy: 200)
        XCTAssertEqual(sim.minimized, [101])
        XCTAssertEqual(sim.frames[102], LayoutFrameResolver.frame(for: .fullscreen, in: sim.screen))
    }

    func testLeavingFullscreenRestoresMinimizedCompanionIntoThird() {
        let sim = RuntimeMirror()
        sim.frames[101] = LayoutFrameResolver.frame(for: .leftTwoThirds, in: sim.screen)
        sim.frames[102] = LayoutFrameResolver.frame(for: .rightThird, in: sim.screen)
        sim.bundleIDs = [101: "com.example.a", 102: "com.example.b"]

        // Enlarge to fullscreen → stash 102
        sim.swipe(on: 101, dx: 0, dy: -200)
        XCTAssertEqual(sim.layout, .fullscreen)
        XCTAssertEqual(sim.minimized, [102])

        // First down step: two-thirds, leftover is the ⅓ slot — restore 102 there.
        sim.swipe(on: 101, dx: 0, dy: 200)
        XCTAssertEqual(sim.layout, .leftTwoThirds)
        XCTAssertEqual(sim.unminimized, [102])
        XCTAssertEqual(
            sim.frames[102],
            LayoutFrameResolver.frame(for: .rightThird, in: sim.screen)
        )
        XCTAssertTrue(WindowRuntime.shouldRestoreMinimized(from: .fullscreen, to: .leftTwoThirds))
        XCTAssertFalse(WindowRuntime.shouldRestoreMinimized(from: .leftTwoThirds, to: .leftHalf))
    }
}
