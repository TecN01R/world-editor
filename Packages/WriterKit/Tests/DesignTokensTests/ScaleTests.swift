import XCTest
@testable import DesignTokens

final class ScaleTests: XCTestCase {
    /// Every step of space, smallest first.
    static let spacing = [Spacing.tight, Spacing.gap, Spacing.row, Spacing.inset,
                          Spacing.margin, Spacing.block, Spacing.section]

    func testSpaceIsTheSpecificationsSevenSteps() {
        XCTAssertEqual(Self.spacing, [4, 8, 12, 16, 20, 24, 32])
    }

    func testSpaceClimbsInFours() {
        for (step, next) in zip(Self.spacing, Self.spacing.dropFirst()) { XCTAssertLessThan(step, next) }
        for step in Self.spacing { XCTAssertEqual(step.remainder(dividingBy: 4), 0, "\(step)") }
    }

    func testCornersGrowWithWhatTheyRound() {
        XCTAssertEqual([Radius.chip, Radius.card, Radius.bubble], [12, 16, 20])
    }

    func testFixedSizes() {
        XCTAssertEqual(Sizing.minimumTarget, 44)
        XCTAssertEqual(Sizing.dot, 8)
        XCTAssertEqual(Sizing.stroke, 1)
    }

    func testMotionSlowsAsMoreChanges() {
        XCTAssertEqual([Motion.quick, Motion.standard, Motion.arrival], [0.2, 0.3, 0.6])
        XCTAssertEqual(Motion.arrivalDelay, 0.3)
    }
}
