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
/// `Filings` as JSON.
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
        names that should have a page of its own. about: the words the message uses for what it \
        is ("a monastery in the hills"; "the fishing village of Holm" gives "fishing village"), \
        exactly; leave it out only when the message just names it. type: what kind of thing it is \
        (one of the world's types only if it is one; a ship is not a Place).
        When a fact's value is a name, give just the name, and list it under pages too.

        Example. The open page: "Bram" (no type yet). Their message: "He trained at the Iron \
        Abbey, a monastery in the hills, under Sister Maud, an old healer. He comes from the \
        fishing village of Holm. He's twenty. He lost his hand in the Siege of Varn, the war's \
        last battle, in the winter of 1102."
        {"facts": [{"page": "Bram", "field": "Trained at", "value": "Iron Abbey"}, \
        {"page": "Bram", "field": "Teacher", "value": "Sister Maud"}, \
        {"page": "Bram", "field": "Comes from", "value": "Holm"}, \
        {"page": "Bram", "field": "Age", "value": "twenty"}, \
        {"page": "Bram", "field": "Lost his hand in", "value": "Siege of Varn"}, \
        {"page": "Siege of Varn", "field": "When", "value": "winter of 1102"}], \
        "pages": [{"title": "Bram", "type": "Character"}, \
        {"title": "Iron Abbey", "about": "a monastery in the hills", "type": "Place"}, \
        {"title": "Sister Maud", "about": "an old healer", "type": "Character"}, \
        {"title": "Holm", "about": "fishing village", "type": "Place"}, \
        {"title": "Siege of Varn", "about": "the war's last battle", "type": "Event"}]}

        Copy their words exactly; never add, reword or guess. Leave out what they asked, wondered \
        about or weren't sure of, and what only their friend said. Give a field that already has \
        a value only when they correct it ("actually it's a bireme"); her age when something \
        happened is not her age. If their message states nothing, return empty lists. Answer \
        with the JSON alone, as in the example.
        """


    /// - Parameters:
    ///   - page: the open page's title, its type's name and its "Name: value" field lines;
    ///     nil in the world's own conversation, where no page is open.
    ///   - types: the world's types, each with its field names.
    ///   - others: the other pages' titles (with no page open, each with its filled fields).
    ///   - asked: what the companion said that the message answers.
    public init(page: (title: String, type: String?, fields: String)?, types: [(name: String, fields: [String])],
                others: [String], asked: String?, message: String) {
        system = Self.instructions
        var lines: [String]
        if let page {
            lines = ["The open page: \(Self.quoted(page.title))" + (page.type.map { " (type: \($0))" } ?? " (no type yet)")]
            if !page.fields.isEmpty { lines.append("Its fields:\n\(page.fields)") }
        } else {
            lines = ["No page is open: they're talking about their world as a whole."]
        }
        lines.append(types.isEmpty ? "The world's types: none yet" : "The world's types:\n" + types.map {
            "- \($0.name)" + ($0.fields.isEmpty ? "" : ": \($0.fields.joined(separator: ", "))")
        }.joined(separator: "\n"))
        let titles = others.filter { !$0.isEmpty }.prefix(Self.maxOthers)
        if !titles.isEmpty { lines.append((page == nil ? "Their pages: " : "Other pages: ") + titles.joined(separator: ", ")) }
        if let asked, !asked.isEmpty { lines.append("Their friend said: \(Self.quoted(asked))") }
        lines.append("Their message: \(Self.quoted(message))")
        self.message = lines.joined(separator: "\n\n")
    }

    /// Enough titles to link the usual names; a world bigger than this needs a look-up (roadmap §5).
    static let maxOthers = 200

    private static func quoted(_ s: String) -> String { "\u{201C}\(s)\u{201D}" }
}

extension FilingPrompt {
    /// A prompt as built elsewhere.
    public init(system: String, message: String) {
        self.system = system
        self.message = message
    }

    /// The prompt for `message`, sent from the world's own conversation: no page open.
    public init(world pages: [Document], schema: Schema, asked: String?, message: String) {
        // With no page open, each page's filled fields show with its name: the model can see
        // what's already set before it gives a field a value.
        let others = pages.map { page -> String in
            let filled = page.fieldText(schema.fields(of: schema.type(page.type))) { id in pages.first { $0.id == id }?.heading }
                .split(separator: "\n").joined(separator: "; ")
            return filled.isEmpty ? page.heading : "\(page.heading) (\(filled))"
        }
        self.init(page: nil, types: schema.types.map { (name: $0.name, fields: schema.fields(of: $0).map(\.name)) },
                  others: others, asked: asked, message: message)
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
/// the model may choose (docs/ai-charter.md). A field that has a value gets
/// a new one only from a message that corrects something ("Actually it's a
/// bireme"), kept in the record so Undo puts the old one back. Only untyped
/// pages get a type, and a page's writing is only added to, at its end, with
/// the sentences the facts came from (`Placement`). What's dropped is dropped,
/// not repaired.
public enum Filer {
    /// Whether `message` states anything: not only questions, guesses and musing. Filing
    /// one that doesn't can only find nothing, so it isn't asked of the model either.
    public static func states(_ message: String) -> Bool {
        Statement.split(message).contains { !$0.hedged }
    }

    /// - Parameters:
    ///   - replaceable: whether a filled field (page, field, its value) may take a corrected
    ///     value; reading a message again passes what it saw the first time.
    ///   - renames: whether naming the page's subject may rename it (reading again: only if
    ///     the title is still what it was the first time).
    public static func file(_ filings: Filings, message: String, open: UUID,
                            pages: inout [Document], schema: inout Schema, now: Date = Date(),
                            replaceable: (UUID, UUID, FieldValue) -> Bool = { _, _, _ in true },
                            renames: Bool = true) -> FilingRecord {
        let sentences = Statement.split(message)
        var record = FilingRecord()
        // Only questions or musing: nothing is stated, so nothing is filed (not even a type).
        guard states(message) else { return record }
        /// `phrase` as the author wrote it, as whole words; whether it's a name (capitalised
        /// mid-sentence, as "the Treaty of Gull Rock", not just at its start); whether
        /// it's said as a correction (`Statement.corrects`); and which sentence says it.
        func found(_ phrase: String) -> (words: String, isName: Bool, corrects: Bool, sentence: Int)? {
            let wanted = Statement.collapsed(phrase).trimmingCharacters(in: Statement.edges)
            guard !wanted.isEmpty else { return nil }
            for (n, s) in sentences.enumerated() where !s.hedged {
                guard let r = Statement.wholeWords(wanted, in: s.text) else { continue }
                let words = String(s.text[r])
                let previous = n > 0 ? sentences[n - 1].text : nil
                return (words, r.lowerBound != s.text.startIndex && Self.looksLikeAName(words),
                        Statement.corrects(s.text, after: previous), n)
            }
            return nil
        }
        func words(_ phrase: String) -> String? { found(phrase)?.words }
        var renamed: String?   // the open page's new name, if the message gives one (below)
        func index(named name: String) -> Int? {
            let name = Self.key(name)
            guard !name.isEmpty else { return nil }
            if let i = pages.firstIndex(where: { $0.id == open }),
               Self.key(pages[i].title) == name || Self.openPage.contains(name) || renamed.map(Self.key) == name { return i }
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

        // Naming the open page's subject ("Her name is Florica") renames the page: not a
        // Name field, nor a new page by that name (Kevin, 2026-11-24). Applied at the end, so
        // lines by the old title still find the page; ones by the new title find it too.
        // (By id each time: new pages go in near the top and move it.)
        func isOpen(_ i: Int?) -> Bool { i.map { pages[$0].id == open } ?? false }
        if renames, let o = pages.firstIndex(where: { $0.id == open }) {
            // The model may call the page by its new name ("Mara: Name = Mara" on an untitled one).
            func about(_ fact: Filings.Fact) -> Bool {
                index(named: fact.page) == o || (index(named: fact.page) == nil && Self.key(fact.page) == Self.key(fact.value))
            }
            for fact in filings.facts where Self.nameFields.contains(Self.key(fact.field)) && about(fact) {
                // Not a name it already has, or part of it ("Florica" for "Florica Dragan").
                guard let hit = found(fact.value), hit.words.contains(where: \.isUppercase),
                      !Set(Self.key(hit.words).split(separator: " "))
                          .isSubset(of: Self.key(pages[o].title).split(separator: " ")) else { continue }
                renamed = hit.words
                break
            }
        }

        for page in filings.pages {
            var i = index(named: page.title)
            // A new page needs a name, as the author wrote one: capitalised ("Myriddea", not "grandmother").
            if i == nil, let title = words(page.title), title.contains(where: \.isUppercase) {
                // Its text says what it is: not part of its name ("Lady" for Lady Corvina), nor what
                // it isn't ("not Port Vell").
                let named = Set(key(title).split(separator: " "))
                let about = words(page.about).flatMap {
                    Set(key($0).split(separator: " ")).isSubset(of: named) || key($0).hasPrefix("not ")
                        ? nil : $0.prefix(1).uppercased() + $0.dropFirst()
                }
                i = make(title, about: about)
            }
            guard let i, pages[i].type == nil, let type = type(named: page.type) else { continue }
            pages[i].type = type
            if !record.entries.contains(.created(page: pages[i].id, modified: now)) {
                record.entries.append(.typed(page: pages[i].id, type: type))
            }
        }

        var filled = Set<[UUID]>()   // page and field filled from this message
        for fact in filings.facts {
            // The open page's name is its title (above), never a field.
            if Self.nameFields.contains(Self.key(fact.field)), isOpen(index(named: fact.page)) { continue }
            // What a page is ("Type: an island republic of glassblowers") is never a field: the
            // sentence saying it goes into the page's writing, below (Kevin, 2026-11-24: "Put that
            // in the page content, not the type").
            if Self.descriptionFields.contains(Self.key(fact.field)) { continue }
            guard let i = index(named: fact.page), let typeID = pages[i].type,
                  let t = schema.types.firstIndex(where: { $0.id == typeID }),
                  let fieldName = name(fact.field), let hit = found(fact.value),
                  key(hit.words) != key(fieldName) else { continue }   // "Grandmother: grandmother" says nothing
            let words = hit.words
            let onType = schema.fields(of: schema.types[t]).first { $0.name.lowercased() == fieldName.lowercased() }
            let shared = schema.fields.first { $0.name.lowercased() == fieldName.lowercased() }
            // A field the author took off this type (its pages still hold values in it) isn't put back.
            if onType == nil, let shared, pages.contains(where: { $0.type == typeID && $0.values[shared.id] != nil }) { continue }
            let known = onType ?? shared
            // A name with no page yet gets one (the model often files "Sword: Mercy" without listing Mercy).
            let linkable = known.map { def in
                def.kind == .page && (pages[i].values[def.id].map { hit.corrects && replaceable(pages[i].id, def.id, $0) } ?? true)
            } ?? true
            if hit.isName, linkable, index(named: words) == nil { _ = make(words) }
            guard let i = index(named: fact.page) else { continue }   // where it is now, after a new page
            let linked = index(named: words).flatMap { $0 == i ? nil : pages[$0] }
            let field = known ?? FieldDefinition(name: fieldName, kind: linked == nil ? .text : .page,
                                                 pageType: linked?.type)
            // A field filled from this message keeps its first value; one filled before changes
            // only when the sentence saying the new value corrects something.
            let was = pages[i].values[field.id]
            guard let value = value(words, linked: linked, for: field), value != was,
                  was.map({ hit.corrects && replaceable(pages[i].id, field.id, $0) }) ?? true,
                  !filled.contains([pages[i].id, field.id]) else { continue }
            filled.insert([pages[i].id, field.id])
            if known == nil {
                schema.fields.append(field)
                record.entries.append(.newField(field.id))
            }
            if !schema.types[t].fields.contains(field.id) {
                schema.types[t].fields.append(field.id)
                record.entries.append(.fieldAdded(type: typeID, field: field.id))
            }
            pages[i].values[field.id] = value
            record.entries.append(was.map { .replaced(page: pages[i].id, field: field.id, was: $0, value: value) }
                                  ?? .value(page: pages[i].id, field: field.id, value: value))
        }
        if let title = renamed, let o = pages.firstIndex(where: { $0.id == open }) {
            record.entries.append(.renamed(page: pages[o].id, was: pages[o].title, title: title))
            pages[o].title = title
        }

        // The sentences the facts came from go into their pages' writing, as the author wrote
        // them (Kevin, 2026-11-24: "fill my pages as long as it uses my own words"; 2026-11-26:
        // "fill in the description based on things I said automatically"). Even where a field
        // kept its value: a sentence that contradicts the page is still theirs to have there.
        var said: [UUID: Set<Int>] = [:]
        for fact in filings.facts where !Self.nameFields.contains(Self.key(fact.field)) {   // the title says it
            guard let i = index(named: fact.page), let hit = found(fact.value),
                  key(hit.words) != key(fact.field) else { continue }   // "Grandmother: grandmother" says nothing
            said[pages[i].id, default: []].insert(hit.sentence)
        }
        for (page, numbers) in said.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            guard let i = pages.firstIndex(where: { $0.id == page }) else { continue }
            let written = pages[i].paragraphs.map { HisWords.words($0.text) }
            // What this message said about the page, leaving out what's on it already.
            let new = numbers.sorted().map { sentences[$0].text }.filter { sentence in
                !written.contains { $0.contains(HisWords.words(sentence)) }   // together and in order
            }
            // Each where it fits: after the author's paragraph about the same thing, or else
            // together at the end of the page (`HisWords.fit`).
            var groups: [(to: UUID?, sentences: [String])] = []
            for sentence in new {
                let to = HisWords.fit(sentence, in: pages[i])
                if let g = groups.firstIndex(where: { $0.to == to }) { groups[g].sentences.append(sentence) }
                else { groups.append((to, [sentence])) }
            }
            var placement = Placement(page: page, paragraphs: [], texts: [], date: now)
            for group in groups {
                let joined = group.sentences.joined(separator: " ")
                let text = HisWords.tidied(joined)
                guard HisWords.sameWords(text, joined) else { continue }
                if let to = group.to, pages[i].append(text, to: to, as: placement.id) {
                    placement.paragraphs.append(to)
                    placement.appended.append(true)
                } else {
                    placement.paragraphs += pages[i].place([text], as: placement.id)
                    placement.appended.append(false)
                }
                placement.texts.append(text)
            }
            if !placement.paragraphs.isEmpty { record.entries.append(.placed(placement)) }
        }
        return record
    }

    /// Field names that mean the page's own name.
    static let nameFields: Set = ["name", "full name", "called", "named"]

    /// Field names that mean what the page is: its text, not a field.
    static let descriptionFields: Set = ["type", "kind", "description", "about", "what it is", "summary", "overview"]

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

    /// The message's sentences. One ends at a line break, or at ".", "!" or "?" before a
    /// space, a closing quote or the end: not inside "3.5", nor after a title or an
    /// initial ("Dr. Vance", "J. R. Hale").
    static func split(_ message: String) -> [Statement] {
        let chars = Array(message)
        var out: [Statement] = [], current = ""
        func end(_ mark: Character?) {
            let text = collapsed(current)
            if !text.isEmpty { out.append(Statement(text: text, hedged: mark == "?" || hedges(text))) }
            current = ""
        }
        for (i, c) in chars.enumerated() {
            if c.isNewline { end(nil); continue }
            current.append(c)
            guard ".!?".contains(c) else { continue }
            let next = i + 1 < chars.count ? chars[i + 1] : nil
            guard next.map({ $0.isWhitespace || "\"')]\u{201D}\u{2019}".contains($0) }) ?? true else { continue }
            if c == ".", abbreviated(current.dropLast()) { continue }
            end(c)
        }
        end(nil)
        return out
    }

    /// Titles written with a full stop that doesn't end the sentence.
    private static let titles: Set<String> = ["mr", "mrs", "ms", "dr", "st", "mt", "jr", "sr", "prof", "gen",
                                              "capt", "col", "lt", "sgt", "rev", "fr", "vs"]

    /// Whether `text` ends in a title or an initial (one capital, never "I").
    private static func abbreviated(_ text: Substring) -> Bool {
        guard text.last?.isLetter == true, let last = text.split(whereSeparator: { !$0.isLetter }).last else { return false }
        return titles.contains(last.lowercased()) || (last.count == 1 && last != "I" && last.allSatisfy(\.isUppercase))
    }

    /// Where `phrase` is in `text` as whole words, ignoring case and accents: "Al" is
    /// never found inside "always".
    static func wholeWords(_ phrase: String, in text: String) -> Range<String.Index>? {
        func wordy(_ c: Character?) -> Bool { c.map { $0.isLetter || $0.isNumber } ?? false }
        var from = text.startIndex
        while let r = text.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive], range: from..<text.endIndex) {
            let before = r.lowerBound > text.startIndex ? text[text.index(before: r.lowerBound)] : nil
            let after = r.upperBound < text.endIndex ? text[r.upperBound] : nil
            if !wordy(before), !wordy(after) { return r }
            from = text.index(after: r.lowerBound)
        }
        return nil
    }

    /// Whether the sentence holds one of the author's words for uncertainty, as a whole word.
    /// "I think it was actually a bireme" is a correction said politely, not a guess (Kevin,
    /// 2026-11-24), as is "Actually, I think…"; "I'm not actually sure" or "I don't
    /// actually know" isn't, and counts as unsure on its own.
    private static func hedges(_ text: String) -> Bool {
        let polite = has(["actually"], in: text)
        let unsure = ["not actually sure", "not really sure", "not entirely sure", "not quite sure",
                      "not completely sure", "not certain", "unsure", "don't know", "don't actually know",
                      "no idea", "can't remember", "don't remember", "i guess"]
        return has(ProvenanceValidator.hedges.filter { $0 != "?" && !(polite && $0 == "i think") } + unsure, in: text)
    }

    /// Words that take something back, in the sentence that says the new value or the one
    /// before it ("Wait. She's twenty.").
    private static let corrections = ["actually", "sorry", "wait", "oops", "correction", "meant", "i mean",
                                      "wrong", "instead", "rather"]

    /// Whether `sentence` corrects something, so a filled field may change: a word of
    /// `corrections` in it or the sentence before, or a "not", "isn't", "wasn't" or
    /// "changed" in it, or either opening with "No". So "she was nineteen when…", or "She
    /// has no siblings. She's forty.", doesn't replace her age.
    static func corrects(_ sentence: String, after previous: String?) -> Bool {
        func takesBack(_ s: String) -> Bool {
            has(corrections, in: s) || s.lowercased().split(whereSeparator: { !$0.isLetter }).first == "no"
        }
        return takesBack(sentence) || has(["not", "isn't", "wasn't", "changed"], in: sentence)
            || previous.map(takesBack) ?? false
    }

    /// Whether `text` holds one of `words` as whole words.
    static func has(_ words: [String], in text: String) -> Bool {
        let letters = String(collapsed(text).lowercased().map { $0.isLetter || $0 == "'" ? $0 : " " })
        let padded = " " + letters.split(separator: " ").joined(separator: " ") + " "   // "not 100% sure" is "not sure"
        return words.contains { padded.contains(" \($0) ") }
    }
}
