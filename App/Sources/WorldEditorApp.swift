import SwiftUI
import Guardrails
import WriterCore

@main
struct WorldEditorApp: App {
    @State private var library = Library()
    @State private var companion = Companion()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(companion)
        }
        .onChange(of: phase) { _, phase in
            if phase != .active { library.flushAll() }   // never lose the last edits
            else { library.removeExpired() }   // the app may stay open past a page's 30 days
        }
    }
}

/// The open world: its pages, the one that's open, and saving shortly after
/// each edit; and the other worlds, to switch to.
@MainActor @Observable
final class Library {
    /// Every world, by name, and the open one. A world's pages, types and
    /// fields are its own; search, @ links and fields stay within it.
    private(set) var worlds: [World] = []
    private(set) var world = World(name: World.defaultName)

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
        /// A type's fields, to remove, reorder or edit ("Edit Character Fields…").
        case editFields(type: UUID)
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

    /// Reorders a type's fields, for every page of it.
    func moveFields(in type: UUID, from offsets: IndexSet, to destination: Int) {
        guard let i = schema.types.firstIndex(where: { $0.id == type }) else { return }
        schema.types[i].fields.move(fromOffsets: offsets, toOffset: destination)
        saveSchema()
    }

    /// Takes a field off a type, for every page of it. The field stays in the
    /// shared list, and values stay saved on the pages, so nothing is lost.
    func remove(_ field: UUID, from type: UUID) {
        guard let i = schema.types.firstIndex(where: { $0.id == type }) else { return }
        schema.types[i].fields.removeAll { $0 == field }
        saveSchema()
    }

    /// A page as the companion is shown it: the `open` one by its title (which
    /// may be empty) and with its fields, the others by their heading.
    /// - Parameter fields: with its fields though not open (every page in a world conversation).
    func companionPage(_ page: WriterCore.Document, open: Bool = false, fields: Bool = false) -> CompanionPrompt.Page {
        CompanionPrompt.Page(name: open ? page.title : page.heading, type: type(of: page)?.name,
                             fields: open || fields ? fieldText(page) : "",
                             writing: page.paragraphs.map(\.text).joined(separator: "\n"))
    }

    // MARK: Filing from the companion's conversation (docs/companion.md, Filing)

    /// What the model is asked, to read types, fields and pages out of the
    /// author's `message` in `page`'s conversation, answering `asked`;
    /// `aboutWorld`: in a conversation about the whole world, with no page open.
    func filingPrompt(for page: WriterCore.Document, aboutWorld: Bool, asked: String?, message: String) -> FilingPrompt {
        aboutWorld ? FilingPrompt(world: pages, schema: schema, asked: asked, message: message)
                   : FilingPrompt(open: page, pages: pages, schema: schema, asked: asked, message: message)
    }

    /// Files what the model read out of `message` (`Filer` keeps only the
    /// author's own words, and replaces nothing) and saves it.
    /// - Parameter again: the record of an earlier reading that found nothing (Try Again
    ///   reads the message again): only values still as it saw them may be corrected.
    /// - Parameter sent: the open page's fields and title when the author sent the
    ///   message: only what's still as it was then on that page is changed.
    func file(_ filings: Filings, message: String, on page: UUID, again: FilingRecord? = nil,
              sent: (values: [UUID: FieldValue], title: String)? = nil) -> FilingRecord {
        var pages = pages, schema = schema
        let open = pages.first { $0.id == page }
        let seen = again?.seen ?? sent?.values ?? open?.values ?? [:]
        let seenTitle = again.map { $0.seenTitle } ?? sent?.title ?? open?.title
        var record = Filer.file(filings, message: message, open: page, pages: &pages, schema: &schema,
                                replaceable: { p, field, was in p == page ? seen[field] == was : again == nil },
                                renames: seenTitle != nil && seenTitle == open?.title)
        record.seen = seen
        record.seenTitle = seenTitle
        record.date = Date()
        if !record.isEmpty { commit(pages, schema) }
        return record
    }

    /// Takes back one thing filing did (`FilingRecord.undo`). A page it made
    /// goes, or, if the author wrote on it since, goes to Recently Deleted.
    /// - Parameters:
    ///   - kept: pages the author has talked about in their own conversation, kept (in
    ///     Recently Deleted) rather than deleted if this made them.
    ///   - others: every other filing record in the world, whose types and fields go too
    ///     once nothing uses them (`FilingRecord.tidy`).
    func undo(_ action: FilingRecord.Entry, of record: inout FilingRecord, kept: (UUID) -> Bool = { _ in false },
              others: [FilingRecord] = []) {
        var pages = pages, schema = schema
        let made = record.undo(action, pages: &pages, schema: &schema, kept: kept, deleted: recentlyDeleted)
        FilingRecord.tidy(others.flatMap(\.entries), pages: pages + recentlyDeleted, schema: &schema)
        if let made, !made.edited {
            if selection == made.page { selection = nil }
            pendingSaves.removeValue(forKey: made.page)?.cancel()
            try? store?.delete(made.page)
            if store != nil { PageIndex.remove(made.page) }
        }
        commit(pages, schema)
        if let made, made.edited { delete(made.page) }
    }

