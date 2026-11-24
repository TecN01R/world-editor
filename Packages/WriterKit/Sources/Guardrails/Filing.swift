import Foundation
import Provenance
import WriterCore

/// What the model reads out of one of the author's messages to the companion:
/// the pages it's about (their type, and for a new one what the author said it
/// is) and facts for their fields. The model writes it as JSON, as in the
/// prompt's example (`parse`), leaving out a part it has nothing for.
public struct Filings: Codable, Hashable, Sendable {
    public struct Page: Codable, Hashable, Sendable {
        public var title: String
        public var type: String
        public var about: String
        public init(title: String, type: String = "", about: String = "") {
            self.title = title; self.type = type; self.about = about
        }

        private enum CodingKeys: String, CodingKey { case title, type, about }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(title: try c.decode(String.self, forKey: .title),
                      type: (try? c.decodeIfPresent(String.self, forKey: .type)) ?? "",
                      about: (try? c.decodeIfPresent(String.self, forKey: .about)) ?? "")
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

    /// What the model wrote, read as JSON: each list on its own, so a code
    /// fence around it or a stray brace between them doesn't lose the other.
    /// What can't be read files nothing.
    public static func parse(_ text: String) -> Filings {
        func list<T: Decodable>(_ key: String, _: T.Type) -> [T] {
            guard let json = array(after: "\"\(key)\"", in: text),
                  let items = try? JSONDecoder().decode([Lenient<T>].self, from: Data(json.utf8)) else { return [] }
            return items.compactMap(\.value)
        }
        return Filings(facts: list("facts", Fact.self), pages: list("pages", Page.self))
    }

    /// The JSON array that follows `key`, up to its matching "]" (brackets in strings don't count).
    static func array(after key: String, in text: String) -> Substring? {
        guard let k = text.range(of: key), let open = text[k.upperBound...].firstIndex(of: "[") else { return nil }
        var depth = 0, inString = false, escaped = false
        for i in text[open...].indices {
            let c = text[i]
            if escaped { escaped = false; continue }
            if inString {
                if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                continue
            }
            switch c {
            case "\"": inString = true
            case "[": depth += 1
            case "]":
                depth -= 1
                if depth == 0 { return text[open...i] }
            default: break
            }
        }
        return nil
    }
}

/// One entry of a list, or nil if it isn't what was expected.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// What the model is asked, to read structure out of the author's message.
/// It runs after the companion has replied, on the same model, which writes
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
        is, in its exact words; leave it out when it doesn't say.
        When a fact's value is a name, give just the name, and list it under pages too.

        Example. The open page: "Bram" (no type yet). Their message: "He trained at the Iron \
        Abbey, a monastery in the hills, under Sister Maud. He's twenty. He lost his hand in the \
        Siege of Varn, in the winter of 1102."
        {"facts": [{"page": "Bram", "field": "Trained at", "value": "Iron Abbey"}, \
        {"page": "Bram", "field": "Teacher", "value": "Sister Maud"}, \
        {"page": "Bram", "field": "Age", "value": "twenty"}, \
        {"page": "Bram", "field": "Lost his hand in", "value": "Siege of Varn"}, \
        {"page": "Siege of Varn", "field": "When", "value": "winter of 1102"}], \
        "pages": [{"title": "Bram", "type": "Character"}, \
        {"title": "Iron Abbey", "type": "Place", "about": "a monastery in the hills"}, \
        {"title": "Sister Maud", "type": "Character"}, \
        {"title": "Siege of Varn", "type": "Event"}]}

        Copy their words exactly; never add, reword or guess. Leave out what they asked, wondered \
        about or weren't sure of, and what only their friend said. If their message states \
        nothing, return empty lists. Answer with the JSON alone, as in the example.
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
    public init(system: String, message: String) {
        self.system = system
        self.message = message
    }

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
        /// `phrase` as the author wrote it, and whether it's a name: capitalised
        /// mid-sentence ("the Treaty of Gull Rock"), not just at its start.
        func found(_ phrase: String) -> (words: String, isName: Bool)? {
            let wanted = Statement.collapsed(phrase).trimmingCharacters(in: Statement.edges)
            guard !wanted.isEmpty else { return nil }
            for s in sentences where !s.hedged {
                if let r = s.text.range(of: wanted, options: [.caseInsensitive, .diacriticInsensitive]) {
                    let words = String(s.text[r])
                    return (words, r.lowerBound != s.text.startIndex && Self.looksLikeAName(words))
                }
            }
            return nil
        }
        func words(_ phrase: String) -> String? { found(phrase)?.words }
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

        /// A new page, just behind the open one (as `@` makes them).
        func make(_ title: String, about: String? = nil) -> Int {
            let new = Document(title: title, paragraphs: [Paragraph(text: about ?? "")], modified: now)
            let at = min(1, pages.count)
            pages.insert(new, at: at)
            record.entries.append(.created(page: new.id, modified: now))
            return at
        }

        for page in filings.pages {
            var i = index(named: page.title)
            // A new page needs a name, as the author wrote one: capitalised ("Myriddea", not "grandmother").
            if i == nil, let title = words(page.title), title.contains(where: \.isUppercase) {
                let about = words(page.about).flatMap { key($0) == key(title) ? nil : $0.prefix(1).uppercased() + $0.dropFirst() }
                i = make(title, about: about)
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
                  let fieldName = name(fact.field), let hit = found(fact.value),
                  key(hit.words) != key(fieldName) else { continue }   // "Grandmother: grandmother" says nothing
            let words = hit.words
            let known = schema.fields(of: schema.types[t]).first { $0.name.lowercased() == fieldName.lowercased() }
                ?? schema.fields.first { $0.name.lowercased() == fieldName.lowercased() }
            // A name with no page yet gets one (the model often files "Sword: Mercy" without listing Mercy).
            let linkable = known.map { $0.kind == .page && pages[i].values[$0.id] == nil } ?? true
            if hit.isName, linkable, index(named: words) == nil { _ = make(words) }
            guard let i = index(named: fact.page) else { continue }   // where it is now, after a new page
            let linked = index(named: words).flatMap { $0 == i ? nil : pages[$0] }
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

    /// Every word capitalised, but for the small ones inside ("Treaty of Gull Rock", "Mercy").
    static func looksLikeAName(_ words: String) -> Bool {
        let parts = words.split(separator: " ")
        return parts.first?.first?.isUppercase == true
            && parts.allSatisfy { $0.first?.isUppercase == true || ["of", "the", "and", "de", "la", "von", "van"].contains($0) }
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
