import Foundation
import WriterCore

/// The companion's search of the author's own pages and of what they told it in earlier
/// conversations: the text of its `search_pages` tool, and the passages the app puts in
/// the prompt for what the author just said. Everything it returns is the author's own
/// words (docs/ai-charter.md): their passages, fields and answers, never the companion's
/// lines. Built from a snapshot of the world, so it is `Sendable` and needs no main actor.
///
/// Ranking is by words (tested here, on Linux); on the phone, Spotlight's ranked item ids
/// come first (`ranked`), and these lexical hits follow, covering what Spotlight missed
/// or hasn't indexed yet.
public struct PageLookup: Sendable {
    /// A page as the search sees it.
    public struct Page: Sendable {
        public var id: UUID
        /// Its name in the pages list.
        public var heading: String
        public var type: String?
        /// "Name: value" lines, a linked page shown by its heading.
        public var fields: [String]
        /// Its paragraphs that have words, in order.
        public var paragraphs: [(id: UUID, text: String)]
        public var modified: Date

        public init(id: UUID = UUID(), heading: String, type: String? = nil, fields: [String] = [],
                    paragraphs: [(id: UUID, text: String)] = [], modified: Date = Date()) {
            self.id = id
            self.heading = heading
            self.type = type
            self.fields = fields
            self.paragraphs = paragraphs
            self.modified = modified
        }
    }

    /// Something the author told the companion in an earlier conversation, in their words.
    public struct Answer: Sendable {
        /// Where they said it, as the results name it: "the conversation on “Ilsa”".
        public var place: String
        public var text: String
        public var date: Date
        /// The page the conversation is about; nil for one about the whole world.
        public var page: UUID?

        public init(place: String, text: String, date: Date = Date(), page: UUID? = nil) {
            self.place = place
            self.text = text
            self.date = date
            self.page = page
        }
    }

    public let pages: [Page]
    public let answers: [Answer]
    private let index: Index

    // MARK: The tool

    public static let toolName = "search_pages"
    public static let toolDescription = "Searches the writer's own pages, and what they told you in earlier "
        + "conversations, for a name or a few words. Returns the matching passages in their words; the name of "
        + "one of their pages returns that page. For their world only: it knows nothing about the real world."
    /// The guide of its one argument, `query`.
    public static let queryGuide = "A name from their pages, or a few of their words to look for"
    /// Searches allowed in one reply; the next gets `lastSearch`.
    public static let searchesPerReply = 2
    /// The most a search returns.
    public static let maxCharacters = 1500
    public static let needsQuery = "search_pages needs a name or a few words to look for."
    public static let lastSearch = "That's the last search for this reply: answer from what you found."

    public static func nothingFound(_ query: String) -> String {
        "Nothing on their pages or in what they've told you mentions \u{201C}\(CompanionPrompt.oneLine(query, maxCharacters: 80))\u{201D}."
    }

    // MARK: Building it

    public init(pages: [Page], answers: [Answer] = []) {
        self.pages = pages
        self.answers = answers
        index = Index(pages: pages, answers: answers)
    }

    /// The snapshot of a world: its `pages` (not those in Recently Deleted), with their
    /// types and fields from `schema`, and what the author answered in `conversations`.
    /// A conversation about a page that's gone is left out.
    public init(pages documents: [Document], schema: Schema, conversations: [Conversation] = []) {
        let live = documents.filter { $0.deleted == nil }
        let headings = Dictionary(live.map { ($0.id, $0.heading) }, uniquingKeysWith: { first, _ in first })
        let pages = live.map { page in
            let type = schema.type(page.type)
            return Page(id: page.id, heading: page.heading, type: type?.name,
                        fields: page.fieldLines(schema.fields(of: type)) { headings[$0] },
                        paragraphs: page.paragraphs.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
                            .map { (id: $0.id, text: $0.text) },
                        modified: page.modified)
        }
        let answers = conversations.flatMap { talk -> [Answer] in
            let place: String
            if talk.aboutWorld {
                place = "a conversation about their whole world"
            } else if let heading = headings[talk.page] {
                place = heading.isEmpty ? "the conversation on an untitled page" : "the conversation on \u{201C}\(heading)\u{201D}"
            } else {
                return []
            }
            return talk.turns.compactMap { turn in
                turn.answer.map { Answer(place: place, text: $0, date: turn.answered ?? turn.asked,
                                         page: talk.aboutWorld ? nil : talk.page) }
            }
        }
        self.init(pages: pages, answers: answers)
    }

