import CoreSpotlight
import OSLog
import WriterCore

/// Search is Spotlight's: pages live in the phone's private, on-device index,
/// and iOS 27's Spotlight finds and ranks them by words and meaning (Apple
/// Intelligence where it's on). Each title and paragraph is its own item, so
/// a result is the passage that matched. The index never leaves the device;
/// results are always the author's own text, never generated text
/// (docs/ai-charter.md, "Search and curation"). Pages also show up in the
/// system's Spotlight search, and open here.
enum PageIndex {
    struct Result {
        let page: UUID
        /// The matching paragraph; nil when the title matched.
        let paragraph: UUID?
    }

    private static let index = CSSearchableIndex.default()
    /// Each step, so CI's log shows whether indexing or searching stalls.
    private static let log = Logger(subsystem: "world-editor", category: "search")
    private static var ready: Task<Void, Never>?

    /// Once at launch: readies Spotlight and indexes every page (items with
    /// the same identifier replace the old ones; deleted pages are removed as
    /// they're deleted).
    static func start(with pages: [WriterCore.Document]) {
        CSUserQuery.prepare()
        log.notice("prepared")
        ready = Task {
            log.notice("indexing \(pages.count) pages")
            do {
                try await index.indexSearchableItems(pages.flatMap(items))
                log.notice("indexed")
            } catch {
                log.error("indexing failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func update(_ page: WriterCore.Document) {
        index.deleteSearchableItems(withDomainIdentifiers: [page.id.uuidString]) { _ in
            index.indexSearchableItems(items(page))
        }
    }

    static func remove(_ id: UUID) {
        index.deleteSearchableItems(withDomainIdentifiers: [id.uuidString])
    }

    /// Spotlight's ranked results for `text`, best first, one per page, and
    /// its suggested completions, passed to `update` as each arrives.
    @MainActor
    static func search(_ text: String, update: ([Result], [String]) -> Void) async {
        await ready?.value
        log.notice("searching")
        let context = CSUserQueryContext()
        context.fetchAttributes = ["title"]
        context.enableRankedResults = true
        context.maxResultCount = 50
        context.maxSuggestionCount = 4
        var results: [Result] = [], suggestions: [String] = []
        do {
            for try await response in CSUserQuery(userQueryString: text, userQueryContext: context).responses {
                switch response {
                case .item(let found):
                    log.notice("result: \(found.item.uniqueIdentifier, privacy: .public)")
                    let parts = found.item.uniqueIdentifier.split(separator: "/").map(String.init)
                    guard let page = parts.first.flatMap(UUID.init), !results.contains(where: { $0.page == page }) else { continue }
                    results.append(Result(page: page, paragraph: parts.dropFirst().first.flatMap(UUID.init)))
                case .suggestion(let suggestion):
                    log.notice("suggestion")
                    suggestions.append(plain(suggestion.suggestion.localizedAttributedSuggestion))
                @unknown default:
                    continue
                }
                update(results, suggestions)
            }
            log.notice("search finished: \(results.count) results")
        } catch {
            log.error("search failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func plain(_ s: AttributedString) -> String { String(s.characters) }
    private static func plain(_ s: NSAttributedString) -> String { s.string }

    /// The title, then each paragraph, as items of the page's domain.
    private static func items(_ page: WriterCore.Document) -> [CSSearchableItem] {
        let title = page.title.trimmingCharacters(in: .whitespaces)
        let passages = (title.isEmpty ? [] : [("title", title)])
            + page.paragraphs.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.map { ($0.id.uuidString, $0.text) }
        return passages.map { id, text in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = page.heading
            attributes.textContent = text
            attributes.contentModificationDate = page.modified
            return CSSearchableItem(uniqueIdentifier: "\(page.id.uuidString)/\(id)",
                                    domainIdentifier: page.id.uuidString, attributeSet: attributes)
        }
    }
}
