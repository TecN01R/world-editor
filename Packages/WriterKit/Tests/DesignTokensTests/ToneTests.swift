import XCTest
@testable import DesignTokens

final class ToneTests: XCTestCase {
    func testHexIsHowTheSpecificationWritesATone() {
        let base = Tone(hex: 0x1C1C1E)
        XCTAssertEqual([base.red, base.green, base.blue], [28, 28, 30])
        XCTAssertEqual(base.alpha, 1)
        XCTAssertEqual(base.hex, "#1C1C1E")
        XCTAssertEqual(Tone(hex: 0x000A0F).hex, "#000A0F")                                  // leading zeros stay
        XCTAssertEqual(Tone(red: 255, green: 0, blue: 128, alpha: 0.5).hex, "#FF008080")   // see-through: alpha last
        XCTAssertEqual("\(Tone.ink)", "#E6E6E6")
    }

    func testTheTokensAreTheSpecificationsValues() {
        let tokens: [(Tone, String)] = [
            (.surface.base, "#1C1C1E"), (.surface.raised, "#2C2C2E"), (.surface.raised2, "#3A3A3C"),
            (.ink, "#E6E6E6"), (.ink2, "#C2C2C7"), (.emphasis, "#FFFFFF"),
            (.faint, "#EBEBF599"),                                  // iOS's secondary label, at 60%
            (.rule, "#E6E6E633"), (.ruleStrong, "#E6E6E659"),       // ink at 20% and 35%
            (.increasedContrast.ink, "#FFFFFF"), (.increasedContrast.ink2, "#DEDEE3"),
        ]
        for (tone, hex) in tokens { XCTAssertEqual(tone.hex, hex) }
        XCTAssertEqual(Tone.faint.alpha, 0.6)
        XCTAssertEqual(Tone.rule, Tone.ink.opacity(0.2))
        XCTAssertEqual(Tone.ruleStrong, Tone.ink.opacity(0.35))
    }

    func testASeeThroughToneMixesWithItsSurface() {
        XCTAssertEqual(Tone.faint.over(.surface.base).hex, "#98989F")
        XCTAssertEqual(Tone.rule.over(.surface.base).hex, "#444446")
        XCTAssertEqual(Tone.ink.over(.surface.raised), .ink)                           // solid: hides its surface
        XCTAssertEqual(Tone.ink.opacity(0).over(.surface.raised), .surface.raised)     // clear: shows it
    }

    func testAlphaStaysBetweenClearAndSolid() {
        XCTAssertEqual(Tone(red: 0, green: 0, blue: 0, alpha: 1.5).alpha, 1)
        XCTAssertEqual(Tone(red: 0, green: 0, blue: 0, alpha: -1).alpha, 0)
        XCTAssertEqual(Tone(red: 0, green: 0, blue: 0, alpha: .nan).alpha, 0)
        XCTAssertEqual(Tone.ink.opacity(0.5).opacity(0.5).alpha, 0.25)   // each lets more through
    }
}
