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
}
