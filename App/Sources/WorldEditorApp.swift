import SwiftUI
import Guardrails
import WriterCore

@main
struct WorldEditorApp: App {
    @State private var library = Library()
    @State private var companion = Companion()
    @Environment(\.scenePhase) private var phase

    /// The look (`Look`) in what UIKit draws: the window behind everything (and, if iOS lets it,
    /// the Duo's side column), and the writing's caret and selection. What it doesn't colour (menus,
    /// alerts, iOS's own sheets) is in iOS's softer dark grey, its sheets' and popovers' own, rather
    /// than its black (Kevin, 2026-11-27: "maybe it's all the black it doesn't feel soothing or
    /// welcoming"): iOS's own colours, one level up.
    private static func applyLook() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.traitOverrides.userInterfaceLevel = .elevated
            for window in scene.windows {
                window.backgroundColor = Look.background
                window.tintColor = Look.emphasis
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                #if DEBUG
                .sceneDirector()   // a scene's set-up after launch (Scenes/)
                #endif
                .environment(library)
                .environment(companion)
                .tint(.primary)   // every control white (`Look`)
                .onAppear(perform: Self.applyLook)
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
    /// What of the open world this version couldn't read ("your types and fields", "2
    /// pages"), to tell the author once: it's kept as it is, never saved over (`UnreadableFile`).
    var unreadable: [String] = []

    /// The open page. Leaving a page that was never written in discards it.
    var selection: UUID? {
        didSet {
            guard oldValue != selection else { return }
            cursor = selection.flatMap(searchCursor) ?? (0, 0)
            if let old = oldValue { flush(old); discardIfEmpty(old) }
            if let selection { unseen.remove(selection) }
        }
    }

    /// Pages the companion made or added to that the author hasn't opened since: marked in the
    /// pages list until they do, so each arrives as a new part of the world (Kevin, 2026-11-27,
    /// of watching the world grow as the pull to come back: "Yes, that"). Kept per world.
    var unseen: Set<UUID> = [] {
        didSet {
            guard unseen != oldValue else { return }
            UserDefaults.standard.set(unseen.map(\.uuidString), forKey: perWorld("unseen"))
        }
    }

    /// Where each page's card is in the world's Connections (`WorldMap`), kept so they grow
    /// outward rather than rearranging themselves each time. Kept per world.
    var mapPlaces: [UUID: WorldMap.Place] = [:] {
        didSet {
            guard mapPlaces != oldValue, let data = try? JSONEncoder().encode(mapPlaces) else { return }
            UserDefaults.standard.set(data, forKey: perWorld("mapPlaces"))
        }
    }

    /// The key a setting is saved under for the open world alone ("unseen.<world's id>").
    private func perWorld(_ setting: String) -> String { setting + "." + world.id.uuidString }

    /// Caret position shared by both editors so switching modes keeps your place.
    var cursor = (paragraph: 0, offset: 0)
    /// The pages list's search, so a result opens at its match, not the top.
    var searchQuery = ""
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
            write(recentlyDeleted[i])
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

    // MARK: Filing from the companion's conversation (docs/companion.md, Filing)

    /// What the model is asked, to read types, fields and pages out of the
    /// author's `message` in `page`'s conversation, answering `asked`;
    /// `aboutWorld`: in a conversation about the whole world, with no page open, where
    /// `focus` is who they were last talking about (`Filer.focus`) and `saidBefore` their
    /// message just before (`Filer.said`).
    func filingPrompt(for page: WriterCore.Document, aboutWorld: Bool, asked: String?, message: String,
                      focus: [UUID] = [], saidBefore: String? = nil) -> FilingPrompt {
        aboutWorld ? FilingPrompt(world: pages, schema: schema, asked: asked, message: message, focus: focus, saidBefore: saidBefore)
                   : FilingPrompt(open: page, pages: pages, schema: schema, asked: asked, message: message)
    }

    /// Files what the model read out of `message` (`Filer` keeps only the
    /// author's own words, and replaces nothing) and saves it. The pages it changed are on
    /// disk when it returns, before the caller saves the message's record: if the app closes
    /// between the two, the message is read again at the next launch (which files nothing
    /// twice), rather than keeping a record of changes the pages never got.
    /// - Parameter again: the record of an earlier reading that found nothing (Try Again
    ///   reads the message again): only values still as it saw them may be corrected.
    /// - Parameter sent: the open page's fields and title when the author sent the
    ///   message: only what's still as it was then on that page is changed.
    /// - Parameter late: something was filed from a later message already (`Filer.isLate`):
    ///   this one only adds.
    /// - Parameter focus: in a conversation about the whole world, who they were last
    ///   talking about, as the model was told (`filingPrompt`).
    func file(_ filings: Filings, message: String, on page: UUID, again: FilingRecord? = nil,
              sent: (values: [UUID: FieldValue], title: String)? = nil, late: Bool = false, focus: [UUID] = []) -> FilingRecord {
        var pages = pages, schema = schema
        let open = pages.first { $0.id == page }
        let seen = again?.seen ?? sent?.values ?? open?.values ?? [:]
        let seenTitle = again.map { $0.seenTitle } ?? sent?.title ?? open?.title
        var record = Filer.file(filings, message: message, open: page, pages: &pages, schema: &schema,
                                replaceable: { p, field, was in p == page ? seen[field] == was : again == nil },
                                renames: seenTitle != nil && seenTitle == open?.title, late: late, focus: focus)
        record.seen = seen
        record.seenTitle = seenTitle
        record.date = Date()
        if !record.isEmpty {
            commit(pages, schema)
            flushAll()   // not left to the save a moment later, which the record would be saved ahead of
            unseen.formUnion(record.actions.compactMap(\.page).filter { $0 != selection })   // the open page is seen
        }
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
            erase(made.page)
            if store != nil { PageIndex.remove(made.page) }
        }
        commit(pages, schema)
        if let made, made.edited { delete(made.page) }
    }

