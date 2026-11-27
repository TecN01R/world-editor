import Foundation
import WriterCore

/// A made-up world, the same every time, for scenes, screenshots and tests. Never a real author's.
///
/// It's Breakwater, a small harbour town: its lighthouse and the woman who keeps it, a
/// clockmaker and her guild, an abbey that casts bells. About a dozen pages of every sort the
/// app shows (written and bare, typed and plain, a long chapter, a name and nothing more) and
/// four conversations with the companion, of which today's filed something of every kind into
/// those pages.
public enum SampleWorld {
    /// A world as the app holds one: what its stores keep, and what it keeps beside them.
    public struct Contents: Equatable, Sendable {
        public var world: World
        public var schema: Schema
        /// As a library keeps them: most recently edited first.
        public var pages: [Document]
        /// The pages in Recently Deleted (`Document.deleted` set), newest first.
        public var deleted: [Document]
        /// The world's own conversations (`aboutWorld`), newest first.
        public var conversations: [Conversation]
        /// Pages filing made or added to that the author hasn't opened since. The app keeps
        /// these in its settings, not in a store, so `write` leaves them to the app.
        public var unseen: Set<UUID>
        /// The conversation the app opens again; nil when nothing has been said yet. Kept in
        /// the app's settings too.
        public var lastConversation: UUID?
        /// The author's standing instructions for the companion: what its replies say they
        /// added. Kept in the app's settings as well, for every world at once.
        public var instructions: String?
    }

    /// The sample world. Everything in it is dated back from `now`, so "yesterday" stays
    /// yesterday in every screenshot; nothing else differs from one call to the next.
    public static func contents(now: Date) -> Contents {
        let times = Times(now: now)
        return Contents(world: World(id: ID.world, name: "Breakwater"),
                        schema: schema,
                        pages: pages(times).sorted { $0.modified > $1.modified },
                        deleted: [captainHale(times)],
                        conversations: [today(times), yesterday(times), lastWeek(times), lastMonth(times)],
                        unseen: [ID.masterCorwen, ID.clockmakersGuild],
                        lastConversation: ID.conversationToday,
                        instructions: instruction)
    }

    /// A world with a name and nothing else: no pages, types or conversations. It has an id
    /// of its own, so it can be written beside the sample world.
    public static func empty() -> Contents {
        Contents(world: World(id: ID.emptyWorld, name: World.defaultName), schema: Schema(), pages: [], deleted: [],
                 conversations: [], unseen: [], lastConversation: nil, instructions: nil)
    }

    /// Writes it under `root`, the folder the app keeps its worlds in, through the stores the
    /// app uses, so the app loads it exactly as it loads a real one: `<root>/<world's id>/`
    /// with `World.json`, the pages in `Documents/` (those in Recently Deleted among them, as
    /// the app keeps them), `Schema.json` and `Conversations/`. If that world is there already,
    /// its folder is deleted first, so nothing a scene changed is left over. A world with no
    /// types or no conversations has no file or folder for them, like one the app has just made.
    public static func write(_ contents: Contents, to root: URL) throws {
        let worlds = try WorldStore(root: root)
        let id = contents.world.id
        if worlds.all().contains(where: { $0.id == id }) { try worlds.delete(id) }
        try worlds.save(contents.world)
        let pages = try DocumentStore(directory: worlds.documents(id))
        for page in contents.pages + contents.deleted { try pages.save(page) }
        if contents.schema != Schema() { try SchemaStore(url: worlds.schema(id)).save(contents.schema) }
        if !contents.conversations.isEmpty {
            let conversations = try ConversationStore(directory: worlds.conversations(id))
            for conversation in contents.conversations { try conversations.save(conversation) }
        }
    }

    /// Stable ids, so a scene can open a page or conversation by name. Each reads
    /// `5EED<what it is>-<which part>-4000-8000-<which one>`, the same in every run.
    public enum ID {
        public static let world = id(0, 1)
        /// The world `empty()` gives.
        public static let emptyWorld = id(0, 2)

