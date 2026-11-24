import Foundation
import Provenance
import WriterCore

/// What the model reads out of one of the author's messages to the companion:
/// the pages it's about (their type, and for a new one what the author said it
/// is) and facts for their fields. Empty strings mean "none", which keeps the
/// shape simple for constrained decoding. The app's `@Generable` mirror and
/// `FilingPrompt.schema` must match it.
public struct Filings: Codable, Hashable, Sendable {
    public struct Page: Codable, Hashable, Sendable {
        public var title: String
        public var type: String
        public var about: String
        public init(title: String, type: String = "", about: String = "") {
            self.title = title; self.type = type; self.about = about
        }
    }

    public struct Fact: Codable, Hashable, Sendable {
        public var page: String
        public var field: String
        public var value: String
        public init(page: String, field: String, value: String) {
            self.page = page; self.field = field; self.value = value
        }
    }

    public var facts: [Fact]
    public var pages: [Page]

    public init(facts: [Fact] = [], pages: [Page] = []) {
        self.facts = facts
        self.pages = pages
    }
}

/// What the model is asked, to read structure out of the author's message.
/// It runs after the companion has replied, on the same model, with its output
public struct FilingPrompt: Equatable, Sendable {
    public var system: String
    public var message: String

    public static let instructions = """
        You keep a writer's pages in order. Each page is about one thing: a person, a place, a \
        group, an object, an event. A page has a type (Character, Place...) and fields (Origin, \
        Age...) that hold short facts.

        You're given the page they have open, what's in their world, and their latest message to \
        a friend they talk to about it. Write down what the message states as true:
        - facts: each fact it states about a page. page: that page's title (the open page when \
        they say "she", "he", "it" or "they"). field: what the fact is, in a word or two; use one \
        of the world's fields only when it means just that, otherwise a new name. value: their \
        exact words, as few as will do: a name, a number, a couple of words.
        - pages: the open page, with its type; and each person, place, group or thing the message \
        names that should have a page of its own. type: what kind of thing it is (one of the \
        world's types only if it is one; a ship is not a Place). about: what the message says it \
        is, in its exact words (or "").
        When a fact's value is a name, give just the name, and list it under pages too.

        Example. The open page: "Bram" (no type yet). Their message: "He trained at the Iron \
        Abbey, a monastery in the hills, under Sister Maud. He's twenty. He lost his hand in the \
        Siege of Varn, in the winter of 1102."
        {"facts": [{"page": "Bram", "field": "Trained at", "value": "Iron Abbey"}, \
        {"page": "Bram", "field": "Teacher", "value": "Sister Maud"}, \
        {"page": "Bram", "field": "Age", "value": "twenty"}, \
        {"page": "Bram", "field": "Lost his hand in", "value": "Siege of Varn"}, \
        {"page": "Siege of Varn", "field": "When", "value": "winter of 1102"}], \
        "pages": [{"title": "Bram", "type": "Character", "about": ""}, \
        {"title": "Iron Abbey", "type": "Place", "about": "a monastery in the hills"}, \
        {"title": "Sister Maud", "type": "Character", "about": ""}, \
        {"title": "Siege of Varn", "type": "Event", "about": ""}]}

        Copy their words exactly; never add, reword or guess. Leave out what they asked, wondered \
        about or weren't sure of, and what only their friend said. If their message states \
        nothing, return empty lists.
        """

    public static let schema = """
        {"type":"object","properties":{\
        "facts":{"type":"array","items":{"type":"object","properties":{\
        "page":{"type":"string"},"field":{"type":"string"},"value":{"type":"string"}},\
        "required":["page","field","value"]}},\
        "pages":{"type":"array","items":{"type":"object","properties":{\
        "title":{"type":"string"},"type":{"type":"string"},"about":{"type":"string"}},\
        "required":["title","type","about"]}}},\
        "required":["facts","pages"]}
        """

