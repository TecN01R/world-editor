import XCTest
@testable import DesignTokens

final class ContrastTests: XCTestCase {
    private let surfaces: [Tone] = [.surface.base, .surface.raised, .surface.raised2]

    /// How strongly `text` stands out on `background`: Lc without its sign, which here only says
    /// that the text is the lighter of the two.
    private func contrast(of text: Tone, on background: Tone) -> Double {
        Contrast.lc(text: text, on: background).magnitude
    }

    func testAPCAMatchesItsPublishedValues() {
        // APCA-W3 0.0.98G-4g's own test values: text, background, Lc.
        let published: [(text: UInt32, background: UInt32, lc: Double)] = [
            (0x888888, 0xFFFFFF, 63.056469930209424),
            (0xFFFFFF, 0x888888, -68.54146436644962),
            (0x000000, 0xAAAAAA, 58.146262578561334),
            (0xAAAAAA, 0x000000, -56.24113336839742),
            (0x112233, 0xDDEEFF, 91.66830811481631),
            (0xDDEEFF, 0x112233, -93.06770049484275),
        ]
        for (text, background, lc) in published {
            let text = Tone(hex: text), background = Tone(hex: background)
            XCTAssertEqual(Contrast.lc(text: text, on: background), lc, accuracy: 1e-9, "\(text) on \(background)")
        }
    }

    func testTonesTooCloseToTellApartHaveNoContrast() {
        XCTAssertEqual(Contrast.lc(text: .ink, on: .ink), 0)
        // Under APCA's low clip, whichever is the text.
        XCTAssertEqual(Contrast.lc(text: Tone(hex: 0x112233), on: Tone(hex: 0x223344)), 0)
        XCTAssertEqual(Contrast.lc(text: Tone(hex: 0x223344), on: Tone(hex: 0x112233)), 0)
    }

    func testASeeThroughToneIsMeasuredAsDrawn() {
        XCTAssertEqual(Contrast.lc(text: .faint, on: .surface.base),
                       Contrast.lc(text: Tone(hex: 0x98989F), on: .surface.base))
    }

    func testTheAuthorsWordsReadOnEverySurface() {
        for surface in surfaces {
            XCTAssertGreaterThanOrEqual(contrast(of: .ink, on: surface), 75, "on \(surface)")
        }
    }

    func testTheAppsSmallTextReadsOnEverySurface() {
        for surface in surfaces {
            XCTAssertGreaterThanOrEqual(contrast(of: .ink2, on: surface), 60, "on \(surface)")
        }
    }

    func testFaintIsTooDimForSmallText() {
        // Which is why it is kept to symbols, placeholders and text from 24 pt.
        XCTAssertLessThan(contrast(of: .faint, on: .surface.base), 60)
    }

    func testIncreaseContrastRaisesBothInks() {
        for surface in surfaces {
            XCTAssertGreaterThan(contrast(of: .increasedContrast.ink, on: surface),
                                 contrast(of: .ink, on: surface), "on \(surface)")
            XCTAssertGreaterThan(contrast(of: .increasedContrast.ink2, on: surface),
                                 contrast(of: .ink2, on: surface), "on \(surface)")
        }
    }

    func testTheTonesKeepTheirOrderOnEverySurface() {
        for surface in surfaces {
            let strongestFirst = [Tone.emphasis, .ink, .ink2, .faint].map { contrast(of: $0, on: surface) }
            for (stronger, weaker) in zip(strongestFirst, strongestFirst.dropFirst()) {
                XCTAssertGreaterThan(stronger, weaker, "on \(surface)")
            }
        }
    }

    func testWCAGRatioForReference() {
        let white = Tone(hex: 0xFFFFFF), black = Tone(hex: 0x000000)
        XCTAssertEqual(Contrast.wcagRatio(text: black, on: white), 21, accuracy: 1e-9)
        XCTAssertEqual(Contrast.wcagRatio(text: white, on: black), 21, accuracy: 1e-9)   // the same either way round
        XCTAssertEqual(Contrast.wcagRatio(text: white, on: white), 1)
        // The grey WCAG's AA level is known by: 4.54 to 1 on white.
        XCTAssertEqual(Contrast.wcagRatio(text: Tone(hex: 0x767676), on: white), 4.54, accuracy: 0.005)
    }
}
