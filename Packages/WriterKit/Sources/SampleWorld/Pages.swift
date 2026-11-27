import Foundation
import WriterCore

extension SampleWorld {
    /// The four kinds of page and their fields, with a field of every kind among them.
    /// Character's first five are the app's first sample's. Character's Teacher, then Group and
    /// its two fields, were made by filing in today's conversation, so they come last, in that
    /// order, and are text or a page, as filing makes them.
    static let schema: Schema = {
        let kind = ID.Kind.self, field = ID.Field.self
        return Schema(fields: [
            FieldDefinition(id: field.species, name: "Species", kind: .choice, options: ["Human", "Elf", "Selkie"]),
            FieldDefinition(id: field.age, name: "Age", kind: .number),
            FieldDefinition(id: field.home, name: "Home", kind: .page, pageType: kind.place),
            FieldDefinition(id: field.firstSeen, name: "First seen", kind: .date),
            FieldDefinition(id: field.keepsASecret, name: "Keeps a secret", kind: .toggle),
            FieldDefinition(id: field.knownFor, name: "Known for", kind: .text),
            FieldDefinition(id: field.gettingThere, name: "Getting there", kind: .longText),
            FieldDefinition(id: field.number, name: "Number", kind: .number),
            FieldDefinition(id: field.pointOfView, name: "Point of view", kind: .page, pageType: kind.character),
            FieldDefinition(id: field.status, name: "Status", kind: .choice, options: ["Idea", "Draft", "Revised"]),
            FieldDefinition(id: field.teacher, name: "Teacher", kind: .page),
            FieldDefinition(id: field.ledBy, name: "Led by", kind: .page, pageType: kind.character),
            FieldDefinition(id: field.members, name: "Members", kind: .text),
        ], types: [
            PageType(id: kind.character, name: "Character",
                     fields: [field.species, field.age, field.home, field.firstSeen, field.keepsASecret, field.teacher]),
            PageType(id: kind.place, name: "Place", fields: [field.knownFor, field.gettingThere]),
            PageType(id: kind.chapter, name: "Chapter", fields: [field.number, field.pointOfView, field.status]),
            PageType(id: kind.group, name: "Group", fields: [field.ledBy, field.members]),
        ])
    }()

    /// Every page that isn't deleted, in no order.
    static func pages(_ times: Times) -> [Document] {
        [harbourNotes(times), mara(times), oldTamsin(times), jory(times), breakwater(times), lighthouse(times),
         ironAbbey(times), mapOfTheCoast(times), clockmakersGuild(times), nightTheBellRang(times), chapterTwo(times),
         untitled(times), masterCorwen(times)]
    }

    /// Every kind of formatting on one plain page: bold, italic, a bulleted and a numbered
    /// list, and two `@` links (the app's first sample page, with a line more).
    static func harbourNotes(_ times: Times) -> Document {
        page(ID.harbourNotes, "Harbour Notes", modified: times.ago(hours: 6), [
            Line("The tide came in faster than the charts promised.").italic("faster"),
            Line("Lantern oil", .bullet),
            Line("Rope, two coils", .bullet),
            Line("Clock oil for Old Tamsin", .bullet).link("Old Tamsin", to: ID.oldTamsin),
            Line("Check the north mooring", .numbered).bold("north"),
            Line("Ask Mara about the bell", .numbered).link("Mara", to: ID.mara),
        ])
    }

    /// A Character with the five fields of the app's first sample filled, one of each kind.
    /// Today's conversation put a sentence on at the end of her third paragraph, and another
    /// as a paragraph of its own.
    static func mara(_ times: Times) -> Document {
        page(ID.mara, "Mara", type: ID.Kind.character, values: [
            ID.Field.species: .text("Selkie"),
            ID.Field.age: .number(61),
            ID.Field.home: .page(ID.lighthouse),
            ID.Field.firstSeen: .date(Self.day(20_717)),   // 21 September 2026
            ID.Field.keepsASecret: .toggle(true),
        ], modified: times.ago(days: 2), [
            Line("Keeps the lighthouse."),
            Line("She came out to the rock at nineteen to carry oil for the old keeper, and when he died the harbour "
                 + "let her stay. Nobody asked where she had come from before that."),
            Line("She trims the lamp at dusk and reads the weather off the gulls. The clockwork that turns the lamp is "
                 + "Old Tamsin's, and Mara is the only one trusted to wind it.")
                .adding("Mara winds the clockwork every four hours, all night.", by: ID.placement(6)),
            Line("Her secret is a sealskin, folded in the oil store under the spare wicks. She has not worn it since "
                 + "she took the keys."),
            Line("Mara was up in the lamp room and heard it through the storm.").placed(by: ID.placement(1)),
        ])
    }

