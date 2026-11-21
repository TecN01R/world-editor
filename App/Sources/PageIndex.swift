import CoreSpotlight
import WriterCore

/// Pages in the phone's private, on-device Spotlight index, so search can
/// match by meaning as well as by words ("the lighthouse keeper" finds Mara).
/// The index never leaves the device; results are always the author's own
/// pages, never generated text (docs/ai-charter.md, "Search and curation").
/// Pages also show up in the system's Spotlight search, and open here.
enum PageIndex {
    private static let index = CSSearchableIndex(name: "pages")

    /// Once at launch: readies Spotlight and indexes every page afresh.
    static func start(with pages: [WriterCore.Document]) {
        CSUserQuery.prepare()
        Task {
            try? await index.deleteAllSearchableItems()
            try? await index.indexSearchableItems(pages.map(item))
        }
    }

    static func update(_ page: WriterCore.Document) {
        index.indexSearchableItems([item(page)])
    }

    static func remove(_ id: UUID) {
        index.deleteSearchableItems(withIdentifiers: [id.uuidString])
    }

    /// Pages matching `text` by meaning or words, best first.
    static func search(_ text: String) async -> [UUID] {
        let context = CSUserQueryContext()
        context.fetchAttributes = ["title"]
        context.enableRankedResults = true
        context.maxResultCount = 20
        var ids: [UUID] = []
        do {
            for try await response in CSUserQuery(userQueryString: text, userQueryContext: context).responses {
                if case .item(let result) = response, let id = UUID(uuidString: result.item.uniqueIdentifier) {
                    ids.append(id)
                }
            }
        } catch {}   // no results is the honest answer when Spotlight can't search
        return ids
    }

    private static func item(_ page: WriterCore.Document) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = page.heading
        attributes.textContent = ([page.title] + page.paragraphs.map(\.text)).joined(separator: "\n")
        attributes.contentModificationDate = page.modified
        return CSSearchableItem(uniqueIdentifier: page.id.uuidString, domainIdentifier: "page", attributeSet: attributes)
    }
}
