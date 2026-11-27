import XCTest
@testable import DesignTokens

final class ReadingTests: XCTestCase {
    /// The Duo's widths in points, folded and unfolded, and the page's type size.
    private let folded = 382.0, unfolded = 669.0, body = 19.0

    func testTheColumnIsTheWidthLessItsMarginsUpToTheCap() {
        XCTAssertEqual(Reading.column(width: folded, fontSize: body, margin: 20), 342)
        XCTAssertEqual(Reading.column(width: unfolded, fontSize: body, margin: 20), 627)   // 33 em, not 629
        XCTAssertEqual(Reading.column(width: folded, fontSize: body), 342)                 // the one margin
        XCTAssertEqual(Reading.column(width: 30, fontSize: body, margin: 20), 0)           // never less than nothing
    }

    func testTheMeasureIsTheColumnInEm() {
        XCTAssertEqual(Reading.measure(columnWidth: 342, fontSize: body), 18)
        XCTAssertEqual(Reading.measure(columnWidth: 627, fontSize: body), Reading.measureCap)
        XCTAssertEqual(Reading.charactersPerLine(measureEm: 18), 36)
        XCTAssertEqual(Reading.charactersPerLine(measureEm: Reading.measureCap), 66)
    }

    func testLeadingAndHyphenationGoByTheMeasure() {
        let byMeasure: [(measure: Double, leading: Double, hyphenation: Double)] = [
            (6, 1.30, 0.9), (12, 1.30, 0.9),                       // short: very large text
            (14, 1.35, 0.75),                                      // easing between
            (16, 1.40, 0.6), (18, 1.40, 0.6), (24, 1.40, 0.6),     // middling: folded
            (26, 1.435, 0.5),                                      // easing between
            (28, 1.47, 0.4), (33, 1.47, 0.4),                      // long: unfolded
        ]
        for (measure, leading, hyphenation) in byMeasure {
            XCTAssertEqual(Reading.leading(measureEm: measure), leading, accuracy: 1e-9, "\(measure) em")
            XCTAssertEqual(Reading.hyphenation(measureEm: measure), hyphenation, accuracy: 1e-9, "\(measure) em")
        }
    }

    /// A step in the leading made 24.5 pt type set shorter lines than 24.4 pt in the same column.
    func testALineNeverGetsShorterAsTheTypeGrows() {
        for column in [342.0, 627, 880] {
            let sizes = stride(from: 12.0, through: 60, by: 0.1)
            for (smaller, larger) in zip(sizes, sizes.dropFirst()) {
                XCTAssertLessThanOrEqual(Reading.lineHeight(fontSize: smaller, columnWidth: column, displayScale: 0),
                                         Reading.lineHeight(fontSize: larger, columnWidth: column, displayScale: 0) + 1e-9,
                                         "\(larger) pt in \(column) pt")
            }
        }
    }

    func testLeadingNeverFallsAndHyphenationNeverRisesAsTheMeasureGrows() {
        let measures = stride(from: 1.0, through: 60, by: 0.25)
        for (shorter, longer) in zip(measures, measures.dropFirst()) {
            XCTAssertLessThanOrEqual(Reading.leading(measureEm: shorter), Reading.leading(measureEm: longer),
                                     "\(longer) em")
            XCTAssertGreaterThanOrEqual(Reading.hyphenation(measureEm: shorter), Reading.hyphenation(measureEm: longer),
                                        "\(longer) em")
        }
    }

    func testLineHeightIsTheLeadingOnAWholePixel() {
        // Folded, 18 em: 19 × 1.40 = 26.6, which is 80 pixels at 3x, 26.67 pt.
        XCTAssertEqual(Reading.lineHeight(fontSize: body, columnWidth: 342, displayScale: 3), 80.0 / 3, accuracy: 1e-9)
        // Unfolded, 33 em: 19 × 1.47 = 27.93, which is 84 pixels, 28 pt.
        XCTAssertEqual(Reading.lineHeight(fontSize: body, columnWidth: 627, displayScale: 3), 28)
        XCTAssertEqual(Reading.lineHeight(fontSize: body, columnWidth: 342, displayScale: 2), 26.5)
        for size in stride(from: 12.0, through: 60, by: 0.5) {
            for scale in [1.0, 2, 3] {
                let pixels = Reading.lineHeight(fontSize: size, columnWidth: 342, displayScale: scale) * scale
                XCTAssertEqual(pixels, pixels.rounded(), accuracy: 1e-9, "\(size) pt at \(scale)x")
            }
        }
    }

    func testAnUnknownDisplayScaleLeavesTheLineHeightUnrounded() {
        XCTAssertEqual(Reading.lineHeight(fontSize: body, columnWidth: 342, displayScale: 0), 19 * 1.40, accuracy: 1e-9)
    }

    func testAnAccessibilitySizeIsAShortMeasure() {
        let size = 53.0
        let column = Reading.column(width: folded, fontSize: size, margin: 20)
        let measure = Reading.measure(columnWidth: column, fontSize: size)
        XCTAssertLessThan(measure, 12)
        XCTAssertEqual(Reading.leading(measureEm: measure), 1.30)
        XCTAssertEqual(Reading.hyphenation(measureEm: measure), 0.9)
    }

    func testTheBaselineOffsetCentresTheTextInItsLine() {
        XCTAssertEqual(Reading.baselineOffset(lineHeight: 28, fontLineHeight: 23), 2.5)
        XCTAssertEqual(Reading.baselineOffset(lineHeight: 22, fontLineHeight: 22), 0)
    }

    func testListItemsSitCloserThanParagraphs() {
        XCTAssertEqual(Reading.paragraphSpacing, 0.5)
        XCTAssertEqual(Reading.listItemSpacing, 0.25)
        XCTAssertEqual(Reading.listEndSpacing, 0.5)
    }
}