    /// Takes on changed pages and schema, saving what changed.
    private func commit(_ new: [WriterCore.Document], _ newSchema: Schema) {
        let old = Dictionary(pages.map { ($0.id, $0) }) { first, _ in first }
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
                return FilingLine(action: action, page: page, type: schema.type(type)?.name)
            case .typed(_, let type):
                return FilingLine(action: action, page: page, label: schema.type(type)?.name ?? "Deleted type")
            case .described(_, let text):
                return FilingLine(action: action, page: page, words: "\u{201C}\(text)\u{201D}")
            case .placed(let placement):
                return FilingLine(action: action, page: page, words: "\u{201C}\(placement.texts.joined(separator: " "))\u{201D}")
            case .renamed:
                return FilingLine(action: action, page: page)
            case .value(_, let fieldID, let value), .replaced(_, let fieldID, _, let value):
                let field = schema.fields.first { $0.id == fieldID }?.name ?? "Deleted field"
                return FilingLine(action: action, page: page, label: field, words: filedValue(value),
                                  was: action.was.map(filedValue))
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
    /// (the drawer's Conversations; Kevin, 2026-11-24).
    func worldSubject(_ conversation: UUID) -> WriterCore.Document {
        WriterCore.Document(id: conversation, title: world.name)
    }

    /// The world conversation last open, to open again (nil: none yet).
    var lastWorldConversation: UUID? {
        get { UserDefaults.standard.string(forKey: perWorld("worldConversation")).flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: perWorld("worldConversation")) }
    }

    /// The open page (an empty one if none is open).
    var document: WriterCore.Document {
        pages.first { $0.id == selection } ?? WriterCore.Document()
    }

    /// Where the open world keeps the companion's conversations; nil if the worlds' folder couldn't be made.
    var conversationsDirectory: URL? { worldStore?.conversations(world.id) }

    private var conversationStore: ConversationStore? {
        conversationsDirectory.flatMap { try? ConversationStore(directory: $0) }
    }

    /// The author's worlds, in Application Support; a scene's own (Scenes/), in a debug build in
    /// the simulator.
    convenience init() {
        #if DEBUG
        if let scene = LaunchScene.current {
            self.init(root: scene.writeWorld())
            scene.open(in: self)
            return
        }
        #endif
        let support = URL.applicationSupportDirectory
        self.init(root: support.appendingPathComponent("Worlds", isDirectory: true), legacy: support)
    }

