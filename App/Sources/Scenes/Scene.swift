#if DEBUG
import Foundation
import SampleWorld
import WriterCore

/// One screen of the app in one state, set up at launch for CI to render on the Duo simulator
/// (ci/scenes.txt, ci/screenshots.sh): `-scene <name>`, with `-fixture sample|empty` (the sample
/// world, `SampleWorld`, unless said) and `-keyboard YES` (the keyboard up as well).
///
/// A scene runs only in a debug build in the simulator (`current`): it can never start on a
/// phone or touch the author's own worlds. It opens its fixture from a folder of its own,
/// written fresh at each launch, with the companion playing a script (`ScriptedModel`) in place
/// of a model. What it shows is reached as the author reaches it: the screen in front and the
/// page open are where the app opens (`LaunchStart`); a sheet, an alert or the keyboard comes
/// after the first frame, as a tap would (`SceneDirector`, `sceneShows`). Once all of that is
/// on screen it says so (`SceneStage`).
struct LaunchScene: Sendable {
    enum Fixture: String, Sendable { case sample, empty }

    /// What the scene presents after the first frame, from the view that presents it.
    enum Shows: Hashable, Sendable {
        case changes, instructions, mentions, typeFields, field, fieldTimeline, newWorld, deleted, focusControls
    }

    var name: String
    var fixture = Fixture.sample
    /// What the app opens on.
    var start = LaunchStart()
    var shows: Shows?
    /// The keyboard is brought up after the first frame, in the first place to write on screen.
    var keyboard = false
    /// Words typed there once it's up.
    var typed: String?
    /// The caret at the end of the open page, where typing left it; else at its top.
    var caretAtEnd = false
    /// The world conversation in front, if not the one the sample opens again; `newConversation`:
    /// a new one, nothing said.
    var conversation: UUID?
    var newConversation = false
    /// What the Pages screen is searching for.
    var search: String?
    var script = ScriptedModel.Script.ready
    /// Pages made for this scene alone, written beside the fixture's.
    var pages: [Document] = []

    /// The scene this launch shows, read once; nil on every launch but a scene's in a debug
    /// build in the simulator.
    static let current: LaunchScene? = {
        #if targetEnvironment(simulator)
        return launched(with: ProcessInfo.processInfo.arguments)
        #else
        return nil
        #endif
    }()

