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
        }
    }
}

/// All pages, the one that's open, and saving shortly after each edit.
@MainActor @Observable
final class Library {
    /// Most recently edited first.
    private(set) var pages: [WriterCore.Document] = []

    /// The open page. Leaving a page that was never written in discards it.
    var selection: UUID? {
        didSet {
            guard oldValue != selection else { return }
            cursor = (0, 0)
            if let old = oldValue { flush(old); discardIfEmpty(old) }
        }
    }

    /// Caret position shared by both editors so switching modes keeps your place.
    var cursor = (paragraph: 0, offset: 0)

    private let store: DocumentStore?
    /// Pending debounced saves, one per page, so editing one page never drops another's.
    private var pendingSaves: [UUID: Task<Void, Never>] = [:]

    /// The open page (an empty one if none is open).
    var document: WriterCore.Document {
        pages.first { $0.id == selection } ?? WriterCore.Document()
    }

    init() {
        if Screenshots.isActive {
            store = nil                        // CI runs never touch saved pages
            pages = Screenshots.pages()
            // Mentions: Mara's page, which Harbour Notes links to.
            if !Screenshots.opensList, let open = Screenshots.showsMentions ? pages[1] : pages.first {
                selection = open.id
                // Typed text: caret at its end. Rich sample: at the top, title in view.
                let last = open.paragraphs.count - 1
                if !Screenshots.isRich { cursor = (last, open.paragraphs[last].length) }
            }
            return
        }
        let dir = URL.applicationSupportDirectory.appendingPathComponent("Documents", isDirectory: true)
        store = try? DocumentStore(directory: dir)
        pages = (try? store?.all()) ?? []
        PageIndex.start(with: pages)
        if pages.isEmpty { newPage() } else { selection = pages.first?.id }
    }

    func newPage() {
        let page = WriterCore.Document()
        pages.insert(page, at: 0)
        selection = page.id
    }

    /// A titled page for an `@` mention, saved but not opened.
    func addPage(titled title: String) -> UUID {
        let page = WriterCore.Document(title: title)
        pages.insert(page, at: min(1, pages.count))   // just behind the open page
        scheduleSave(page)
        return page.id
    }

    /// Pages with an `@` link to `id`, most recent first.
    func mentions(of id: UUID) -> [WriterCore.Document] {
        pages.filter { $0.id != id && $0.mentions(id) }
    }

    func delete(_ id: UUID) {
        pendingSaves.removeValue(forKey: id)?.cancel()
        if selection == id { selection = nil }
        pages.removeAll { $0.id == id }
        try? store?.delete(id)
        if store != nil { PageIndex.remove(id) }
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
        pendingSaves[page.id] = Task { [store] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let store else { return }
            try? store.save(page)
            PageIndex.update(page)
        }
    }

    /// Saves a page now if it has an edit waiting (leaving it, or the app going away).
    func flush(_ id: UUID) {
        guard let task = pendingSaves.removeValue(forKey: id) else { return }
        task.cancel()
        if let store, let page = pages.first(where: { $0.id == id }), !page.isEmpty {
            try? store.save(page)
            PageIndex.update(page)
        }
    }

    func flushAll() { for id in Array(pendingSaves.keys) { flush(id) } }
}

/// Launch arguments for CI screenshots (never used otherwise):
/// - `-screenshotText "para one\npara two"`: a page with that text (`EMPTY` for blank)
/// - `-screenshotRich YES`: one page showing bold, italic and both kinds of list
/// - `-screenshotMentions YES`: with `-screenshotRich`, Mara's page with its Mentions sheet open
/// - `-screenshotPages YES`: showing the pages list
/// - `-screenshotSearch light`: with `-screenshotPages`, searching the list
/// Each seeds two more pages, so `@` has something to find.
/// - `-startInFocus YES`: open the page in Focus mode (read by `RootView`)
/// - `-focusControls YES`: with Focus mode's controls showing (read by `RootView`)
enum Screenshots {
    private static let defaults = UserDefaults.standard
    static var isActive: Bool { defaults.string(forKey: "screenshotText") != nil || isRich || opensList }
    static var opensList: Bool { defaults.bool(forKey: "screenshotPages") }
    static var isRich: Bool { defaults.bool(forKey: "screenshotRich") }
    static var showsMentions: Bool { defaults.bool(forKey: "screenshotMentions") }
    static var searchQuery: String? { defaults.string(forKey: "screenshotSearch") }

    static func pages() -> [WriterCore.Document] {
        let day: TimeInterval = 86_400
        let mara = WriterCore.Document(title: "Mara", paragraphs: [Paragraph(text: "Keeps the lighthouse.")],
                                       modified: Date().addingTimeInterval(-day))
        let map = WriterCore.Document(title: "Map of the Coast", paragraphs: [Paragraph(text: "Three coves, one road.")],
                                      modified: Date().addingTimeInterval(-3 * day))
        if let seeded = defaults.string(forKey: "screenshotText") {
            let text = seeded == "EMPTY" ? "" : seeded.replacingOccurrences(of: "\\n", with: "\n")
            return [WriterCore.Document(paragraphs: text.components(separatedBy: "\n").map { Paragraph(text: $0) }), mara, map]
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
        return [rich, mara, map]
    }
}
