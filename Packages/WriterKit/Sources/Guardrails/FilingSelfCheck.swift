import Foundation
import WriterCore

/// Whether filing works with the model on this phone, checked on a small made-up world of
/// its own (never the author's pages): five exchanges of the world's conversation, written
/// the way the author writes to the companion (a sentence at a time, often with no capital
/// or full stop, its subject often only "she"). Each is read by the model and filed as a
/// real one is (`Filer.focus`, `FilingPrompt(world:)`, `Filer.file`), and passes only if
/// its words landed where they should. Debug builds run it and write how it went to the
/// phone's log.
public enum FilingSelfCheck {
    /// How one exchange went: its letter, and in a line why it failed, if it did.
    public struct Outcome: Equatable, Sendable {
        public var letter: String
        public var passed: Bool
        public var reason: String
    }

    /// One exchange: what the companion said before it (made up, as all of it is) and the
    /// author's message.
    struct Exchange: Sendable {
        var letter: String
        var asked: String
        var message: String
    }

    static let exchanges = [
        // A plain statement that names its pages: it should fill one, or make one.
        Exchange(letter: "a", asked: "",
                 message: "Old Tamsin is the oldest clockmaker in the Clockmakers' Guild and has kept its brass bench for forty years."),
        // Straight after it, its subject only "she": onto Old Tamsin's page, as written.
        Exchange(letter: "b", asked: "Forty years at one bench.",
                 message: "she was expelled from the guild for mending clocks for free"),
        // Part of a name: onto The Clockmakers' Guild's page.
        Exchange(letter: "c", asked: "For free? That seems harsh.",
                 message: "the guild meets in the old customs house"),
        // Only a question: nothing is filed.
        Exchange(letter: "d", asked: "A customs house, for clockmakers.",
                 message: "does the guild ever take anyone back after that?"),
        // A correction that names its page: her Age changes. (Run into its question with a
        // comma it would be one sentence, a question, and nothing of it would be filed.)
        Exchange(letter: "e", asked: "I don't know. Does it?",
                 message: "Actually Old Tamsin is 71 not 61. Does that change anything?"),
    ]

    /// Runs the five exchanges in order. `read` is the model: given an exchange's filing
    /// prompt, what it read out of the message. If it throws (stopped for a reply), so does this.
    public static func run(reading read: @Sendable (FilingPrompt) async throws -> Filings) async rethrows -> [Outcome] {
        // The world: Old Tamsin, a Character aged 61, and The Clockmakers' Guild, a Group.
        let age = FieldDefinition(name: "Age", kind: .text)
        let character = PageType(name: "Character", fields: [age.id]), group = PageType(name: "Group")
        let tamsin = Document(title: "Old Tamsin", paragraphs: [Paragraph(text: "")], type: character.id,
                              values: [age.id: .text("61")])
        let guild = Document(title: "The Clockmakers' Guild", paragraphs: [Paragraph(text: "")], type: group.id)
        var pages = [tamsin, guild], schema = Schema(fields: [age], types: [character, group])
        var talk = Conversation(page: UUID(), aboutWorld: true)
        var outcomes: [Outcome] = []

        for exchange in exchanges {
            if !exchange.asked.isEmpty { talk.ask(exchange.asked) }
            talk.answer(exchange.message)
            let turn = talk.turns[talk.turns.count - 1]
            let focus = Filer.focus(before: turn.id, in: talk, pages: pages)
            let prompt = FilingPrompt(world: pages, schema: schema, asked: turn.question, message: exchange.message,
                                      focus: focus, saidBefore: Filer.said(before: turn.id, in: talk))
            let before = pages
            let record = Filer.file(try await read(prompt), message: exchange.message, open: talk.page,
                                    pages: &pages, schema: &schema, focus: focus)
            talk.turns[talk.turns.count - 1].filed = record

            /// Why the message's sentence isn't on `page` as written (tidied only), or nil if it is.
            func missing(from page: Document) -> String? {
                let sentence = HisWords.tidied(exchange.message)
                func has(_ page: Document) -> Bool { page.paragraphs.contains { $0.text.contains(sentence) } }
                if pages.contains(where: { $0.id == page.id && has($0) }) { return nil }
                guard let other = pages.first(where: has) else { return "it wasn't filed" }
                return "it went on \u{201C}\(other.title)\u{201D}, not \u{201C}\(page.title)\u{201D}"
            }
            let failure: String?
            switch exchange.letter {
            case "a": failure = record.isEmpty ? "nothing was filed from a plain statement" : nil
            case "b": failure = missing(from: tamsin)
            case "c": failure = missing(from: guild)
            case "d": failure = record.isEmpty && pages == before ? nil : "a question was filed"
            default:
                switch pages.first(where: { $0.id == tamsin.id })?.values[age.id] {
                case .text("71"): failure = nil
                case .text(let other): failure = "Old Tamsin's Age is \(other), not 71"
                default: failure = "Old Tamsin's Age isn't 71"
                }
            }
            outcomes.append(Outcome(letter: exchange.letter, passed: failure == nil, reason: failure ?? ""))
        }
        return outcomes
    }
}
