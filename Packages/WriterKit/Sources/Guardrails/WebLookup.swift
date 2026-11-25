import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import WriterCore

/// The companion's look-ups of the real world, its `look_up` tool (Kevin, 2026-11-25: "go
/// for it with the web stuff"; docs/companion-roadmap.md, step 1): English Wikipedia's search,
/// with no account or key. For a query it returns the articles that best match, numbered, for
/// the model to answer from: the two best read whole, each as it opens and the paragraphs that
/// best answer the query, and the third's passage that matched; and the articles as sources
/// for the line under its reply. The same code runs in the app and the
///
/// Only the query leaves the phone, and never a name from the writer's pages: a query that
/// names one is answered from here, without asking Wikipedia (`theirs`).
public enum WebLookup {
    public static let toolName = "look_up"
    public static let toolDescription = "Looks up the real world on Wikipedia: history, science, places, people, how things "
        + "work. Returns passages from the articles it finds. Not for the writer's own world: their names and inventions "
        + "aren't there."
    /// The guide of its one argument, `query`.
    public static let queryGuide = "A few words naming the real-world thing to look up"
    /// Look-ups allowed in one reply; the next gets `lastLookUp`.
    public static let lookupsPerReply = 2
    /// The most a look-up returns.
    public static let maxCharacters = 3000
    /// The most of an article's opening it returns.
    static let openingCharacters = 400
    public static let needsQuery = "look_up needs a few words to look for."
    public static let lastLookUp = "That's the last look-up for this reply: answer from what you found."
    public static let unreachable = "Wikipedia couldn't be reached just now: answer from what you know, and say you couldn't check it."

    public static func theirs(_ name: String) -> String {
        "\u{201C}\(name)\u{201D} is from their pages, and look_up is for the real world only, so nothing was looked up. "
            + "What their pages say about it is theirs (search_pages)."
    }

    public static func nothingFound(_ query: String) -> String {
        "Wikipedia has nothing on \u{201C}\(CompanionPrompt.oneLine(query, maxCharacters: 80))\u{201D}."
    }

    // MARK: Keeping their world private

    /// The names in their world that a look-up never sends: their pages' names, and every word
    /// they wrote with a capital inside a sentence, on their pages, in what they told the
    /// companion before (`pages`) and in `said` (this conversation), unless `known` says it's a
    /// word of the language (a real place's name, say; the phone's dictionary). The model is
    /// places now and then (2026-11-25): this makes sure they stay on the phone.
    public static func theirNames(pages: PageLookup?, said: [String] = [], known: (String) -> Bool = { _ in false }) -> [String] {
        let all: [PageLookup.Page] = pages?.pages ?? []
        let headings: [String] = all.map(\.heading).filter { !$0.isEmpty }
        var texts: [String] = said
        for page in all { texts += page.fields + page.paragraphs.map { $0.text } }
        for answer in pages?.answers ?? [] { texts.append(answer.text) }
        let edges: CharacterSet = CharacterSet.punctuationCharacters.union(CharacterSet.symbols)
        var named = Set<String>()
        for text in texts {
            var sentenceStart = true
            for token in text.split(whereSeparator: { $0.isWhitespace }) {
                let word: String = token.trimmingCharacters(in: edges)
                if !sentenceStart, let first = word.first, first.isUppercase, word.count >= 3, !known(word) { named.insert(word) }
                sentenceStart = token.last.map { ".!?:\u{2026}".contains($0) } ?? false
            }
        }
        return headings + named.sorted()
    }

    /// The name of theirs (`names`, from `theirNames`) that `query` contains, if any: whole
    /// words, any case. Such a query is never sent.
    public static func theirName(in query: String, names: [String]) -> String? {
        let words = PageLookup.words(query).map(\.word)
        return names.first { name in
            let named = PageLookup.words(name).map(\.word)
            guard !named.isEmpty, named.count <= words.count else { return false }
            return (0...(words.count - named.count)).contains { Array(words[$0..<$0 + named.count]) == named }
        }
    }

    // MARK: Asking Wikipedia

