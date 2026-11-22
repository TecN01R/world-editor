import SwiftUI
import WriterCore

@main
struct WorldEditorApp: App {
    @State private var library = Library()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
        }
        .onChange(of: phase) { _, phase in
            if phase != .active { library.flushAll() }   // never lose the last edits
            else { library.removeExpired() }   // the app may stay open past a page's 30 days
        }
    }
}

/// All pages, the one that's open, and saving shortly after each edit.
@MainActor @Observable
final class Library {
    /// Most recently edited first.
    private(set) var pages: [WriterCore.Document] = []
    /// Deleted pages, newest first, kept for 30 days so a delete can be undone.
    /// Apart from `pages`, so nothing else (search, @ links, fields) sees them.
    private(set) var recentlyDeleted: [WriterCore.Document] = []

    /// The open page. Leaving a page that was never written in discards it.
    var selection: UUID? {
        didSet {
            guard oldValue != selection else { return }
            cursor = selection.flatMap(searchCursor) ?? (0, 0)
            if let old = oldValue { flush(old); discardIfEmpty(old) }
        }
    }

    /// Caret position shared by both editors so switching modes keeps your place.
    var cursor = (paragraph: 0, offset: 0)
    /// The pages list's search, so a result opens at its match, not the top.
    var searchQuery = Screenshots.searchQuery ?? ""
    /// Spotlight's results for it, best first, and its suggested completions.
    var searchResults: [PageIndex.Result] = []
    var searchSuggestions: [String] = []

    private func searchCursor(_ id: UUID) -> (paragraph: Int, offset: Int)? {
        guard !searchQuery.isEmpty, let page = pages.first(where: { $0.id == id }),
              let passage = searchResults.first(where: { $0.page == id })?.paragraph,
              let i = page.paragraphs.firstIndex(where: { $0.id == passage }) else { return nil }
        return (i, page.offset(of: searchQuery, inParagraph: i) ?? 0)
    }

    /// A sheet or alert the page's fields asked for, shown by the editor.
    enum FieldsRequest: Identifiable, Hashable {
        case newType, addField(type: UUID), editField(UUID), newPage(field: UUID)
        var id: Self { self }
    }
    var fieldsRequest: FieldsRequest?

    /// The author's shared fields and the types (Character, Place…) built from them.
    private(set) var schema = Schema()
    func type(of page: WriterCore.Document) -> PageType? { schema.type(page.type) }
    func fields(of page: WriterCore.Document) -> [FieldDefinition] { schema.fields(of: type(of: page)) }

    /// Creates a type with no fields yet and gives it to the open page.
    func addType(named name: String) {
        let type = PageType(name: name)
        schema.types.append(type)
        saveSchema()
        update { $0.type = type.id }
    }

    func renameType(_ id: UUID, to name: String) {
        schema.renameType(id, to: name)
        saveSchema()
    }

    /// Deletes a type. Its pages have no type after; their field values stay
    /// saved, so giving them a type with those fields brings them back.
    func deleteType(_ id: UUID) {
        for i in pages.indices where pages[i].type == id {
            pages[i].type = nil
            scheduleSave(pages[i])
        }
        // Deleted pages too, so one recovered later doesn't name a missing type.
        for i in recentlyDeleted.indices where recentlyDeleted[i].type == id {
            recentlyDeleted[i].type = nil
            try? store?.save(recentlyDeleted[i])
        }
        schema.removeType(id)
        saveSchema()
    }

    func pageCount(ofType id: UUID) -> Int { pages.count { $0.type == id } }

    /// Adds `field` to the shared list if it's new, and to the end of `type`.
    func add(_ field: FieldDefinition, to type: UUID) {
        if !schema.fields.contains(where: { $0.id == field.id }) { schema.fields.append(field) }
        guard let i = schema.types.firstIndex(where: { $0.id == type }), !schema.types[i].fields.contains(field.id) else { return }
        schema.types[i].fields.append(field.id)
        saveSchema()
    }

    /// Changes a shared field (its name or choices) for every type that uses it.
    func updateField(_ field: FieldDefinition) {
        guard let i = schema.fields.firstIndex(where: { $0.id == field.id }) else { return }
        schema.fields[i] = field
        saveSchema()
    }

    /// Takes a field off a type, for every page of it. The field stays in the
    /// shared list, and values stay saved on the pages, so nothing is lost.
    func remove(_ field: UUID, from type: UUID) {
        guard let i = schema.types.firstIndex(where: { $0.id == type }) else { return }
        schema.types[i].fields.removeAll { $0 == field }
        saveSchema()
    }

    /// "Name: value" lines for a page's fields, for search.
    func fieldText(_ page: WriterCore.Document) -> String {
        page.fieldText(fields(of: page)) { id in pages.first { $0.id == id }?.heading }
    }