    /// The scene named in the launch `arguments`, if any. A name no scene has stops the app,
    /// so a mistyped line in ci/scenes.txt shows as a shot that's missing, not a wrong one.
    private static func launched(with arguments: [String]) -> LaunchScene? {
        func value(_ flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        guard let name = value("-scene") else { return nil }
        SceneStage.clearMarker()   // before anything else: CI waits for the new one
        guard var scene = named(name) else { fatalError("No scene is named \u{201C}\(name)\u{201D} (App/Sources/Scenes/Scene.swift)") }
        if let fixture = value("-fixture") {
            guard let chosen = Fixture(rawValue: fixture) else { fatalError("No fixture is named \u{201C}\(fixture)\u{201D}") }
            scene.fixture = chosen
        }
        if value("-keyboard") == "YES" { scene.keyboard = true }
        return scene
    }

    // MARK: Opening it

    /// Writes the scene's world into a fresh folder of its own, with what the app keeps of it
    /// in its settings, and returns the folder, for `Library` to load its worlds from.
    func writeWorld(now: Date = Date()) -> URL {
        var contents = fixture == .empty ? SampleWorld.empty() : SampleWorld.contents(now: now)
        contents.pages.insert(contentsOf: pages, at: 0)
        if newConversation { contents.lastConversation = UUID() } else if let conversation { contents.lastConversation = conversation }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Scene", isDirectory: true)
        do {
            try? FileManager.default.removeItem(at: root)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try SampleWorld.write(contents, to: root)
        } catch {
            fatalError("Scene \(name): the world couldn't be written: \(error)")
        }
        // As `Library` and `Companion` keep them (`openWorldKey`, `perWorld`, `instructions`).
        let defaults = UserDefaults.standard, world = contents.world.id.uuidString
        defaults.set(world, forKey: "openWorld")
        defaults.set(contents.unseen.map(\.uuidString), forKey: "unseen." + world)
        defaults.set(contents.lastConversation?.uuidString, forKey: "worldConversation." + world)
        defaults.set(contents.instructions, forKey: "companionInstruction")
        defaults.removeObject(forKey: "mapPlaces." + world)   // Connections lays out the same each time
        return root
    }

    /// Opens the scene's page, with the caret where it says, and its search.
    @MainActor func open(in library: Library) {
        if let id = start.page {
            library.selection = id
            if caretAtEnd, let page = library.pages.first(where: { $0.id == id }), let last = page.paragraphs.indices.last {
                library.cursor = (last, page.paragraphs[last].length)
            }
        }
        if let search { library.searchQuery = search }
    }

    /// What has to be on screen before the scene is ready (`SceneStage`).
    var waits: Set<SceneStage.Step> {
        var steps: Set<SceneStage.Step> = [.firstFrame]
        if shows != nil { steps.insert(.shown) }
        // Focus mode and a new page bring the keyboard up themselves.
        if keyboard || start.mode == .focus || start.page == Self.newPage { steps.insert(.keyboard) }
        if script != .ready && script != .downloadOffer { steps.insert(.held) }
        return steps
    }

    // MARK: The scenes

    /// Every scene, by the name CI and the docs use.
    static func named(_ name: String) -> LaunchScene? {
        typealias ID = SampleWorld.ID
        var scene = LaunchScene(name: name)
        func page(_ id: UUID, _ mode: LaunchStart.Mode = .read) {
            scene.start = LaunchStart(screen: .pages, page: id, mode: mode)   // opened from Pages
        }
        func focus(_ made: Document) {
            scene.pages = [made]
            scene.start = LaunchStart(screen: .pages, page: made.id, mode: .focus)
            scene.caretAtEnd = true
        }
        switch name {
        // The conversation
        case "talk": break
        case "talk-empty": scene.newConversation = true
        case "talk-thinking": scene.conversation = ID.conversationYesterday; scene.script = .thinking
        case "talk-streaming": scene.conversation = ID.conversationYesterday; scene.script = .streaming
        case "talk-failed": scene.conversation = ID.conversationYesterday; scene.script = .failed
        case "talk-download-offer": scene.script = .downloadOffer
        case "talk-downloading": scene.script = .downloading
        case "talk-filing": scene.script = .filing
        case "talk-composing": scene.keyboard = true; scene.typed = "the keeper's lamp went out the night"
        case "talk-long": scene.conversation = ID.conversationLastMonth
        // The drawer, Pages and Connections
        case "drawer": scene.start.drawer = true
        case "pages": scene.start.screen = .pages
        case "pages-empty": scene.start.screen = .pages; scene.fixture = .empty
        case "pages-deleted": scene.start.screen = .pages; scene.shows = .deleted
        case "pages-search": scene.start.screen = .pages; scene.search = "bell"
        case "connections": scene.start.screen = .connections
        case "connections-empty": scene.start.screen = .connections; scene.fixture = .empty
        // A page, read
        case "page-read": page(ID.mara)
        case "page-read-chapter": page(ID.nightTheBellRang)
        case "page-read-rumour": page(ID.masterCorwen)
        case "page-read-long-title": page(ID.chapterTwo)
        case "page-read-notes": page(ID.harbourNotes)
        // A page, in Edit mode
        case "page-edit": page(ID.mara, .edit)
        case "page-edit-typing": page(ID.harbourNotes, .edit); scene.keyboard = true; scene.caretAtEnd = true
        case "page-edit-chapter": page(ID.nightTheBellRang, .edit)
        case "page-edit-long-title": page(ID.chapterTwo, .edit)
        case "page-new":
            scene.pages = [Document(id: newPage)]
            page(newPage, .edit)
        case "page-mention":
            // Typing a link to Mara: the @ menu is open at the caret.
            scene.pages = [Document(id: mentionPage, title: "To Ask", paragraphs: [
                Paragraph(text: "Before the bell rings again:"), Paragraph(text: "Ask @Ma"),
            ])]
            page(mentionPage, .edit)
            scene.keyboard = true
            scene.caretAtEnd = true
        // Focus mode
        case "focus": focus(threeParagraphs)
        case "focus-controls": focus(threeParagraphs); scene.shows = .focusControls
        case "focus-empty": focus(Document(id: focusPage))
        case "focus-long": focus(oneLongParagraph)
        // Sheets and dialogs
        case "sheet-changes": scene.shows = .changes
        case "sheet-instructions": scene.shows = .instructions
        case "sheet-mentions": page(ID.mara, .edit); scene.shows = .mentions
        case "sheet-type-fields": page(ID.mara, .edit); scene.shows = .typeFields
        case "sheet-field": page(ID.mara, .edit); scene.shows = .field
        case "sheet-field-timeline": scene.shows = .fieldTimeline
        case "alert-new-world": scene.start.drawer = true; scene.shows = .newWorld
        default: return nil
        }
        return scene
    }

    /// Whether the view presenting `what` presents it in this scene: the one the scene shows,
    /// or the one it's reached through (a field's timeline is in Changes).
    func presents(_ what: Shows) -> Bool {
        shows == what || (what == .changes && shows == .fieldTimeline)
    }

    /// What `sheet-type-fields`, `sheet-field` and `sheet-field-timeline` open.
    static let character = SampleWorld.ID.Kind.character
    static let field = SampleWorld.ID.Field.species
    /// The guild's members, which today's conversation filed and then corrected.
    static let timeline = FieldKey(page: SampleWorld.ID.clockmakersGuild, field: SampleWorld.ID.Field.members)

    // MARK: Pages of the scenes' own

    private static func id(_ number: Int) -> UUID { UUID(uuidString: "5CE0E000-0000-4000-8000-\(String(format: "%012d", number))")! }
    static let newPage = id(1)
    static let mentionPage = id(2)
    static let focusPage = id(3)

    static let threeParagraphs = Document(id: focusPage, title: "The Last Ring", paragraphs: [
        Paragraph(text: "The bell rang once more, at the very end, and the whole harbour heard it."),
        Paragraph(text: "Mara was on the gallery with the lamp already lit."),
        Paragraph(text: "She knew who it was for before the sound had crossed the water."),
    ])

    static let oneLongParagraph = Document(id: focusPage, title: "The South Cove", paragraphs: [
        Paragraph(text: "Nobody lands in the south cove. The seals come back to it every year, the same ones, and the "
                  + "boats keep off, and nobody in Breakwater says why out loud, though every one of them knows. "
                  + "Mara's mother tried it once, the spring before the Petrel went down, and came back without her "
                  + "oars and would not say what she had seen on the stones."),
    ])
}
#endif