    static let api = "https://en.wikipedia.org/w/api.php"
    /// Wikimedia's User-Agent policy asks a client to name itself with a contact, and gives
    /// one that does 200 requests a minute where one that doesn't gets 10 (2026). The contact
    /// is the app's public repository, nothing of the writer's (Kevin, 2026-11-25).
    static let userAgent = "WorldEditor/0.1 (https://github.com/TecN01R/world-editor)"

    /// The three articles that best match `query`, with the passage that matched in each.
    static func searchURL(_ query: String) -> URL {
        url(["action": "query", "list": "search", "srsearch": query, "srlimit": "3", "srprop": "snippet"])
    }

    /// An article's whole text, as plain text, and its address.
    static func articleURL(_ title: String) -> URL {
        url(["action": "query", "prop": "extracts|info", "explaintext": "1", "exsectionformat": "plain",
             "inprop": "url", "redirects": "1", "titles": title])
    }

    private static func url(_ items: [String: String]) -> URL {
        var parts = URLComponents(string: api)!
        parts.queryItems = (["format": "json", "formatversion": "2"].merging(items) { $1 })
            .sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return parts.url!
    }

    /// An article the search found.
    struct Hit: Equatable {
        var title: String
        /// The passage that matched, as plain text.
        var passage: String
    }

    /// An article's text and address.
    struct Article: Equatable {
        var text: String
        var url: URL
    }

    static func hits(_ data: Data) throws -> [Hit] {
        struct Response: Decodable {
            struct Query: Decodable { let search: [Result] }
            struct Result: Decodable { let title: String; let snippet: String? }
            let query: Query?
        }
        return (try JSONDecoder().decode(Response.self, from: data).query?.search ?? []).map {
            Hit(title: $0.title, passage: plain($0.snippet ?? ""))
        }
    }

    /// The one article asked for, if Wikipedia has it.
    static func article(_ data: Data) throws -> Article? {
        struct Response: Decodable {
            struct Query: Decodable { let pages: [Page]? }
            struct Page: Decodable { let extract: String?; let fullurl: String? }
            let query: Query?
        }
        guard let page = try JSONDecoder().decode(Response.self, from: data).query?.pages?.first,
              let text = page.extract, let address = page.fullurl.flatMap(URL.init(string:)) else { return nil }
        return Article(text: text, url: address)
    }

