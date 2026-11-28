import XCTest
@testable import DesignTokens

final class PageMetricsTests: XCTestCase {
    /// The gaps down and across a page.
    private let gaps = [
        PageMetrics.aboveTitle, PageMetrics.titleToKind, PageMetrics.kindToFacts,
        PageMetrics.factColumnSpacing, PageMetrics.aboveWriting, PageMetrics.beforeHeading,
        PageMetrics.afterHeading, PageMetrics.bottom,
    ]

    func testThePageIsTheSpecificationsNumbers() {
        XCTAssertEqual(gaps, [8, 8, 16, 16, 24, 32, 12, 32])
    }

    func testEveryGapIsAStepOfSpace() {
        for gap in gaps { XCTAssertTrue(ScaleTests.spacing.contains(gap), "\(gap)") }
    }

    func testARowOfFactsIsATouchTargetTall() {
        // Edited, its name and its value are each tapped. The rows' height parts them, so
        // nothing goes between.
        XCTAssertEqual(PageMetrics.factRowMinHeight, Sizing.minimumTarget)
        XCTAssertEqual(PageMetrics.factRowSpacing, 0)
    }

    func testTheKindsLineIsATouchTargetWithTheGapsAroundIt() throws {
        // Edited, the kind is a menu, touched from the title down to the facts: nothing moves
        // to make room for a finger.
        let line = try XCTUnwrap(TextRole.ui.label.lineHeight)
        XCTAssertGreaterThanOrEqual(PageMetrics.titleToKind + line + PageMetrics.kindToFacts, Sizing.minimumTarget)
    }

    func testAHeadingSitsCloserToItsOwnSection() {
        XCTAssertLessThan(PageMetrics.afterHeading, PageMetrics.beforeHeading)
    }
}