    // MARK: Searching

    /// The tool's text for `query`, at most `maxCharacters`, plain for Gemma
    /// (`Reasoned.gemmaPlain`): the page it names, with its fields and writing and the other
    /// pages that mention it; or the pages with the most matching passages; then what the
    /// author told the companion about it. `ranked`: Spotlight's item ids for the query, best
    /// first; they come before the lexical hits, and those of pages or paragraphs no longer
    /// here are dropped.
    public func results(for query: String, ranked: [String] = []) -> String {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Self.needsQuery }
        let match = index.match(Self.terms(query, leavingOut: Self.stopwords))
        let named = self.named(query)
        let hits = pageHits(ranked: ranked, match: match, without: named, limit: named == nil ? 5 : 4)
        let said = answerLines(match)
        let lines = self.lines(hits, found: match.found)
        if let named {
            return Self.assemble(head: describe(named, maxCharacters: 900), pages: lines, heading: "Also on their pages:",
                                 said: said, maxCharacters: Self.maxCharacters)
        }
        guard !hits.isEmpty || !said.isEmpty else { return Reasoned.gemmaPlain(Self.nothingFound(query)) }
        return Self.assemble(head: [], pages: lines,
                             heading: "Their pages, for \u{201C}\(CompanionPrompt.oneLine(query, maxCharacters: 80))\u{201D}:",
                             said: said, maxCharacters: Self.maxCharacters)
    }

    /// What the author's pages and earlier answers say about `message` (what they just
    /// said), for the prompt: the same search as `results`, its words taken from the
    /// message, within `maxCharacters` and plain for Gemma; empty when nothing bears on it.
    /// `excluding`: the open page, already shown in full.
    public func related(to message: String, maxCharacters: Int, ranked: [String] = [], excluding page: UUID? = nil) -> String {
        let terms = Self.terms(message, leavingOut: Self.stopwords).filter { term in
            // A message is sentences, not a query: its everyday words say nothing.
            term.count > 1 || term[0].count <= 3 || !term[0].contains(where: \.isLetter)
                || !CompanionPrompt.keywords(term[0]).isEmpty
        }
        guard !terms.isEmpty || !ranked.isEmpty else { return "" }
        let match = index.match(terms)
        let without = page.flatMap { id in pages.firstIndex { $0.id == id } }
        let hits = pageHits(ranked: ranked, match: match, without: without, limit: 5)
        return Self.assemble(head: [], pages: lines(hits, found: match.found), heading: nil, said: answerLines(match),
                             maxCharacters: maxCharacters)
    }

    /// Every page as "- Name (Type)", those sharing the most words with `focus` first (as
    /// `CompanionPrompt` orders the pages it shows), within `maxCharacters`; when they
    /// don't all fit, it ends "…and 63 more."
    public static func directory(_ pages: [CompanionPrompt.Page], focus: String, maxCharacters: Int) -> String {
        let listed = CompanionPrompt.ordered(pages.filter { !$0.name.isEmpty || !$0.writing.isEmpty }, focus: focus)
        func more(_ count: Int) -> String { "\u{2026}and \(count) more." }
        var lines: [String] = [], used = 0
        for (i, page) in listed.enumerated() {
            let line = CompanionPrompt.listed(page.name, type: page.type)
            let cost = (lines.isEmpty ? 0 : 1) + line.count, left = listed.count - i - 1
            // Room is kept for saying how many are left out.
            guard used + cost + (left > 0 ? 1 + more(left).count : 0) <= maxCharacters else {
                let rest = more(listed.count - i)
                if used + (lines.isEmpty ? 0 : 1) + rest.count <= maxCharacters { lines.append(rest) }
                break
            }
            lines.append(line)
            used += cost
        }
        return lines.joined(separator: "\n")
    }

    // MARK: What a search shows

    /// A page found, and its passages to show (fields or paragraphs, at most two).
    private struct PageHit {
        var page: Int
        var passages: [Int] = []
    }

    /// The page `query` names: its heading, ignoring case, accents and a leading "The"
    /// (the newest, if two have it).
    private func named(_ query: String) -> Int? {
        let name = Self.name(query)
        guard !name.isEmpty else { return nil }
        return pages.indices.filter { Self.name(pages[$0].heading) == name }.max { pages[$0].modified < pages[$1].modified }
    }

    /// "the Kestrel" as a title match compares it: "kestrel".
    private static func name(_ text: String) -> String {
        var words = words(text).map(\.word)
        if words.count > 1, words[0] == "the" { words.removeFirst() }
        return words.joined(separator: " ")
    }

    /// Pages in the order their passages rank, Spotlight's first, then the lexical hits,
    /// up to `limit` pages and two passages each; `without`: a page left out.
    private func pageHits(ranked: [String], match: Index.Match, without: Int?, limit: Int) -> [PageHit] {
        let spotlight = ranked.compactMap { Search.Item(id: $0).flatMap { index.byItem[$0] } }
        var seen = Set<Int>(), hits: [PageHit] = [], at: [Int: Int] = [:]
        for p in spotlight + match.ranked where seen.insert(p).inserted {
            let passage = index.passages[p]
            guard passage.kind != .answer, passage.owner != without else { continue }
            let i: Int
            if let found = at[passage.owner] {
                i = found
            } else {
                guard hits.count < limit else { continue }
                i = hits.count
                at[passage.owner] = i
                hits.append(PageHit(page: passage.owner))
            }
            if passage.kind != .title, hits[i].passages.count < 2 { hits[i].passages.append(p) }
        }
        return hits
    }

    /// Each hit's line with two passages, then with one, for `assemble` to take the first that fits.
    private func lines(_ hits: [PageHit], found: Set<String>) -> [[String]] {
        hits.map { hit in [2, 1].map { line(hit, passages: $0, found: found) } }
    }

    /// "- Name (Type): " and the hit's first `passages`: its matching fields, and each
    /// paragraph cut around the first word found. A page found by its name alone shows its
    /// fields, or how it opens.
    private func line(_ hit: PageHit, passages count: Int, found: Set<String>) -> String {
        let page = pages[hit.page]
        var shown = hit.passages.prefix(count).map { p -> String in
            let passage = index.passages[p]
            guard passage.kind == .fields else {
                return "\u{201C}" + Self.window(page.paragraphs[passage.paragraph].text, found: found) + "\u{201D}"
            }
            let matching = page.fields.filter { Self.words($0).contains { found.contains($0.word) } }
            return Self.window((matching.isEmpty ? page.fields : matching).joined(separator: "; "), found: found)
        }
        if shown.isEmpty {
            if !page.fields.isEmpty {
                shown = [Self.window(page.fields.joined(separator: "; "), found: [])]
            } else if let first = page.paragraphs.first {
                shown = ["\u{201C}" + Self.window(first.text, found: []) + "\u{201D}"]
            }
        }
        return Reasoned.gemmaPlain(CompanionPrompt.listed(page.heading, type: page.type)
            + (shown.isEmpty ? "" : ": " + shown.joined(separator: " ")))
    }

    /// The best two of the author's answers that match.
    private func answerLines(_ match: Index.Match) -> [String] {
        match.ranked.filter { index.passages[$0].kind == .answer }.prefix(2).map { p in
            let answer = answers[index.passages[p].owner]
            return Reasoned.gemmaPlain("They told you, in \(answer.place): \u{201C}\(Self.window(answer.text, found: match.found))\u{201D}")
        }
    }

    /// The page a search names, in at most `maxCharacters`: what it is, its fields, then its
    /// writing (how it opens and its latest part, when long).
    private func describe(_ p: Int, maxCharacters: Int) -> [String] {
        let page = pages[p]
        let kind = page.type.map { type in
            CompanionPrompt.article(type) + " " + CompanionPrompt.lowercasedWord(type) + " page"
        } ?? "one of their pages"
        var lines = [Reasoned.gemmaPlain("\u{201C}\(page.heading)\u{201D}, \(kind):")], used = lines[0].count
        for field in page.fields {
            let line = Reasoned.gemmaPlain(Self.window(field, found: []))
            guard used + 1 + line.count <= maxCharacters else { break }
            lines.append(line)
            used += 1 + line.count
        }
        let writing = Reasoned.gemmaPlain(page.paragraphs.map(\.text).joined(separator: "\n"))
        let room = maxCharacters - used - 1
        if writing.isEmpty {
            if page.fields.isEmpty { lines.append("Nothing is written on it yet.") }
        } else if writing.count <= room {
            lines.append(writing)
        } else if room >= 80, let excerpt = CompanionPrompt.excerpt(writing, maxCharacters: room - 5) {
            lines.append(excerpt)   // the excerpt adds "\n[…]\n" between its parts
        }
        return lines
    }

    /// The tool's text: `head`, then `heading` and as many `pages` as fit (each in the
    /// first of its forms that fits), then `said`, within `maxCharacters`. What the author
    /// told the companion keeps up to a third of the room, so pages can't crowd it out.
    private static func assemble(head: [String], pages: [[String]], heading: String?, said: [String],
                                 maxCharacters: Int) -> String {
        var kept: [String] = [], reserved = 0
        for line in said where reserved + line.count + 1 <= maxCharacters / 3 {
            kept.append(line)
            reserved += line.count + 1
        }
        let room = maxCharacters - reserved
        var lines: [String] = [], used = -1   // a line break before every line but the first
        for line in head where used + 1 + line.count <= room {
            lines.append(line)
            used += 1 + line.count
        }
        let heading = heading.map(Reasoned.gemmaPlain)
        var found: [String] = [], usedWithPages = used + (heading.map { 1 + $0.count } ?? 0)
        for forms in pages {
            guard let line = forms.first(where: { usedWithPages + 1 + $0.count <= room }) else { continue }
            found.append(line)
            usedWithPages += 1 + line.count
        }
        if !found.isEmpty { lines += (heading.map { [$0] } ?? []) + found }
        return (lines + kept).joined(separator: "\n")
    }

    // MARK: Words

    /// Words too common to search for. Short on purpose: names like "Ana" or "Kai" are
    /// short words too.
    static let stopwords: Set<String> = [
        "a", "about", "an", "and", "are", "as", "at", "be", "been", "but", "by", "did", "do", "does", "for", "from",
        "he", "her", "him", "his", "how", "i", "in", "is", "it", "its", "me", "my", "of", "on", "or", "our", "she",
        "that", "the", "their", "them", "these", "they", "this", "those", "to", "was", "we", "were", "what", "when",
        "where", "which", "who", "whom", "whose", "why", "with", "you", "your",
    ]

    /// What `query` looks for: its terms (`Search.terms`: words, "quoted phrases" whole),
    /// each as its folded words; single words in `leavingOut` are left out, unless that
    /// would leave nothing.
    static func terms(_ query: String, leavingOut stopwords: Set<String>) -> [[String]] {
        var all: [[String]] = []
        for term in Search.terms(query).map({ words($0).map(\.word) }) where !term.isEmpty && !all.contains(term) {
            all.append(term)
        }
        let kept = all.filter { $0.count > 1 || !stopwords.contains($0[0]) }
        return kept.isEmpty ? all : kept
    }

    /// The words of `text`, each folded (`fold`) and where it is.
    static func words(_ text: String) -> [(word: String, range: Range<String.Index>)] {
        var words: [(word: String, range: Range<String.Index>)] = [], start: String.Index?
        func finish(_ end: String.Index) {
            guard let from = start else { return }
            start = nil
            let word = fold(text[from..<end])
            if !word.isEmpty { words.append((word, from..<end)) }
        }
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if c.isLetter || c.isNumber || (start != nil && (c == "'" || c == "\u{2019}")) {
                if start == nil { start = i }
            } else {
                finish(i)
            }
            i = text.index(after: i)
        }
        finish(text.endIndex)
        return words
    }

    /// A word as search compares it: lower case, without accents or a possessive "'s".
    static func fold(_ word: Substring) -> String {
        var word = word.allSatisfy(\.isASCII) ? word.lowercased()
            : String(word).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
                .replacingOccurrences(of: "\u{2019}", with: "'")
        if word.hasSuffix("'s") { word.removeLast(2) }
        while word.hasSuffix("'") { word.removeLast() }
        return word
    }

    /// About `size` characters of `text`, on one line, from a little before the first word
    /// in `found` (from its start when none is), cut at words with "…" where it's cut.
    static func window(_ text: String, found: Set<String>, size: Int = 240) -> String {
        let text = CompanionPrompt.oneLine(text)
        guard text.count > size else { return text }
        let match = found.isEmpty ? nil : words(text).first { found.contains($0.word) }?.range
        var start = match.map { text.index($0.lowerBound, offsetBy: -(size / 4), limitedBy: text.startIndex) ?? text.startIndex }
            ?? text.startIndex
        var end = text.index(start, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
        if end == text.endIndex { start = text.index(end, offsetBy: -size, limitedBy: text.startIndex) ?? text.startIndex }
        // The start moves on to a word's beginning, the end back to a word's end, never past the match.
        if start > text.startIndex, text[text.index(before: start)] != " ",
           let space = text[start...].firstIndex(of: " "), space < (match?.lowerBound ?? end) {
            start = text.index(after: space)
        }
        if end < text.endIndex, text[end] != " ", let space = text[start..<end].lastIndex(of: " "),
           space >= (match?.upperBound ?? start) {
            end = space
        }
        return (start > text.startIndex ? "\u{2026}" : "") + text[start..<end].trimmingCharacters(in: .whitespaces)
            + (end < text.endIndex ? "\u{2026}" : "")
    }
}