        /// Bold, italic, a bulleted and a numbered list, and two `@` links.
        public static let harbourNotes = id(3, 1)
        /// A Character with five fields filled, one of each kind the app's first sample had
        /// (a choice, a number, a page, a date, a toggle), and words placed by filing.
        public static let mara = id(3, 2)
        /// A Character filing renamed today (it was "Tamsin"), with two paragraphs it placed.
        public static let oldTamsin = id(3, 3)
        /// A Character with fields filled and no writing.
        public static let jory = id(3, 4)
        /// A Place, with an `@` link.
        public static let breakwater = id(3, 5)
        /// A Place where one message's words were placed both ways: at the end of a paragraph
        /// of the author's, and as a paragraph of their own.
        public static let lighthouse = id(3, 6)
        /// A Place whose writing names three other pages, with no `@` link.
        public static let ironAbbey = id(3, 7)
        /// A Place with an `@` link, and a sentence placed by yesterday's conversation.
        public static let mapOfTheCoast = id(3, 8)
        /// A Group, the kind filing made today; everything on the page is from filing. Unseen.
        public static let clockmakersGuild = id(3, 9)
        /// The long Chapter: about 1,200 words.
        public static let nightTheBellRang = id(3, 10)
        /// A Chapter with a very long title, written on, with none of its fields filled.
        public static let chapterTwo = id(3, 11)
        /// A page with no title: one paragraph, which names it in lists.
        public static let untitled = id(3, 12)
        /// A rumour: a title and nothing else, made by filing today. Unseen.
        public static let masterCorwen = id(3, 13)
        /// In Recently Deleted.
        public static let captainHale = id(3, 14)

        /// The one the app opens again: nine turns, in which filing did everything it can do.
        public static let conversationToday = id(5, 1)
        /// A short one, ending on the author's words.
        public static let conversationYesterday = id(5, 2)
        /// One turn: the author's first words, never answered.
        public static let conversationLastWeek = id(5, 3)
        /// Thirty short turns, for scrolling.
        public static let conversationLastMonth = id(5, 4)

        /// The kinds of page (`PageType`).
        public enum Kind {
            public static let character = id(1, 1)
            public static let place = id(1, 2)
            public static let chapter = id(1, 3)
            /// Made by filing, in today's conversation.
            public static let group = id(1, 4)
        }

        /// The fields the kinds share (`FieldDefinition`).
        public enum Field {
            public static let species = id(2, 1)
            public static let age = id(2, 2)
            public static let home = id(2, 3)
            public static let firstSeen = id(2, 4)
            public static let keepsASecret = id(2, 5)
            public static let knownFor = id(2, 6)
            public static let gettingThere = id(2, 7)
            public static let number = id(2, 8)
            public static let pointOfView = id(2, 9)
            public static let status = id(2, 10)
            /// The three filing made, in today's conversation.
            public static let teacher = id(2, 11)
            public static let ledBy = id(2, 12)
            public static let members = id(2, 13)
        }

        /// The id of `page`'s paragraph `index`.
        static func paragraph(_ index: Int, of page: UUID) -> UUID { part(4, index, of: page) }

        /// The id of `conversation`'s turn `index`.
        static func turn(_ index: Int, of conversation: UUID) -> UUID { part(6, index, of: conversation) }

        /// The id of the `number`th placement of the author's words by filing (`Placement`).
        static func placement(_ number: Int) -> UUID { id(7, number) }

        /// The `number`th thing of one `kind`: 0 a world, 1 a kind of page, 2 a field, 3 a page,
        /// 5 a conversation, 7 a placement.
        private static func id(_ kind: Int, _ number: Int) -> UUID {
            UUID(uuidString: "5EED\(hex(kind, 4))-0000-4000-8000-\(hex(number, 12))")!
        }

        /// Part `index` of `whole`, with the whole's own number: 4 a page's paragraph, 6 a
        /// conversation's turn.
        private static func part(_ kind: Int, _ index: Int, of whole: UUID) -> UUID {
            UUID(uuidString: "5EED\(hex(kind, 4))-\(hex(index, 4))-4000-8000-\(whole.uuidString.suffix(12))")!
        }

        private static func hex(_ number: Int, _ width: Int) -> String {
            let digits = String(number, radix: 16, uppercase: true)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
    }
}

/// When things in the sample happened, counted back from `now`.
struct Times {
    var now: Date

    /// `now`, this long ago.
    func ago(days: Double = 0, hours: Double = 0, minutes: Double = 0) -> Date {
        now.addingTimeInterval(-((days * 24 + hours) * 60 + minutes) * 60)
    }
}
