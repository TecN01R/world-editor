import XCTest
@testable import FocusLayout

final class FocusPagesTests: XCTestCase {
    func testARunOfBlankLinesIsOnePage() {
        // "Hey", "", "", "", "there"
        let starts = FocusPages.starts(empty: [false, true, true, true, false])
        XCTAssertEqual(starts, [0, 1, 4])
        XCTAssertEqual(FocusPages.page(of: 3, starts: starts), 1)   // inside the run
        XCTAssertEqual(FocusPages.page(of: 4, starts: starts), 2)
    }

    func testEveryWrittenParagraphIsItsOwnPage() {
        XCTAssertEqual(FocusPages.starts(empty: [false, false, true, false]), [0, 1, 2, 3])
    }

    func testBlankLinesAtTheEdges() {
        XCTAssertEqual(FocusPages.starts(empty: [true, true, false, true, true]), [0, 2, 3])
        XCTAssertEqual(FocusPages.starts(empty: [true]), [0])
        XCTAssertEqual(FocusPages.starts(empty: []), [])
    }
}