    /// The worlds kept in `root`, with the one open last loaded.
    /// - Parameter legacy: where pages were saved before worlds existed, to become the first world.
    init(root: URL, legacy: URL? = nil) {
        worldStore = try? WorldStore(root: root)
        if let legacy {
            _ = try? worldStore?.adoptLegacy(documents: legacy.appendingPathComponent("Documents", isDirectory: true),
                                             schema: legacy.appendingPathComponent("Schema.json"))
        }
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

    /// "1 page", "2 pages".
    private static func count(_ n: Int, _ thing: String) -> String { "\(n) \(thing)\(n == 1 ? "" : "s")" }

    /// Reads a world from disk. No page opens: its conversation is in front (`RootView`).
    private func load(_ world: World) {
        self.world = world
        unseen = Set((UserDefaults.standard.stringArray(forKey: perWorld("unseen")) ?? []).compactMap(UUID.init))
        mapPlaces = UserDefaults.standard.data(forKey: perWorld("mapPlaces"))
            .flatMap { try? JSONDecoder().decode([UUID: WorldMap.Place].self, from: $0) } ?? [:]
        UserDefaults.standard.set(world.id.uuidString, forKey: Self.openWorldKey)
        store = worldStore.flatMap { try? DocumentStore(directory: $0.documents(world.id)) }
        schemaStore = worldStore.map { SchemaStore(url: $0.schema(world.id)) }
        let saved = store?.scan() ?? (pages: [], unreadable: [])
        pages = saved.pages.filter { $0.deleted == nil }
        recentlyDeleted = saved.pages.filter { $0.deleted != nil }.sorted { $0.deleted! > $1.deleted! }
        removeExpired()
        var unread: [String] = []
        do {
            schema = try schemaStore?.load() ?? Schema()
        } catch {
            schema = Schema()
            unread.append("your types and fields")
        }
        if !saved.unreadable.isEmpty { unread.append(Self.count(saved.unreadable.count, "page")) }
        let talk = conversationStore?.scan().unreadable ?? []
        if !talk.isEmpty { unread.append(Self.count(talk.count, "conversation")) }
        unreadable = unread
        searchQuery = ""
        PageIndex.start(with: pages.map { ($0, fieldText($0)) })
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
        for page in (try? DocumentStore(directory: store.documents(id)))?.all() ?? [] { PageIndex.remove(page.id) }
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
        guard !page.isEmpty else { erase(id); return }
        page.deleted = .now
        recentlyDeleted.insert(page, at: 0)
        write(page)
    }

    /// Back from Recently Deleted, to its place by date among the pages.
    func recover(_ id: UUID) {
        guard let i = recentlyDeleted.firstIndex(where: { $0.id == id }) else { return }
        var page = recentlyDeleted.remove(at: i)
        page.deleted = nil
        pages.insert(page, at: pages.firstIndex { $0.modified < page.modified } ?? pages.count)
        write(page)
        if store != nil { PageIndex.update(page, fields: fieldText(page)) }
    }

    func deleteForGood(_ id: UUID) {
        recentlyDeleted.removeAll { $0.id == id }
        erase(id)
        conversationStore?.delete(id)   // its talk goes with it
    }

    /// Deletes for good the pages whose 30 days are up.
    func removeExpired() {
        for page in recentlyDeleted where page.goesForGood! <= .now { deleteForGood(page.id) }
    }

    /// Applies a user edit to the open page, which goes to the top of the list (once: moving
    /// it on every keystroke redrew everything showing the list).
    func update(_ change: (inout WriterCore.Document) -> Void) {
        guard let i = pages.firstIndex(where: { $0.id == selection }) else { return }
        if i != 0 { pages.move(fromOffsets: [i], toOffset: 0) }
        let heading = pages[0].heading
        change(&pages[0])
        let page = pages[0]
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
        let talk = conversationStore
        if let talk, talk.hasTalk(id) { return }
        talk?.delete(id)
        pendingSaves.removeValue(forKey: id)?.cancel()
        pages.removeAll { $0.id == id }
        erase(id)
    }

    private func scheduleSave(_ page: WriterCore.Document) {
        pendingSaves[page.id]?.cancel()
        let fields = fieldText(page)
        pendingSaves[page.id] = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, store != nil else { return }
            write(page)
            PageIndex.update(page, fields: fields)
        }
    }

    /// Page files are written and removed in order on one queue of their own, so saving
    /// never holds up typing, and a delete is never undone by a save still waiting to run.
    private let disk = DispatchQueue(label: "app.world-editor.pages", qos: .userInitiated)

    private func write(_ page: WriterCore.Document) {
        guard let store else { return }
        disk.async { try? store.save(page) }
    }

    private func erase(_ id: UUID) {
        guard let store else { return }
        disk.async { try? store.delete(id) }
    }

    /// Saves a page now if it has an edit waiting (leaving it, or the app going away).
    func flush(_ id: UUID) {
        guard let task = pendingSaves.removeValue(forKey: id) else { return }
        task.cancel()
        if store != nil, let page = pages.first(where: { $0.id == id }), !page.isEmpty {
            write(page)
            PageIndex.update(page, fields: fieldText(page))
        }
    }

    /// Saves every edit waiting, and waits for them to be on disk (the app going away).
    func flushAll() {
        for id in Array(pendingSaves.keys) { flush(id) }
        disk.sync {}
    }
}

/// One thing filing did, as a line in the conversation: a page made, a type
/// given, or a field filled; each undone on its own.
struct FilingLine: Hashable {
    var action: FilingRecord.Entry
    var page: String
    /// The type given, or the field filled: the app's labels, in San Francisco.
    var label: String? = nil
    /// The value filed, or the page text filed (quoted): the author's words, in New York.
    var words: String? = nil
    /// The value a corrected field had.
    var was: String? = nil
    /// A new page's type.
    var type: String? = nil
    var isNew: Bool { if case .created = action { true } else { false } }

    /// "Field: value (was old)", the type given, or the page text filed; nil for a new page or a rename.
    var detail: String? {
        let words = words.map { $0 + (was.map { " (was \($0))" } ?? "") }
        return switch (label, words) {
        case let (label?, words?): "\(label): \(words)"
        case (let label?, nil): label
        case (nil, let words?): words
        case (nil, nil): nil
        }
    }
}
