import XCTest
@testable import FocusLayout

/// Monospaced fake: every character is 0.5em wide, wrapping on spaces.
struct FakeMeasurer: TextMeasurer {
    func measure(_ text: String, fontSize: Double, width: Double) -> TextMeasurement {
        let charW = 0.5 * fontSize
        var lines = 1, lineLen = 0.0, widest = 0.0, fits = true
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            let w = Double(word.count) * charW
            if w > width { fits = false }
            let needed = lineLen == 0 ? w : lineLen + charW + w
            if needed > width && lineLen > 0 { lines += 1; lineLen = w } else { lineLen = needed }
            widest = max(widest, lineLen)
        }
        let lh = FitEngine.lineHeight(for: fontSize) * fontSize
        return TextMeasurement(width: widest, height: Double(lines) * lh, lineCount: lines, fitsWithoutBreakingWords: fits)
    }
    func ink(_ text: String) -> InkMetrics {
        InkMetrics(ascent: 0.92, descent: 0.26, inkAscent: 0.72, inkDescent: text.contains("g") ? 0.22 : 0)
    }
}

final class FitEngineTests: XCTestCase {
    let engine = FitEngine()
    let area = (width: 300.0, height: 400.0)

    func testFirstCharacterIsEnormous() {
        let r = engine.fit("", in: area, measurer: FakeMeasurer())
        XCTAssertGreaterThan(r.fontSize, 200)
        XCTAssertFalse(r.overflows)
    }

    func testMoreTextIsSmaller() {
        let a = engine.fit("Hi", in: area, measurer: FakeMeasurer())
        let b = engine.fit("Hi this is a much longer sentence that has to wrap", in: area, measurer: FakeMeasurer())
        XCTAssertGreaterThan(a.fontSize, b.fontSize)
    }

    func testResultAlwaysFits() {
        for text in ["g", "Hi. This", "a b c d e f g h i j k l m n o p", String(repeating: "word ", count: 80)] {
            let r = engine.fit(text, in: area, measurer: FakeMeasurer())
            if !r.overflows {
                XCTAssertLessThanOrEqual(r.blockSize.height, area.height + 0.5, text)
                XCTAssertLessThanOrEqual(r.blockSize.width, area.width + 0.5, text)
            }
        }
    }

    func testDoesNotGrowForSmallGainsWhileTyping() {
        let m = FakeMeasurer()
        let held = engine.fit("Hello there friend", in: area, measurer: m).fontSize
        let next = engine.fit("Hello there friend!", in: area, measurer: m, held: held, allowGrow: false)
        XCTAssertLessThanOrEqual(next.fontSize, held * 1.045)
    }

    func testStepsAreDiscreteAndIncreasing() {
        XCTAssertEqual(FitEngine.steps.first, FitEngine.minSize)
        XCTAssertTrue(zip(FitEngine.steps, FitEngine.steps.dropFirst()).allSatisfy { $0 < $1 })
    }

    func testCentringStaysClearOfKeyboard() {
        let top = FitEngine.centredTop(blockHeight: 200, areaTop: 0, areaBottom: 400)
        XCTAssertEqual(top, 100)
        let tall = FitEngine.centredTop(blockHeight: 395, areaTop: 0, areaBottom: 400, margin: 8)
        XCTAssertLessThanOrEqual(tall + 395, 392)
    }
}
