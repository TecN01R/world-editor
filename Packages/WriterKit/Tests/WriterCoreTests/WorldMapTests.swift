import XCTest
@testable import WriterCore

final class WorldMapTests: XCTestCase {
    private let home = FieldDefinition(name: "Home", kind: .page)
    private lazy var character = PageType(name: "Character", fields: [home.id])
    private lazy var schema = Schema(fields: [home], types: [character])

    private func page(_ title: String, _ text: String = "", type: UUID? = nil) -> Document {
        Document(title: title, paragraphs: [Paragraph(text: text)], type: type)
    }

    func testLinesComeFromFieldsLinksAndNamesInTheWriting() {
        let hollow = page("Hollowmere", "A town of salt.")
        var mira = page("Mira", "She cuts salt.", type: character.id)
        mira.values[home.id] = .page(hollow.id)
        let road = page("The Salt Road", "Mira walks it every spring.")
        let guild = Document(title: "The Brine Guild",
                             paragraphs: [Paragraph(text: "Its hall", links: [PageLink(location: 0, length: 3, page: road.id)])])
        let map = WorldMap(pages: [guild, road, mira, hollow], schema: schema)
        XCTAssertEqual(Set(map.lines), [[mira.id, hollow.id], [road.id, mira.id], [guild.id, road.id]])
    }

    func testANameCountsOnlyAsWholeWords() {
        XCTAssertTrue(WorldMap.names("Mira", in: "Then Mira's road turned."))
        XCTAssertTrue(WorldMap.names("the salt road", in: "She took The Salt Road."))
        XCTAssertFalse(WorldMap.names("Mira", in: "The Miradel hills."))
        XCTAssertFalse(WorldMap.names("Al", in: "Al was there."))   // too short to tell from other words
    }

    func testARumourIsANameWithNothingKnownYet() {
        let wren = page("Wren")
        let mira = page("Mira", "She cuts salt.\nShe sings.")
        let cards = WorldMap(pages: [wren, mira], schema: schema).cards
        XCTAssertEqual(cards.first { $0.id == wren.id }?.isRumour, true)
        XCTAssertEqual(cards.first { $0.id == mira.id }?.known, 1)   // one paragraph
    }

    func testCardsKeepTheirPlacesAndNewOnesGoBesideWhatTheyreLinkedTo() {
        let hollow = page("Hollowmere", "A town.")
        let far = page("Far Isle", "An island.")
        let first = WorldMap(pages: [far, hollow], schema: schema)
        XCTAssertNotEqual(first.places[hollow.id], first.places[far.id])

        let mira = page("Mira", "She lives in Hollowmere.")
        let second = WorldMap(pages: [mira, far, hollow], schema: schema, placed: first.places)
        XCTAssertEqual(second.places[hollow.id], first.places[hollow.id])
        XCTAssertEqual(second.places[far.id], first.places[far.id])
        let h = first.places[hollow.id]!, m = second.places[mira.id]!
        XCTAssertLessThanOrEqual(max(abs(m.x - h.x), abs(m.y - h.y)), 1)   // right beside Hollowmere
        XCTAssertEqual(Set(second.places.values).count, 3)   // no two in one place
    }

    func testDeletedAndBlankPagesArentOnTheMap() {
        var gone = page("Gone", "Was here.")
        gone.deleted = Date()
        let map = WorldMap(pages: [gone, Document(), page("Kept", "Here.")], schema: schema)
        XCTAssertEqual(map.cards.map(\.title), ["Kept"])
    }

    func testTheNearestFreePlace() {
        let taken: Set = [WorldMap.Place(x: 0, y: 0), WorldMap.Place(x: 1, y: 0)]
        let place = WorldMap.free(near: WorldMap.Place(x: 0, y: 0), taken: taken)
        XCTAssertFalse(taken.contains(place))
        XCTAssertLessThanOrEqual(max(abs(place.x), abs(place.y)), 1)
    }
}
