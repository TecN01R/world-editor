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
    private(set) var document: Document
    private let store: DocumentStore?
    private var saveTask: Task<Void, Never>?

    /// Caret position shared by both views so switching modes keeps your place.
    var cursor = (paragraph: 0, offset: 0)

    init() {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("Documents", isDirectory: true)
        let store = try? DocumentStore(directory: dir)
        self.store = store
        self.document = (try? store?.all())?.first ?? Document()
    }

    func update(_ change: (inout Document) -> Void) {
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
