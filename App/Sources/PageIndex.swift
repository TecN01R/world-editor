import CoreSpotlight
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

    private static let index = CSSearchableIndex(name: "pages")
    private static var ready: Task<Void, Never>?

    /// Once at launch: readies Spotlight and indexes every page afresh.
    static func start(with pages: [WriterCore.Document]) {
        CSUserQuery.prepare()
        ready = Task {
            try? await index.deleteAllSearchableItems()
            try? await index.indexSearchableItems(pages.flatMap(items))
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
    /// its suggested completions.
    static func search(_ text: String) async -> (results: [Result], suggestions: [String]) {
        await ready?.value
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
                    let parts = found.item.uniqueIdentifier.split(separator: "/").map(String.init)
                    guard let page = parts.first.flatMap(UUID.init), !results.contains(where: { $0.page == page }) else { continue }
                    results.append(Result(page: page, paragraph: parts.dropFirst().first.flatMap(UUID.init)))
                case .suggestion(let suggestion):
                    suggestions.append(text(suggestion.suggestion.localizedAttributedSuggestion))
                @unknown default:
                    continue
                }
            }
        } catch {}   // no results is the honest answer when Spotlight can't search
        return (results, suggestions)
    }

    private static func text(_ s: AttributedString) -> String { String(s.characters) }
    private static func text(_ s: NSAttributedString) -> String { s.string }

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
