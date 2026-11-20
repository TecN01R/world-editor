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

/// Holds the open document and saves it shortly after each edit.
@MainActor @Observable
final class Library {
    private(set) var document: WriterCore.Document
    private let store: DocumentStore?
    private var saveTask: Task<Void, Never>?

    /// Caret position shared by both views so switching modes keeps your place.
    var cursor = (paragraph: 0, offset: 0)

    init() {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("Documents", isDirectory: true)
        let store = try? DocumentStore(directory: dir)
        self.store = store
        self.document = (try? store?.all())?.first ?? WriterCore.Document()

        // Screenshot runs (CI): `-screenshotText "para one\npara two"` shows that
        // text instead of saved notes (`EMPTY` for a blank document). Nothing is
        // saved unless it's edited.
        if let seeded = UserDefaults.standard.string(forKey: "screenshotText") {
            let text = seeded == "EMPTY" ? "" : seeded.replacingOccurrences(of: "\\n", with: "\n")
            let paragraphs = text.components(separatedBy: "\n").map { Paragraph(text: $0) }
            document = WriterCore.Document(paragraphs: paragraphs)
            cursor = (paragraphs.count - 1, paragraphs.last?.text.count ?? 0)
        }
    }

    func update(_ change: (inout WriterCore.Document) -> Void) {
        change(&document)
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = document
        saveTask = Task { [store] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            try? store?.save(snapshot)
        }
    }
}
