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
        /// The matching paragraph; nil when the title or a field matched.
        let paragraph: UUID?
    }

    private static let index = CSSearchableIndex.default()
    private static var ready: Task<Void, Never>?

    /// When a world opens: the index holds its pages only, so search (in the
    /// app and the system's) stays within the open world.
    /// `pages` come with their fields' text ("Species: Elf").
    static func start(with pages: [(WriterCore.Document, String)]) {
        if ready == nil { CSUserQuery.prepare() }
        let items = pages.flatMap { page, fields in Self.items(page, fields: fields) }
        ready = Task {
            try? await index.deleteAllSearchableItems()
            try? await index.indexSearchableItems(items)
        }
    }

    static func update(_ page: WriterCore.Document, fields: String) {
        index.deleteSearchableItems(withDomainIdentifiers: [page.id.uuidString]) { _ in
            index.indexSearchableItems(items(page, fields: fields))
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
                    suggestions.append(plain(suggestion.suggestion.localizedAttributedSuggestion))
                @unknown default:
                    continue
                }
                update(results, suggestions)
            }
        } catch {}   // no results is the honest answer when Spotlight can't search
    }

    private static func plain(_ s: AttributedString) -> String { String(s.characters) }
    private static func plain(_ s: NSAttributedString) -> String { s.string }

    /// The title, the field values, then each paragraph, as items of the page's domain.
    private static func items(_ page: WriterCore.Document, fields: String) -> [CSSearchableItem] {
        let title = page.title.trimmingCharacters(in: .whitespaces)
        let passages = (title.isEmpty ? [] : [("title", title)]) + (fields.isEmpty ? [] : [("fields", fields)])
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