    /// An article's address on Wikipedia, from its title.
    static func address(_ title: String) -> URL {
        let path = title.replacingOccurrences(of: " ", with: "_")
        return URL(string: "https://en.wikipedia.org/wiki/" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path))!
    }

    /// A search passage as plain text: Wikipedia marks the matching words in HTML.
    static func plain(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, character) in [("&quot;", "\""), ("&#039;", "'"), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The tool's text for `query`, numbered by article: for each article read (`articles`, by
    /// title), how it opens and the paragraphs that best answer the query (`passages`; the
    /// search's passage where none does); for the others, the search's passage. Plain for
    /// alone too often lacked the answer (2026-11-25).
    static func answer(_ query: String, hits: [Hit], articles: [String: Article]) -> (text: String, found: LookedUp) {
        var parts: [String] = [], sources: [LookedUp.Source] = []
        for hit in hits {
            var part = "[\(sources.count + 1)] \(hit.title)"
            if let article = articles[hit.title] {
                let opening = opening(article.text)
                if !opening.isEmpty { part += ": " + opening }
                var found = passages(article.text, query: query)
                if found.isEmpty, !hit.passage.isEmpty, !repeats(hit.passage, opening) { found = ["\u{2026}\(hit.passage)\u{2026}"] }
                part += found.map { "\n   " + $0 }.joined()
            } else if !hit.passage.isEmpty {
                part += ": \u{2026}\(hit.passage)\u{2026}"
            }
            parts.append(part)
            sources.append(LookedUp.Source(title: hit.title, url: articles[hit.title]?.url ?? address(hit.title)))
        }
        let found = LookedUp(query: query, sources: sources)
        guard !parts.isEmpty else { return (Reasoned.gemmaPlain(nothingFound(query)), found) }
        var text = "From Wikipedia, for \u{201C}\(CompanionPrompt.oneLine(query, maxCharacters: 80))\u{201D}:"
        for part in parts {
            guard text.count + part.count + 2 <= maxCharacters else { break }
            text += "\n\n" + part
        }
        return (Reasoned.gemmaPlain(text), found)
    }

    /// Most of `passage`'s words are in `opening` already (the search's passage is often the
    /// article's first lines, written a little differently).
    static func repeats(_ passage: String, _ opening: String) -> Bool {
        let words = Set(PageLookup.words(opening).map(\.word)), said = PageLookup.words(passage).map(\.word)
        guard !said.isEmpty else { return true }
        return Double(said.filter(words.contains).count) / Double(said.count) >= 0.6
    }

    /// The paragraphs of an article (after its first) that best answer `query`: those with the
    /// most of its words (a word's singular or plural counts), at least half of them, up to
    /// `count`, in the article's order, each cut to `passageCharacters` from the sentence where
    /// its first match is.
    static func passages(_ text: String, query: String, count: Int = 2) -> [String] {
        let terms = PageLookup.terms(query, leavingOut: PageLookup.stopwords).map { term in
            term.count == 1 ? [[term[0]] + PageLookup.numberForms(term[0])] : term.map { [$0] }
        }
        guard !terms.isEmpty else { return [] }
        let paragraphs = Array(paragraphs(text).dropFirst())
        var scored: [(index: Int, score: Int, first: String.Index)] = []
        for (index, paragraph) in paragraphs.enumerated() {
            let words = PageLookup.words(paragraph)
            let present = Set(words.map(\.word))
            let matched = terms.filter { term in term.allSatisfy { forms in forms.contains(where: present.contains) } }
            guard matched.count * 2 >= terms.count,
                  let first = words.first(where: { word in matched.contains { $0.contains { $0.contains(word.word) } } })
            else { continue }
            scored.append((index, matched.count, first.range.lowerBound))
        }
        return scored.sorted { ($0.score, -$0.index) > ($1.score, -$1.index) }.prefix(count).sorted { $0.index < $1.index }
            .map { cut(paragraphs[$0.index], from: $0.first) }
    }

    static let passageCharacters = 600

    /// An article's paragraphs that have something to say (not its section headings).
    private static func paragraphs(_ text: String) -> [String] {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count >= 60 }
    }

    /// `paragraph` from the start of the sentence `match` is in, to `passageCharacters`, cut at a word.
    private static func cut(_ paragraph: String, from match: String.Index) -> String {
        guard paragraph.count > passageCharacters else { return paragraph }
        let before = paragraph[..<match]
        let start = before.range(of: ". ", options: .backwards)?.upperBound ?? paragraph.startIndex
        var piece = paragraph[start...]
        var cutEnd = false
        if piece.count > passageCharacters {
            piece = piece.prefix(passageCharacters)
            piece = piece[..<(piece.lastIndex(where: \.isWhitespace) ?? piece.endIndex)]
            cutEnd = true
        }
        return (start > paragraph.startIndex ? "\u{2026}" : "") + piece + (cutEnd ? "\u{2026}" : "")
    }

    /// How an article opens (its first paragraph), up to `openingCharacters`: whole sentences
    /// where they fit, otherwise cut at a word.
    static func opening(_ text: String) -> String {
        let text = paragraphs(text).first ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > openingCharacters else { return text }
        let head = text.prefix(openingCharacters)
        if let end = head.range(of: ". ", options: .backwards), end.lowerBound > head.startIndex {
            return String(head[...end.lowerBound])
        }
        return String(head[..<(head.lastIndex(where: \.isWhitespace) ?? head.endIndex)]) + "\u{2026}"
    }

    /// Looks `query` up: the search, then the text of the two articles that best match it.
    public static func lookUp(_ query: String, session: URLSession = .shared) async throws -> (text: String, found: LookedUp) {
        let hits = try Self.hits(try await get(searchURL(query), session))
        var articles: [String: Article] = [:]
        for hit in hits.prefix(2) {
            articles[hit.title] = try Self.article(try await get(articleURL(hit.title), session))
        }
        return answer(query, hits: hits, articles: articles)
    }

    /// Asks again if Wikipedia is busy (it turns away bursts of requests) or the connection
    /// drops: after a second, then after three (or as long as Wikipedia asks, up to five).
    private static func get(_ url: URL, _ session: URLSession) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for wait in [1.0, 3.0, nil] {
            var pause = wait
            do {
                let (data, response) = try await session.data(for: request)
                let http = response as? HTTPURLResponse
                if http?.statusCode == 200 { return data }
                if let asked = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init), let wait { pause = min(max(asked, wait), 5) }
            } catch let error as URLError where error.code != .cancelled && wait != nil {
            }
            guard let pause else { break }
            try await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
        }
        throw URLError(.badServerResponse)
    }
}