// MARK: - The lexical index

extension PageLookup {
    /// Every passage of the snapshot (titles, fields, paragraphs and answers) by its words,
    /// for ranking by words: whole words and the longer words they begin, weighted by how
    /// rare they are in the world (idf).
    struct Index: Sendable {
        struct Passage: Sendable {
            /// In the order ties go: title, then fields, then paragraph, then an answer.
            enum Kind: Comparable, Sendable { case title, fields, paragraph, answer }

            var kind: Kind
            /// The page's index; for an answer, the answer's.
            var owner: Int
            /// For a paragraph, its index in the page's paragraphs.
            var paragraph: Int
            var words: [String]
            var date: Date
        }

        /// What a search found: the passages that match, best first, and the words that
        /// matched (to show the passages from).
        struct Match {
            var ranked: [Int]
            var found: Set<String>
        }

        var passages: [Passage] = []
        /// Each page's passages but its title, with what was said in its conversation.
        var belonging: [Int: [Int]] = [:]
        var byItem: [Search.Item: Int] = [:]
        /// The passages holding each word, ascending.
        var postings: [String: [Int]] = [:]
        /// Every word, sorted by its UTF-8 bytes, so the words a prefix begins are together.
        var vocabulary: [String] = []

        init(pages: [Page], answers: [Answer]) {
            var pageAt: [UUID: Int] = [:]
            func add(_ kind: Passage.Kind, owner: Int, paragraph: Int = 0, text: String, date: Date, item: Search.Item?) {
                let p = passages.count
                passages.append(Passage(kind: kind, owner: owner, paragraph: paragraph, words: PageLookup.words(text).map(\.word),
                                        date: date))
                if let item, byItem[item] == nil { byItem[item] = p }
                if kind == .fields || kind == .paragraph { belonging[owner, default: []].append(p) }
            }
            for (i, page) in pages.enumerated() {
                if pageAt[page.id] == nil { pageAt[page.id] = i }
                if !page.heading.isEmpty {
                    add(.title, owner: i, text: page.heading, date: page.modified, item: Search.Item(page: page.id, part: .title))
                }
                if !page.fields.isEmpty {
                    add(.fields, owner: i, text: page.fields.joined(separator: "\n"), date: page.modified,
                        item: Search.Item(page: page.id, part: .fields))
                }
                for (j, paragraph) in page.paragraphs.enumerated() {
                    add(.paragraph, owner: i, paragraph: j, text: paragraph.text, date: page.modified,
                        item: Search.Item(page: page.id, part: .paragraph(paragraph.id)))
                }
            }
            for (i, answer) in answers.enumerated() {
                add(.answer, owner: i, text: answer.text, date: answer.date, item: nil)
                if let page = answer.page.flatMap({ pageAt[$0] }) { belonging[page, default: []].append(passages.count - 1) }
            }
            for (p, passage) in passages.enumerated() {
                for word in passage.words where postings[word]?.last != p { postings[word, default: []].append(p) }
            }
            vocabulary = postings.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        }