    /// A Character whose page today's conversation renamed (it was "Tamsin") and gave two
    /// paragraphs and a teacher.
    static func oldTamsin(_ times: Times) -> Document {
        page(ID.oldTamsin, "Old Tamsin", type: ID.Kind.character, values: [
            ID.Field.species: .text("Human"),
            ID.Field.age: .number(74),
            ID.Field.home: .page(ID.breakwater),
            ID.Field.keepsASecret: .toggle(false),
            ID.Field.teacher: .page(ID.masterCorwen),
        ], modified: times.ago(days: 6), [
            Line("A clockmaker, the last on the coast who can cut a wheel by eye."),
            Line("Her shop is on Net Street in Breakwater, under the sign of the three hands. Every clock in the "
                 + "harbour has been through it at least once, and she remembers what was wrong with each."),
            Line("Old Tamsin built the clockwork that turns the lamp and she has never once been out to see it run.")
                .placed(by: ID.placement(3)),
            Line("She learned the trade from Master Corwen.").placed(by: ID.placement(4)),
        ])
    }

    /// A Character with fields filled and nothing written.
    static func jory(_ times: Times) -> Document {
        page(ID.jory, "Jory", type: ID.Kind.character, values: [
            ID.Field.species: .text("Human"),
            ID.Field.age: .number(13),
            ID.Field.home: .page(ID.breakwater),
        ], modified: times.ago(days: 9), [Line("")])
    }

    /// A Place, with an `@` link to the guild (which made the guild's page, weeks before
    /// anything was known of it).
    static func breakwater(_ times: Times) -> Document {
        page(ID.breakwater, "Breakwater", type: ID.Kind.place, values: [
            ID.Field.knownFor: .text("Herring, and a clock that has never been wrong"),
            ID.Field.gettingThere: .text("The coast road ends here. A cart comes from the market town on Mondays and "
                                         + "Thursdays, and nothing comes at all when the river is up."),
        ], modified: times.ago(days: 16), [
            Line("A harbour town at the end of the coast road. Seven hundred people, forty boats, one clock."),
            Line("The Clockmakers' Guild winds the town clock every morning at six, and the boats go out by it. The "
                 + "harbour wall took eleven summers to build and has been mended every summer since.")
                .link("The Clockmakers' Guild", to: ID.clockmakersGuild),
            Line("From the quay you can see the lighthouse on a clear day and hear its bell on a foul one. The black "
                 + "shape on the headland to the north is the Iron Abbey."),
        ])
    }

    /// A Place. Today's conversation put a sentence on at the end of its paragraph about the
    /// bell, and the next as a paragraph of its own: one placement, both ways.
    static func lighthouse(_ times: Times) -> Document {
        page(ID.lighthouse, "The Lighthouse", type: ID.Kind.place, values: [
            ID.Field.knownFor: .text("Its bell"),
            ID.Field.gettingThere: .text("By boat from the harbour steps, a quarter of a mile. At the two lowest tides "
                                         + "of the month the causeway shows, and it can be walked in twenty minutes by "
                                         + "anyone who doesn't stop to look at things."),
        ], modified: times.ago(days: 4), [
            Line("Stands on Anvil Rock, a quarter of a mile off the harbour wall, where the charts stop being sure of "
                 + "themselves."),
            Line("Mara keeps it. The lamp turns once every thirty seconds on a clockwork Old Tamsin built."),
            Line("The bell hangs under the gallery on the seaward side. It was cast at the Iron Abbey and is rung in "
                 + "fog, by hand, with a rope that comes down through the floor of the lamp room.")
                .adding("The lighthouse bell rang by itself the night the Petrel went down.", by: ID.placement(2)),
            Line("Nobody pulled the rope.").placed(by: ID.placement(2)),
        ])
    }