/// them: `search_pages` (with `pages`), `look_up` (when looking up is on) and `add_instruction`
/// (when instructing), each within its budget for the reply. It never fails: what goes wrong is
/// told to the model in a sentence.
public struct ReplyTools: Sendable {
    /// What the model is offered, in the order the prompt declares them.
    public let offered: [GemmaChat.Tool]
    private var searches: PageLookup.Searches?
    private let pages: PageLookup?
    /// Their names, which a look-up never sends.
    private let names: [String]
    private var lookupsMade = 0
    /// What it looked up, and found, in order: what was sent to Wikipedia.
    public private(set) var lookups: [LookedUp] = []
    /// The instructions it added to the writer's, in order (`Instructions`).
    public private(set) var instructions: [String] = []

    /// - Parameter listing: `list_pages` is offered too (the plain model, which isn't shown their pages).
    /// - Parameter instructing: `add_instruction` is offered too.
    /// - Parameter theirNames: what a look-up never sends (`WebLookup.theirNames`; by default
    ///   their pages' names and the names they wrote, none taken as words of the language).
    public init(pages: PageLookup?, lookingUp: Bool, listing: Bool = false, instructing: Bool = false, theirNames: [String]? = nil) {
        self.pages = pages
        searches = pages.map(PageLookup.Searches.init)
        names = theirNames ?? WebLookup.theirNames(pages: pages)
        offered = (pages == nil ? [] : (listing ? [GemmaChat.listPages] : []) + [GemmaChat.searchPages])
            + (lookingUp ? [GemmaChat.lookUp] : []) + (instructing ? [GemmaChat.addInstruction] : [])
    }

    /// What it searched their pages for, in order.
    public var queries: [String] { searches?.queries ?? [] }

    /// The answer to the model's call of `tool` with `query`. `lookUp` asks Wikipedia
    public mutating func answer(_ tool: String, query: String?,
                                lookUp: (String) async throws -> (text: String, found: LookedUp)) async -> String {
        guard offered.contains(where: { $0.name == tool }) else { return "Tool not found: \(tool)" }
        if tool == PageLookup.listToolName { return pages?.list(query) ?? "Tool not found: \(tool)" }
        if tool == Instructions.toolName { return addInstruction(query) }
        guard tool == WebLookup.toolName else { return searches?.answer(tool, query: query) ?? "Tool not found: \(tool)" }
        let query = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return WebLookup.needsQuery }
        lookupsMade += 1
        guard lookupsMade <= WebLookup.lookupsPerReply else { return WebLookup.lastLookUp }
        if let name = WebLookup.theirName(in: query, names: names) { return Reasoned.gemmaPlain(WebLookup.theirs(name)) }
        do {
            let (text, found) = try await lookUp(query)
            lookups.append(found)
            return text
        } catch {
            return WebLookup.unreachable
        }
    }

    /// Keeps `text` as an instruction to add, up to `Instructions.perReply` a reply.
    private mutating func addInstruction(_ text: String?) -> String {
        let text = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return Instructions.needsInstruction }
        guard instructions.count < Instructions.perReply else { return Instructions.lastOne }
        instructions.append(text)
        return Instructions.added
    }
}