        /// The passages that match `terms`, best first. A term counts its idf for a whole
        /// word (or a plural's singular: "tolls" finds "toll"), 0.6 of it for a longer word
        /// it begins ("oar" finds "oars"); a phrase's words have to come in order. A page's
        /// title matching counts half on its other passages that don't. Ties go title,
        /// fields, paragraph, answer, then newer.
        func match(_ terms: [[String]]) -> Match {
            var scores: [Int: Double] = [:], found = Set<String>()
            for term in terms {
                let forms = term.map(matches)
                var weights: [Int: Double] = [:]
                if forms.count == 1 {
                    for (word, weight) in forms[0] {
                        for p in postings[word] ?? [] { weights[p] = max(weights[p] ?? 0, weight) }
                    }
                } else {
                    let holding = forms.map { Set($0.keys.flatMap { postings[$0] ?? [] }) }
                    for p in holding.dropFirst().reduce(holding[0], { $0.intersection($1) }) {
                        let words = passages[p].words
                        guard words.count >= forms.count else { continue }
                        for start in 0...(words.count - forms.count) {
                            let each = forms.indices.compactMap { forms[$0][words[start + $0]] }
                            if each.count == forms.count { weights[p] = max(weights[p] ?? 0, each.min()!) }
                        }
                    }
                }
                guard !weights.isEmpty else { continue }
                found.formUnion(forms.flatMap(\.keys))
                let idf = log(1 + Double(passages.count) / Double(weights.count))
                for (p, weight) in weights {
                    scores[p, default: 0] += weight * idf
                    guard passages[p].kind == .title else { continue }
                    for q in belonging[passages[p].owner] ?? [] where weights[q] == nil { scores[q, default: 0] += weight * idf / 2 }
                }
            }
            let ranked = scores.keys.sorted { a, b in
                let (x, y) = (passages[a], passages[b])
                if scores[a]! != scores[b]! { return scores[a]! > scores[b]! }
                if x.kind != y.kind { return x.kind < y.kind }
                if x.date != y.date { return x.date > y.date }
                return a < b
            }
            return Match(ranked: ranked, found: found)
        }