    private func saveSchema() {
        try? schemaStore?.save(schema)
        for page in pages where page.type != nil { PageIndex.update(page, fields: fieldText(page)) }
    }

    private let store: DocumentStore?
    private let schemaStore: SchemaStore?
    /// Pending debounced saves, one per page, so editing one page never drops another's.
    private var pendingSaves: [UUID: Task<Void, Never>] = [:]

    /// The open page (an empty one if none is open).
    var document: WriterCore.Document {
        pages.first { $0.id == selection } ?? WriterCore.Document()
    }

    init() {
        if Screenshots.isActive {
            store = nil                        // CI runs never touch saved pages
            schemaStore = nil
            (pages, schema) = Screenshots.pages()
            PageIndex.start(with: pages.map { ($0, fieldText($0)) })   // the simulator's own index
            if !Screenshots.opensList, let open = Screenshots.opensMara ? pages[1] : pages.first {
                selection = open.id
                // Typed text: caret at its end. Rich sample: at the top, title in view.
                let last = open.paragraphs.count - 1
                if !Screenshots.isRich { cursor = (last, open.paragraphs[last].length) }
            }
            return
        }
        let dir = URL.applicationSupportDirectory.appendingPathComponent("Documents", isDirectory: true)
        store = try? DocumentStore(directory: dir)
        schemaStore = SchemaStore(url: URL.applicationSupportDirectory.appendingPathComponent("Schema.json"))
        let saved = (try? store?.all()) ?? []
        pages = saved.filter { $0.deleted == nil }
        recentlyDeleted = saved.filter { $0.deleted != nil }.sorted { $0.deleted! > $1.deleted! }
        removeExpired()
        schema = schemaStore?.load() ?? Schema()
        PageIndex.start(with: pages.map { ($0, fieldText($0)) })
        if pages.isEmpty { newPage() } else { selection = pages.first?.id }
    }

    func newPage() {
        let page = WriterCore.Document()
        pages.insert(page, at: 0)
        selection = page.id
    }

    /// A titled page for an `@` mention, saved but not opened.
    func addPage(titled title: String, type: UUID? = nil) -> UUID {
        var page = WriterCore.Document(title: title)
        page.type = type
        pages.insert(page, at: min(1, pages.count))   // just behind the open page
        scheduleSave(page)
        return page.id
    }

    /// Pages with an `@` link to `id`, most recent first.
    func mentions(of id: UUID) -> [WriterCore.Document] {
        pages.filter { $0.id != id && $0.mentions(id) }
    }

    /// Moves a page to Recently Deleted (an empty one just goes).
    func delete(_ id: UUID) {
        // First: leaving the open page discards it if it's empty, which
        // changes `pages` under us.
        if selection == id { selection = nil }
        pendingSaves.removeValue(forKey: id)?.cancel()
        guard let i = pages.firstIndex(where: { $0.id == id }) else { return }
        var page = pages.remove(at: i)
        if store != nil { PageIndex.remove(id) }
        guard !page.isEmpty else { try? store?.delete(id); return }
        page.deleted = .now
        recentlyDeleted.insert(page, at: 0)
        try? store?.save(page)
    }

    /// Back from Recently Deleted, to its place by date among the pages.
    func recover(_ id: UUID) {
        guard let i = recentlyDeleted.firstIndex(where: { $0.id == id }) else { return }
        var page = recentlyDeleted.remove(at: i)
        page.deleted = nil
        pages.insert(page, at: pages.firstIndex { $0.modified < page.modified } ?? pages.count)
        try? store?.save(page)
        if store != nil { PageIndex.update(page, fields: fieldText(page)) }
    }

    func deleteForGood(_ id: UUID) {
        recentlyDeleted.removeAll { $0.id == id }
        try? store?.delete(id)
    }

    /// Deletes for good the pages whose 30 days are up.
    func removeExpired() {
        for page in recentlyDeleted where page.goesForGood! <= .now { deleteForGood(page.id) }
    }

    /// Applies a user edit to the open page.
    func update(_ change: (inout WriterCore.Document) -> Void) {
        guard let i = pages.firstIndex(where: { $0.id == selection }) else { return }
        let heading = pages[i].heading
        change(&pages[i])
        let page = pages.remove(at: i)
        pages.insert(page, at: 0)
        scheduleSave(page)
        // Renamed: links to it everywhere show the new name, as in Apple Notes.
        guard page.heading != heading else { return }
        for j in pages.indices.dropFirst() where pages[j].retitleLinks(to: page.id, as: page.heading) {
            scheduleSave(pages[j])
        }
    }

    private func discardIfEmpty(_ id: UUID) {
        guard let page = pages.first(where: { $0.id == id }), page.isEmpty else { return }
        pendingSaves.removeValue(forKey: id)?.cancel()
        pages.removeAll { $0.id == id }
        try? store?.delete(id)
    }