    /// - Parameters:
    ///   - page: the open page's title, its type's name and its "Name: value" field lines.
    ///   - types: the world's types, each with its field names.
    ///   - others: the other pages' titles.
    ///   - asked: what the companion said that the message answers.
    public init(page: (title: String, type: String?, fields: String), types: [(name: String, fields: [String])],
                others: [String], asked: String?, message: String) {
        system = Self.instructions
        var lines = ["The open page: \(Self.quoted(page.title))" + (page.type.map { " (type: \($0))" } ?? " (no type yet)")]
        if !page.fields.isEmpty { lines.append("Its fields:\n\(page.fields)") }
        lines.append(types.isEmpty ? "The world's types: none yet" : "The world's types:\n" + types.map {
            "- \($0.name)" + ($0.fields.isEmpty ? "" : ": \($0.fields.joined(separator: ", "))")
        }.joined(separator: "\n"))
        let titles = others.filter { !$0.isEmpty }.prefix(Self.maxOthers)
        if !titles.isEmpty { lines.append("Other pages: " + titles.joined(separator: ", ")) }
        if let asked, !asked.isEmpty { lines.append("Their friend said: \(Self.quoted(asked))") }
        lines.append("Their message: \(Self.quoted(message))")
        self.message = lines.joined(separator: "\n\n")
    }

    /// Enough titles to link the usual names; a world bigger than this needs a look-up (roadmap §5).
    static let maxOthers = 200

    private static func quoted(_ s: String) -> String { "\u{201C}\(s)\u{201D}" }
}

extension FilingPrompt {
    /// The prompt for `message`, sent from `page`'s conversation in a world of `pages` and `schema`.
    public init(open page: Document, pages: [Document], schema: Schema, asked: String?, message: String) {
        let type = schema.type(page.type)
        let fields = page.fieldText(schema.fields(of: type)) { id in pages.first { $0.id == id }?.heading }
        self.init(page: (title: page.title, type: type?.name, fields: fields),
                  types: schema.types.map { (name: $0.name, fields: schema.fields(of: $0).map(\.name)) },
                  others: pages.filter { $0.id != page.id }.map(\.heading), asked: asked, message: message)
    }
}

/// Files what the model read out of a message into the world, keeping only
/// what the author said: every value, new page title and new page text must be
/// their own words, found in a sentence of the message that isn't a question
/// or hedged ("maybe", "might"). Type and field names are structure, which
/// the model may choose (docs/ai-charter.md). Nothing the author wrote is
/// replaced: only empty fields are filled, only untyped pages get a type, and
/// an existing page's text is never touched. What's dropped is dropped, not
/// repaired.
public enum Filer {
    public static func file(_ filings: Filings, message: String, open: UUID,
                            pages: inout [Document], schema: inout Schema, now: Date = Date()) -> FilingRecord {
        let sentences = Statement.split(message)
        var record = FilingRecord()
        // Only questions or musing: nothing is stated, so nothing is filed (not even a type).
        guard sentences.contains(where: { !$0.hedged }) else { return record }
        func words(_ phrase: String) -> String? {
            let wanted = Statement.collapsed(phrase).trimmingCharacters(in: Statement.edges)
            guard !wanted.isEmpty else { return nil }
            for s in sentences where !s.hedged {
                if let r = s.text.range(of: wanted, options: [.caseInsensitive, .diacriticInsensitive]) {
                    return String(s.text[r])
                }
            }
            return nil
        }
        func index(named name: String) -> Int? {
            let name = Self.key(name)
            guard !name.isEmpty else { return nil }
            if let i = pages.firstIndex(where: { $0.id == open }),
               Self.key(pages[i].title) == name || Self.openPage.contains(name) { return i }
            return pages.firstIndex { Self.key($0.heading) == name }
        }
        func type(named name: String) -> UUID? {
            guard let name = Self.name(name) else { return nil }
            if let type = schema.types.first(where: { $0.name.lowercased() == name.lowercased() }) { return type.id }
            let type = PageType(name: name)
            schema.types.append(type)
            record.entries.append(.newType(type.id))
            return type.id
        }

        for page in filings.pages {
            var i = index(named: page.title)
            // A new page needs a name, as the author wrote one: capitalised ("Myriddea", not "grandmother").
            if i == nil, let title = words(page.title), title.contains(where: \.isUppercase) {
                let about = words(page.about).flatMap { key($0) == key(title) ? nil : $0.prefix(1).uppercased() + $0.dropFirst() }
                let new = Document(title: title, paragraphs: [Paragraph(text: about ?? "")], modified: now)
                i = min(1, pages.count)   // just behind the open page, as `@` makes them
                pages.insert(new, at: i!)
                record.entries.append(.created(page: new.id, modified: now))
            }
            guard let i, pages[i].type == nil, let type = type(named: page.type) else { continue }
            pages[i].type = type
            if !record.entries.contains(.created(page: pages[i].id, modified: now)) {
                record.entries.append(.typed(page: pages[i].id, type: type))
            }
        }

        for fact in filings.facts {
            guard let i = index(named: fact.page), let typeID = pages[i].type,
                  let t = schema.types.firstIndex(where: { $0.id == typeID }),
                  let fieldName = name(fact.field), let words = words(fact.value),
                  key(words) != key(fieldName) else { continue }   // "Grandmother: grandmother" says nothing
            let linked = index(named: words).flatMap { $0 == i ? nil : pages[$0] }
            let known = schema.fields(of: schema.types[t]).first { $0.name.lowercased() == fieldName.lowercased() }
                ?? schema.fields.first { $0.name.lowercased() == fieldName.lowercased() }
            let field = known ?? FieldDefinition(name: fieldName, kind: linked == nil ? .text : .page,
                                                 pageType: linked?.type)
            guard pages[i].values[field.id] == nil, let value = value(words, linked: linked, for: field) else { continue }
            if known == nil {
                schema.fields.append(field)
                record.entries.append(.newField(field.id))
            }
            if !schema.types[t].fields.contains(field.id) {
                schema.types[t].fields.append(field.id)
                record.entries.append(.fieldAdded(type: typeID, field: field.id))
            }
            pages[i].values[field.id] = value
            record.entries.append(.value(page: pages[i].id, field: field.id, value: value))
        }
        return record
    }

