import XCTest
@testable import FocusLayout

final class FocusFitTests: XCTestCase {
    func testFindsTheLargestFittingSize() {
        XCTAssertEqual(FocusFit.largest { $0 <= 123 }, 123, accuracy: 0.5)
    }

    func testClampsToTheRange() {
        XCTAssertEqual(FocusFit.largest { _ in true }, FocusFit.maxSize)
        XCTAssertEqual(FocusFit.largest { _ in false }, FocusFit.minSize)
    }

    func testShrinksAtOnce() {
        XCTAssertEqual(FocusFit.settle(best: 90, current: 100, mayGrow: false), 90)
    }

    func testTypingOnlyGrowsForAClearWin() {
        XCTAssertEqual(FocusFit.settle(best: 102, current: 100, mayGrow: false), 100)
        XCTAssertEqual(FocusFit.settle(best: 106, current: 100, mayGrow: false), 106)
    }

    func testDeletingOrAFreshPageGrowsFreely() {
        XCTAssertEqual(FocusFit.settle(best: 102, current: 100, mayGrow: true), 102)
        XCTAssertEqual(FocusFit.settle(best: 102, current: 0, mayGrow: false), 102)
    }
}
