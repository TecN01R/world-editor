import XCTest
@testable import DesignTokens

final class PageMetricsTests: XCTestCase {
    private let topToBottom = [
        PageMetrics.aboveTitle, PageMetrics.titleToKind, PageMetrics.kindToFacts, PageMetrics.factRowSpacing,
        PageMetrics.factColumnSpacing, PageMetrics.aboveWriting, PageMetrics.beforeHeading,
        PageMetrics.afterHeading, PageMetrics.bottom,
    ]

    func testThePageIsTheSpecificationsNumbers() {
        XCTAssertEqual(topToBottom, [8, 8, 16, 12, 16, 24, 32, 12, 32])
    }

    func testEveryGapIsAStepOfSpace() {
        for gap in topToBottom { XCTAssertTrue(ScaleTests.spacing.contains(gap), "\(gap)") }
    }

    func testAHeadingSitsCloserToItsOwnSection() {
        XCTAssertLessThan(PageMetrics.afterHeading, PageMetrics.beforeHeading)
    }
}