        /// The words in the world that count as `word`, with their weight.
        private func matches(_ word: String) -> [String: Double] {
            var forms = [word], prefixes = [word]
            if word.count >= 4, word.hasSuffix("s"), !word.hasSuffix("ss") {
                forms.append(String(word.dropLast()))
                prefixes.append(String(word.dropLast()))
            }
            if word.count >= 5, word.hasSuffix("es") { forms.append(String(word.dropLast(2))) }
            if word.count >= 5, word.hasSuffix("ies") { forms.append(word.dropLast(3) + "y") }
            var weights: [String: Double] = [:]
            for prefix in prefixes where prefix.count >= 3 {
                var i = lowerBound(prefix)
                while i < vocabulary.count, vocabulary[i].utf8.starts(with: prefix.utf8) {
                    weights[vocabulary[i]] = 0.6
                    i += 1
                }
            }
            for form in forms where postings[form] != nil { weights[form] = 1 }
            return weights
        }

        /// Where `word` is, or would be, in `vocabulary`.
        private func lowerBound(_ word: String) -> Int {
            var low = 0, high = vocabulary.count
            while low < high {
                let mid = (low + high) / 2
                if vocabulary[mid].utf8.lexicographicallyPrecedes(word.utf8) { low = mid + 1 } else { high = mid }
            }
            return low
        }
    }
}
