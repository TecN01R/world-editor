import XCTest
@testable import WriterCore

final class WikiEntryTests: XCTestCase {
    private func page(_ title: String, _ text: String = "") -> Document {
        Document(title: title, paragraphs: [Paragraph(text: text)])
    }

    func testOtherPagesNamesAreLinkedOnceTheLongestFirst() {
        let road = page("The Salt Road"), salt = page("Salt"), mira = page("Mira"), al = page("Al")
        let text = "Mira walked the salt road for salt. Mira again. Al too."
        let pieces = WikiEntry.pieces(of: text, linking: [road, salt, mira, al], except: UUID())
        XCTAssertEqual(pieces.map(\.text).joined(), text)   // nothing lost or added
        // "salt" inside "the salt road" is the road's; the later one is Salt's; "Al" is too short.
        XCTAssertEqual(pieces.filter { $0.page != nil }.map(\.text), ["Mira", "the salt road", "salt"])
        XCTAssertEqual(pieces.filter { $0.page != nil }.map(\.page), [mira.id, road.id, salt.id])
    }

    func testAPageDoesntLinkToItself() {
        let mira = page("Mira")
        XCTAssertNil(WikiEntry.pieces(of: "Mira sings.", linking: [mira], except: mira.id).first { $0.page != nil })
    }

    func testMentionsQuoteTheSentenceThatNamesOrLinksThePage() {
        let mira = page("Mira", "She cuts salt.")
        let road = page("The Salt Road", "It runs east. Mira walks it every spring. It never ends.")
        let guild = Document(title: "The Brine Guild",
                             paragraphs: [Paragraph(text: "The old map hangs here. Her friend keeps it.",
                                                    links: [PageLink(location: 24, length: 10, page: mira.id)])])
        let home = FieldDefinition(name: "Friend", kind: .page)
        let type = PageType(name: "Character", fields: [home.id])
        var tamsin = Document(title: "Tamsin", paragraphs: [Paragraph(text: "A clockmaker.")], type: type.id)
        tamsin.values[home.id] = .page(mira.id)
        let mentions = WikiEntry.mentions(of: mira, in: [road, guild, tamsin, mira],
                                          schema: Schema(fields: [home], types: [type]))
        XCTAssertEqual(mentions, [
            WikiEntry.Mention(page: road.id, quote: "Mira walks it every spring."),
            WikiEntry.Mention(page: guild.id, quote: "Her friend keeps it."),
            WikiEntry.Mention(page: tamsin.id, quote: nil),   // a field holds it
        ])
    }

    func testASentenceRunsToItsOwnStop() {
        let text = "Dr. Vance came. She stayed"
        let at = text.range(of: "stayed")!.lowerBound
        XCTAssertEqual(WikiEntry.sentence(around: at, in: text), "She stayed")
        // A stop with no space after it, as in a number, ends nothing.
        let price = "It costs 3.5 crowns. Cheap!"
        XCTAssertEqual(WikiEntry.sentence(around: price.range(of: "crowns")!.lowerBound, in: price), "It costs 3.5 crowns.")
    }
}