    /// A Place whose writing names the lighthouse, the guild and Old Tamsin, with no `@` link.
    static func ironAbbey(_ times: Times) -> Document {
        page(ID.ironAbbey, "Iron Abbey", type: ID.Kind.place, values: [
            ID.Field.knownFor: .text("Bells"),
            ID.Field.gettingThere: .text("Up the cliff path from the north cove: two hundred and twelve steps, which "
                                         + "the brothers count aloud."),
        ], modified: times.ago(days: 12), [
            Line("A monastery on the headland above the north cove, built of the same black stone as the cliff."),
            Line("The brothers cast bells. Every harbour bell on this coast came out of their foundry, and the "
                 + "lighthouse bell is the largest they ever poured."),
            Line("They keep the hours by a water clock and will not have one of the Clockmakers' Guild's clocks "
                 + "inside the walls. Old Tamsin has never forgiven them for it."),
        ])
    }

    /// A Place, with an `@` link. Yesterday's conversation put a sentence on at the end of its
    /// paragraph about the south cove.
    static func mapOfTheCoast(_ times: Times) -> Document {
        page(ID.mapOfTheCoast, "Map of the Coast", type: ID.Kind.place, values: [
            ID.Field.knownFor: .text("Being wrong about the north cove"),
            ID.Field.gettingThere: .text("It hangs in the harbourmaster's office, behind the door, where the damp "
                                         + "can't reach it."),
        ], modified: times.ago(days: 21), [
            Line("Three coves, one road."),
            Line("North cove: deep water, no beach, and the cliff path up to the Iron Abbey."),
            Line("Middle cove: Breakwater, its harbour and its wall."),
            Line("South cove: shingle, seals, and nobody who will say why the boats don't land there.")
                .adding("The seals in the south cove are why the boats won't land there.", by: ID.placement(8)),
            Line("The Lighthouse sits off the point between the middle cove and the south, on Anvil Rock.")
                .link("The Lighthouse", to: ID.lighthouse),
        ])
    }

    /// A Group, the kind today's conversation made. Until today it was a name and nothing
    /// else; its kind, both its fields and all its writing are from filing: the description it
    /// was given, then the author's sentences, of which the later corrects the earlier.
    static func clockmakersGuild(_ times: Times) -> Document {
        page(ID.clockmakersGuild, "The Clockmakers' Guild", type: ID.Kind.group, values: [
            ID.Field.ledBy: .page(ID.oldTamsin),
            ID.Field.members: .text("seven"),
        ], modified: times.ago(days: 24), [
            Line("The oldest guild on the coast"),
            Line("Old Tamsin leads it. There are nine of them.").placed(by: ID.placement(5)),
            Line("There are only seven in the Clockmakers' Guild now. Two died the winter the Petrel was lost.")
                .placed(by: ID.placement(7)),
        ])
    }

    /// The long Chapter, to judge reading over a long page (`chapter`).
    static func nightTheBellRang(_ times: Times) -> Document {
        page(ID.nightTheBellRang, "The Night the Bell Rang", type: ID.Kind.chapter, values: [
            ID.Field.number: .number(1),
            ID.Field.pointOfView: .page(ID.mara),
            ID.Field.status: .text("Draft"),
        ], modified: times.ago(days: 1, hours: 3), chapter.map { Line($0) })
    }

    /// A Chapter whose title runs to 94 characters, to see it wrap; written on, with none of
    /// its fields filled.
    static func chapterTwo(_ times: Times) -> Document {
        page(ID.chapterTwo, "Chapter two, in which Old Tamsin is rowed out to the lighthouse against every promise she made",
             type: ID.Kind.chapter, modified: times.ago(days: 7), [
                Line("Jory rows. She keeps her eyes shut the whole way out and counts the strokes."),
                Line("What she does when she sees the clockwork running, I don't know yet."),
             ])
    }