    /// Takes on changed pages and schema, saving what changed.
    private func commit(_ new: [WriterCore.Document], _ newSchema: Schema) {
        let old = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, $0) })
        pages = new
        if newSchema != schema {
            schema = newSchema
            saveSchema()
        }
        for page in new where old[page.id] != page { scheduleSave(page) }
        // Renamed (by filing, or its Undo): links to it everywhere show the new name, as in `update`.
        for page in new where old[page.id].map({ $0.heading != page.heading }) ?? false {
            for j in pages.indices where pages[j].id != page.id && pages[j].retitleLinks(to: page.id, as: page.heading) {
                scheduleSave(pages[j])
            }
        }
    }

    /// What a filing did, as the conversation shows it: pages by their names now. Every
    /// action gets a line, even one whose page, type or field has since been deleted
    /// (named as deleted): Undo goes newest first, so a hidden line could block an older one.
    func describe(_ record: FilingRecord) -> [FilingLine] {
        record.actions.compactMap { action -> FilingLine? in
            let page = action.page.map(filedName) ?? Self.deletedPage
            switch action {
            case .created(let id, _):
                let type = (pages.first { $0.id == id } ?? recentlyDeleted.first { $0.id == id })?.type
                return FilingLine(action: action, page: page, detail: nil, type: schema.type(type)?.name)
            case .typed(_, let type):
                return FilingLine(action: action, page: page, detail: schema.type(type)?.name ?? "Deleted type", type: nil)
            case .described(_, let text):
                return FilingLine(action: action, page: page, detail: "\u{201C}\(text)\u{201D}", type: nil)
            case .renamed:
                return FilingLine(action: action, page: page, detail: nil, type: nil)
            case .value(_, let fieldID, let value), .replaced(_, let fieldID, _, let value):
                let field = schema.fields.first { $0.id == fieldID }?.name ?? "Deleted field"
                var detail = "\(field): \(filedValue(value))"
                if case .replaced(_, _, let was, _) = action { detail += " (was \(filedValue(was)))" }
                return FilingLine(action: action, page: page, detail: detail, type: nil)
            case .newType, .newField, .fieldAdded:
                return nil
            }
        }
    }

    static let deletedPage = "Deleted page"

    /// A page's name as filing lines show it: in Recently Deleted too, else as deleted.
    func filedName(_ id: UUID) -> String {
        (pages.first { $0.id == id } ?? recentlyDeleted.first { $0.id == id })?.heading ?? Self.deletedPage
    }

    /// A filed value as filing lines show it (a link by its page's name).
    func filedValue(_ value: FieldValue) -> String {
        value.display { self.filedName($0) } ?? ""
    }

    /// "Name: value" lines for a page's fields, for search.
    func fieldText(_ page: WriterCore.Document) -> String {
        page.fieldText(fields(of: page)) { id in pages.first { $0.id == id }?.heading }
    }

    private func saveSchema() {
        try? schemaStore?.save(schema)
        for page in pages where page.type != nil { PageIndex.update(page, fields: fieldText(page)) }
    }

    private let worldStore: WorldStore?
    private var store: DocumentStore?
    private var schemaStore: SchemaStore?
    /// Pending debounced saves, one per page, so editing one page never drops another's.
    private var pendingSaves: [UUID: Task<Void, Never>] = [:]

    /// A conversation about the whole world stands for no page: it goes by its own id
    /// (`WorldCompanionView`; Kevin, 2026-11-24).
    func worldSubject(_ conversation: UUID) -> WriterCore.Document {
        WriterCore.Document(id: conversation, title: world.name)
    }

    /// The world conversation open when the author last left the companion's list, to go
    /// back into (nil: they were at the list).
    var lastWorldConversation: UUID? {
        get { UserDefaults.standard.string(forKey: "worldConversation." + world.id.uuidString).flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "worldConversation." + world.id.uuidString) }
    }

    /// The open page (an empty one if none is open).
    var document: WriterCore.Document {
        pages.first { $0.id == selection } ?? WriterCore.Document()
    }

    /// Where the open world keeps the companion's conversations; nil in CI.
    var conversationsDirectory: URL? { worldStore?.conversations(world.id) }

    init() {
        if Screenshots.isActive {
            worldStore = nil                   // CI runs never touch saved pages
            worlds = [world]
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
        let support = URL.applicationSupportDirectory
        worldStore = try? WorldStore(root: support.appendingPathComponent("Worlds", isDirectory: true))
        // Pages saved before worlds existed become the first world.
        _ = try? worldStore?.adoptLegacy(documents: support.appendingPathComponent("Documents", isDirectory: true),
                                         schema: support.appendingPathComponent("Schema.json"))
        worlds = worldStore?.all() ?? []
        if worlds.isEmpty {
            try? worldStore?.save(world)
            worlds = [world]
        }
        let last = UserDefaults.standard.string(forKey: Self.openWorldKey).flatMap(UUID.init)
        load(worlds.first { $0.id == last } ?? worlds[0])
        worldStore?.removeExpired(except: world.id)   // the open world's are removed as it loads
    }

    private static let openWorldKey = "openWorld"

    /// Reads a world from disk and opens its most recent page.
    private func load(_ world: World) {
        self.world = world
        UserDefaults.standard.set(world.id.uuidString, forKey: Self.openWorldKey)
        store = worldStore.flatMap { try? DocumentStore(directory: $0.documents(world.id)) }
        schemaStore = worldStore.map { SchemaStore(url: $0.schema(world.id)) }
        let saved = (try? store?.all()) ?? []
        pages = saved.filter { $0.deleted == nil }
        recentlyDeleted = saved.filter { $0.deleted != nil }.sorted { $0.deleted! > $1.deleted! }
        removeExpired()
        schema = schemaStore?.load() ?? Schema()
        searchQuery = ""
        PageIndex.start(with: pages.map { ($0, fieldText($0)) })
        if pages.isEmpty { newPage() } else { selection = pages.first?.id }
    }

    /// Switches to another world, saving and leaving the open page first.
    func open(world id: UUID) {
        guard id != world.id, let next = worlds.first(where: { $0.id == id }) else { return }
        selection = nil   // leaves the page (an empty one is discarded) in this world
        flushAll()
        load(next)
    }

    /// Opens a page from any world (the system's Spotlight search).
    func open(page id: UUID) {
        if !pages.contains(where: { $0.id == id }), let other = worldStore?.world(containing: id) { open(world: other) }
        if pages.contains(where: { $0.id == id }) { selection = id }
    }

    func newWorld(named name: String) throws {
        let new = World(name: name)
        try worldStore?.save(new)
        worlds = worldStore?.all() ?? worlds + [new]
        open(world: new.id)
    }

    func renameWorld(_ id: UUID, to name: String) throws {
        guard var renamed = worlds.first(where: { $0.id == id }) else { return }
        renamed.name = name
        try worldStore?.save(renamed)
        worlds = worldStore?.all() ?? worlds
        if world.id == id { world = renamed }
    }

    /// Deletes a world and all its pages, for good; never the last one.
    func deleteWorld(_ id: UUID) {
        guard worlds.count > 1, let store = worldStore else { return }
        if world.id == id, let other = worlds.first(where: { $0.id != id }) { open(world: other.id) }
        for page in (try? DocumentStore(directory: store.documents(id)).all()) ?? [] { PageIndex.remove(page.id) }
        try? store.delete(id)
        worlds = store.all()
    }

    /// How many pages a world holds, Recently Deleted included.
    func pageCount(inWorld id: UUID) -> Int {
        id == world.id ? pages.count { !$0.isEmpty } + recentlyDeleted.count : worldStore?.pageCount(id) ?? 0
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
        // A link in a field the page's type no longer shows doesn't count (its value is kept, unseen).
        pages.filter { page in
            page.id != id && (page.paragraphs.contains { $0.links.contains { $0.page == id } }
                              || fields(of: page).contains { page.values[$0.id] == .page(id) })
        }
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
        // A blank page you've talked through with the companion is kept; its
        // unanswered question goes with it otherwise.
        let talk = conversationsDirectory.flatMap { try? ConversationStore(directory: $0) }
        if let talk, !talk.load(id).authorText.isEmpty { return }
        talk?.delete(id)
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

/// One thing filing did, as a line in the conversation: a page made, a type
/// given, or a field filled; each undone on its own.
struct FilingLine: Hashable {
    var action: FilingRecord.Entry
    var page: String
    /// The type given, "Field: value", or the page text filed (quoted); nil for a new page.
    var detail: String?
    /// A new page's type.
    var type: String?
    var isNew: Bool { if case .created = action { true } else { false } }
}