    /// What the model may call the open page instead of its title (an untitled one has none).
    static let openPage: Set = ["she", "he", "it", "they", "her", "him", "them", "this page", "the open page"]

    /// The author's words as a value of `field`'s kind; nil if they don't fit it.
    private static func value(_ words: String, linked: Document?, for field: FieldDefinition) -> FieldValue? {
        switch field.kind {
        case .page: linked.map { .page($0.id) }
        case .text, .longText: .text(words)
        case .choice: field.options.first { $0.lowercased() == words.lowercased() }.map { .text($0) }
        case .number: Double(words).map { .number($0) }
        case .date, .toggle: nil
        }
    }

    /// How names are matched: "The Guild of Lamps" is "guild of lamps".
    static func key(_ name: String) -> String {
        let name = Statement.collapsed(name).trimmingCharacters(in: Statement.edges).lowercased()
        return name.hasPrefix("the ") ? String(name.dropFirst(4)) : name
    }

    /// A type or field name the model chose: a few words on one line, capitalised.
    static func name(_ raw: String) -> String? {
        let name = Statement.collapsed(raw).trimmingCharacters(in: Statement.edges)
        guard !name.isEmpty, name.count <= 40, !["none", "none yet", "unknown", "n/a"].contains(name.lowercased())
        else { return nil }
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

/// A sentence of the author's message, and whether it's a question or hedged.
struct Statement {
    var text: String
    var hedged: Bool

    static let edges = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        .subtracting(CharacterSet(charactersIn: "-'"))

    /// Straight quotes, single spaces: how the message and the model's copy are compared.
    static func collapsed(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func split(_ message: String) -> [Statement] {
        var out: [Statement] = [], current = ""
        func end(_ mark: Character?) {
            let text = collapsed(current)
            if !text.isEmpty { out.append(Statement(text: text, hedged: mark == "?" || hedges(text))) }
            current = ""
        }
        for c in message {
            if c.isNewline { end(nil); continue }
            current.append(c)
            if ".!?".contains(c) { end(c) }
        }
        end(nil)
        return out
    }

    /// Whether the sentence holds one of the author's words for uncertainty, as a whole word.
    private static func hedges(_ text: String) -> Bool {
        let padded = " " + String(text.lowercased().map { $0.isLetter || $0 == "'" ? $0 : " " }) + " "
        return ProvenanceValidator.hedges.contains { $0 != "?" && padded.contains(" \($0) ") }
    }
}