    private func scheduleSave(_ page: WriterCore.Document) {
        pendingSaves[page.id]?.cancel()
        let fields = fieldText(page)
        pendingSaves[page.id] = Task { [store] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let store else { return }
            try? store.save(page)
            PageIndex.update(page, fields: fields)
        }
    }

    /// Saves a page now if it has an edit waiting (leaving it, or the app going away).
    func flush(_ id: UUID) {
        guard let task = pendingSaves.removeValue(forKey: id) else { return }
        task.cancel()
        if let store, let page = pages.first(where: { $0.id == id }), !page.isEmpty {
            try? store.save(page)
            PageIndex.update(page, fields: fieldText(page))
        }
    }

    func flushAll() { for id in Array(pendingSaves.keys) { flush(id) } }
}

/// Launch arguments for CI screenshots (never used otherwise):
/// - `-screenshotText "para one\npara two"`: a page with that text (`EMPTY` for blank)
/// - `-screenshotRich YES`: one page showing bold, italic and both kinds of list
/// - `-screenshotMentions YES`: with `-screenshotRich`, Mara's page with its Mentions sheet open
/// - `-screenshotMara YES`: with `-screenshotRich`, Mara's page: a Character with fields
/// - `-screenshotPages YES`: showing the pages list
/// - `-screenshotSearch "about the bell"`: with `-screenshotPages`, searching the list
/// Each seeds two more pages, so `@` has something to find.
/// - `-startInFocus YES`: open the page in Focus mode (read by `RootView`)
/// - `-focusControls YES`: with Focus mode's controls showing (read by `RootView`)
enum Screenshots {
    private static let defaults = UserDefaults.standard
    static var isActive: Bool { defaults.string(forKey: "screenshotText") != nil || isRich || opensList }
    static var opensList: Bool { defaults.bool(forKey: "screenshotPages") }
    static var isRich: Bool { defaults.bool(forKey: "screenshotRich") }
    static var showsMentions: Bool { defaults.bool(forKey: "screenshotMentions") }
    /// Mara's page: a Character, which Harbour Notes links to.
    static var opensMara: Bool { showsMentions || defaults.bool(forKey: "screenshotMara") }
    static var searchQuery: String? { defaults.string(forKey: "screenshotSearch") }

    /// Sample pages: Harbour Notes, Mara (a Character), Map of the Coast.
    static func pages() -> ([WriterCore.Document], Schema) {
        let place = PageType(name: "Place")
        let fields = [
            FieldDefinition(name: "Species", kind: .choice, options: ["Human", "Elf", "Selkie"]),
            FieldDefinition(name: "Age", kind: .number),
            FieldDefinition(name: "Home", kind: .page, pageType: place.id),
            FieldDefinition(name: "First seen", kind: .date),
            FieldDefinition(name: "Keeps a secret", kind: .toggle),
        ]
        let character = PageType(name: "Character", fields: fields.map(\.id))
        let schema = Schema(fields: fields, types: [character, place])
        let day: TimeInterval = 86_400
        let map = WriterCore.Document(title: "Map of the Coast", paragraphs: [Paragraph(text: "Three coves, one road.")],
                                      modified: Date().addingTimeInterval(-3 * day), type: place.id)
        let mara = WriterCore.Document(title: "Mara", paragraphs: [Paragraph(text: "Keeps the lighthouse.")],
                                       modified: Date().addingTimeInterval(-day), type: character.id, values: [
                                           fields[0].id: .text("Selkie"),
                                           fields[1].id: .number(61),
                                           fields[2].id: .page(map.id),
                                           fields[3].id: .date(Date(timeIntervalSince1970: 1_790_000_000)),
                                           fields[4].id: .toggle(true),
                                       ])
        if let seeded = defaults.string(forKey: "screenshotText") {
            let text = seeded == "EMPTY" ? "" : seeded.replacingOccurrences(of: "\\n", with: "\n")
            return ([WriterCore.Document(paragraphs: text.components(separatedBy: "\n").map { Paragraph(text: $0) }), mara, map],
                    schema)
        }
        let rich = WriterCore.Document(title: "Harbour Notes", paragraphs: [
            Paragraph(text: "The tide came in faster than the charts promised.",
                      runs: [StyleRun(location: 17, length: 6, style: .italic)]),
            Paragraph(text: "Lantern oil", kind: .bullet),
            Paragraph(text: "Rope, two coils", kind: .bullet),
            Paragraph(text: "Check the north mooring", kind: .numbered,
                      runs: [StyleRun(location: 10, length: 5, style: .bold)]),
            Paragraph(text: "Ask Mara about the bell", kind: .numbered,
                      links: [PageLink(location: 4, length: 4, page: mara.id)]),
        ])
        return ([rich, mara, map], schema)
    }
}
