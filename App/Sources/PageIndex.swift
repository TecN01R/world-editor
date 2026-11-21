import CoreSpotlight
import WriterCore

/// Pages in the phone's private, on-device Spotlight index, so search can
/// match by meaning as well as by words ("the lighthouse keeper" finds Mara),
/// paragraph by paragraph so a result is the passage that matched.
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

    /// Passages matching `text` by meaning or words, best first, at most one per page.
    static func search(_ text: String) async -> [(page: UUID, paragraph: UUID)] {
        let context = CSUserQueryContext()
        context.fetchAttributes = ["title"]
        context.enableRankedResults = true
        context.maxResultCount = 40
        var found: [(page: UUID, paragraph: UUID)] = []
        do {
            for try await response in CSUserQuery(userQueryString: text, userQueryContext: context).responses {
                guard case .item(let result) = response else { continue }
                let ids = result.item.uniqueIdentifier.split(separator: "/").compactMap { UUID(uuidString: String($0)) }
                if ids.count == 2, !found.contains(where: { $0.page == ids[0] }) { found.append((ids[0], ids[1])) }
            }
        } catch {}   // no results is the honest answer when Spotlight can't search
        return found
    }

    /// One item per paragraph, so a match points at the passage, not just the page.
    private static func items(_ page: WriterCore.Document) -> [CSSearchableItem] {
        page.paragraphs.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.map { p in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = page.heading
            attributes.textContent = p.text
            attributes.contentModificationDate = page.modified
            return CSSearchableItem(uniqueIdentifier: "\(page.id.uuidString)/\(p.id.uuidString)",
                                    domainIdentifier: page.id.uuidString, attributeSet: attributes)
        }
    }
}