    /// A page with no title: one paragraph, longer than the 80 characters of it that name the
    /// page in lists.
    static func untitled(_ times: Times) -> Document {
        page(ID.untitled, "", modified: times.ago(days: 3), [
            Line("What if the bell was never meant for the boats? Something to try: it only ever rings for someone the "
                 + "sea is about to keep."),
        ])
    }

    /// A rumour: a name and nothing else. Filing made it in today's conversation, when the
    /// author named Old Tamsin's teacher, and it's dated then, having never been opened.
    static func masterCorwen(_ times: Times) -> Document {
        page(ID.masterCorwen, "Master Corwen", modified: filedToday(times, turn: 2), [Line("")])
    }

    /// The page in Recently Deleted, for 25 more days. Filing made it in last month's
    /// conversation, with the author's words for him as its first line; the author wrote
    /// under them, then deleted it.
    static func captainHale(_ times: Times) -> Document {
        var hale = page(ID.captainHale, "Captain Hale", type: ID.Kind.character, modified: times.ago(days: 12, hours: 5), [
            Line("The harbourmaster who signed the Petrel out that night"),
            Line("Probably not needed. The ledger can say everything he would."),
        ])
        hale.deleted = times.ago(days: 5)
        return hale
    }

    /// A date for a field: noon, Greenwich time, `days` after 1 January 1970, so it's the
    /// same day almost wherever a simulator's clock is set. A field's date is what the author
    /// chose, so it isn't counted back from `now`.
    private static func day(_ days: Double) -> Date {
        Date(timeIntervalSince1970: (days + 0.5) * 86_400)
    }

    /// A page of the sample, its paragraphs given ids of their own from the page's.
    private static func page(_ id: UUID, _ title: String, type: UUID? = nil, values: [UUID: FieldValue] = [:],
                             modified: Date, _ lines: [Line]) -> Document {
        let paragraphs = lines.enumerated().map { index, line in
            Paragraph(id: ID.paragraph(index, of: id), text: line.text, kind: line.kind, runs: line.runs,
                      links: line.links, placed: line.placed)
        }
        return Document(id: id, title: title, paragraphs: paragraphs, modified: modified, type: type, values: values)
    }
}

/// A paragraph as the sample writes one down: its words, and which of them are bold, italic,
/// a link to a page or placed by filing, each named by the words themselves, so no offsets
/// are counted by hand.
private struct Line {
    var text: String
    var kind: ParagraphKind
    var runs: [StyleRun] = []
    var links: [PageLink] = []
    var placed: [PlacedRun] = []

    init(_ text: String, _ kind: ParagraphKind = .body) {
        self.text = text
        self.kind = kind
    }

    func bold(_ words: String) -> Line { styled(words, .bold) }
    func italic(_ words: String) -> Line { styled(words, .italic) }

    /// An `@` link to `page`: `words` are its title, as the app keeps a link's text.
    func link(_ words: String, to page: UUID) -> Line {
        var line = self
        let (location, length) = span(words)
        line.links.append(PageLink(location: location, length: length, page: page))
        return line
    }

    /// The whole paragraph was put there by filing (`placement`), as `Document.place` leaves one.
    func placed(by placement: UUID) -> Line {
        var line = self
        line.placed.append(PlacedRun(location: 0, length: text.utf16.count, placement: placement))
        return line
    }

    /// The author's paragraph with `words` put on at its end by filing (`placement`), after a
    /// space, as `Document.append` leaves it.
    func adding(_ words: String, by placement: UUID) -> Line {
        var line = self
        let start = text.utf16.count + 1
        line.text += " " + words
        line.placed.append(PlacedRun(location: start, length: words.utf16.count, placement: placement))
        return line
    }

    private func styled(_ words: String, _ style: InlineStyle) -> Line {
        var line = self
        let (location, length) = span(words)
        line.runs.append(StyleRun(location: location, length: length, style: style))
        return line
    }

    /// Where `words` first are in the text, in UTF-16 units (nowhere, if they aren't in it).
    private func span(_ words: String) -> (location: Int, length: Int) {
        guard let range = text.range(of: words) else { return (0, 0) }
        return (text.utf16.distance(from: text.startIndex, to: range.lowerBound), words.utf16.count)
    }
}
