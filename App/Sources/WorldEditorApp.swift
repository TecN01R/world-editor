import SwiftUI
import WriterCore

@main
struct WorldEditorApp: App {
    @State private var library = Library()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
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
            if let old = oldValue { discardIfEmpty(old) }
        }
    }

    /// Caret position shared by both editors so switching modes keeps your place.
    var cursor = (paragraph: 0, offset: 0)

    private let store: DocumentStore?
    private var saveTask: Task<Void, Never>?

    /// The open page (an empty one if none is open).
    var document: WriterCore.Document {
        pages.first { $0.id == selection } ?? WriterCore.Document()
    }

    init() {
        if Screenshots.isActive {
            store = nil                        // CI runs never touch saved pages
            pages = Screenshots.pages()
            if !Screenshots.opensList, let open = pages.first {
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
        if pages.isEmpty { newPage() } else { selection = pages.first?.id }
    }

    func newPage() {
        let page = WriterCore.Document()
        pages.insert(page, at: 0)
        selection = page.id
    }

    func delete(_ id: UUID) {
        if selection == id { selection = nil }
        pages.removeAll { $0.id == id }
        try? store?.delete(id)
    }

    /// Applies a user edit to the open page.
    func update(_ change: (inout WriterCore.Document) -> Void) {
        guard let i = pages.firstIndex(where: { $0.id == selection }) else { return }
        change(&pages[i])
        let page = pages.remove(at: i)
        pages.insert(page, at: 0)
        scheduleSave(page)
    }

    private func discardIfEmpty(_ id: UUID) {
        guard let page = pages.first(where: { $0.id == id }), page.isEmpty else { return }
        pages.removeAll { $0.id == id }
        try? store?.delete(id)
    }

    private func scheduleSave(_ page: WriterCore.Document) {
        saveTask?.cancel()
        saveTask = Task { [store] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            try? store?.save(page)
        }
    }
}

/// Launch arguments for CI screenshots (never used otherwise):
/// - `-screenshotText "para one\npara two"`: one page with that text (`EMPTY` for blank)
/// - `-screenshotRich YES`: one page showing bold, italic and both kinds of list
/// - `-screenshotPages YES`: several pages, showing the pages list
/// - `-startInFocus YES`: open the page in Focus mode (read by `RootView`)
/// - `-focusControls YES`: with Focus mode's controls showing (read by `RootView`)
/// - `-screenshotNewPage YES`: a new, empty page (cursor in its title)
/// - `-screenshotModels YES`: with the On-device Models sheet open (with `-screenshotPages`)
enum Screenshots {
    private static let defaults = UserDefaults.standard
    static var isActive: Bool { defaults.string(forKey: "screenshotText") != nil || isRich || opensList || isNewPage }
    static var opensList: Bool { defaults.bool(forKey: "screenshotPages") }
    static var isRich: Bool { defaults.bool(forKey: "screenshotRich") }
    static var isNewPage: Bool { defaults.bool(forKey: "screenshotNewPage") }
    static var showsModels: Bool { defaults.bool(forKey: "screenshotModels") }

    static func pages() -> [WriterCore.Document] {
        if isNewPage { return [WriterCore.Document()] }
        if let seeded = defaults.string(forKey: "screenshotText") {
            let text = seeded == "EMPTY" ? "" : seeded.replacingOccurrences(of: "\\n", with: "\n")
            return [WriterCore.Document(paragraphs: text.components(separatedBy: "\n").map { Paragraph(text: $0) })]
        }
        let rich = WriterCore.Document(title: "Harbour Notes", paragraphs: [
            Paragraph(text: "The tide came in faster than the charts promised.",
                      runs: [StyleRun(location: 17, length: 6, style: .italic)]),
            Paragraph(text: "Lantern oil", kind: .bullet),
            Paragraph(text: "Rope, two coils", kind: .bullet),
            Paragraph(text: "Check the north mooring", kind: .numbered,
                      runs: [StyleRun(location: 10, length: 5, style: .bold)]),
            Paragraph(text: "Ask about the bell", kind: .numbered),
        ])
        guard opensList else { return [rich] }
        let day: TimeInterval = 86_400
        return [
            rich,
            WriterCore.Document(title: "Characters", paragraphs: [Paragraph(text: "Mara keeps the lighthouse.")],
                                modified: Date().addingTimeInterval(-day)),
            WriterCore.Document(title: "Map of the Coast", paragraphs: [Paragraph(text: "Three coves, one road.")],
                                modified: Date().addingTimeInterval(-3 * day)),
        ]
    }
}
