import CoreSpotlight
import SwiftUI
import WriterCore

/// Pages list beside the open page. Folded, it's a stack (list, then page);
/// unfolded, the list sits alongside. Controls are standard toolbar items, so
/// on iPhone Duo the system lays them out in the side column.
struct RootView: View {
    @Environment(Library.self) private var library
    @State private var column: NavigationSplitViewColumn = Screenshots.opensList ? .sidebar : .detail
    @State private var focusMode = Self.startsInFocus
    @State private var focusControls = false
    @State private var columns: NavigationSplitViewVisibility = Self.startsInFocus ? .detailOnly : .all
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    private static var startsInFocus: Bool { UserDefaults.standard.bool(forKey: "startInFocus") }

    /// In Focus mode everything but the writing hides (bars, status, home
    /// indicator, pages list) until a tap outside the text brings it back.
    /// VoiceOver users keep the controls: hidden ones would be unreachable.
    private var chromeHidden: Bool { focusMode && !focusControls && !voiceOver }

    var body: some View {
        @Bindable var library = library
        // Focus mode takes the whole display: the pages list steps aside when unfolded.
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $column) {
            PageList(selection: $library.selection) {
                library.newPage()
                column = .detail
            }
        } detail: {
            if let id = library.selection {
                EditorView(focusMode: $focusMode, focusControls: $focusControls, chromeHidden: chromeHidden).id(id)
            } else {
                ContentUnavailableView("No Page Open", systemImage: "doc.text",
                                       description: Text("Choose a page or start a new one."))
            }
        }
        // Applied at the root: status bar visibility is decided by the top controller.
        .statusBarHidden(chromeHidden)
        // A page chosen in the system's Spotlight search opens here.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let id = (activity.userInfo?[CSSearchableItemActivityIdentifier] as? String).flatMap(UUID.init) {
                library.selection = id
                column = .detail
            }
        }
        .persistentSystemOverlays(chromeHidden ? .hidden : .automatic)
        // CI shot of revealed controls: reveal after launch, the way a tap would,
        // rather than starting revealed (a path no user ever takes).
        .task {
            guard UserDefaults.standard.bool(forKey: "focusControls") else { return }
            try? await Task.sleep(for: .seconds(1.5))
            focusControls = true
        }
        .onChange(of: focusMode) { _, focus in
            focusControls = false
            withAnimation { columns = focus ? .detailOnly : .all }   // unfolded: list beside the page
        }
    }
}

struct PageList: View {
    @Environment(Library.self) private var library
    @Binding var selection: UUID?
    let newPage: () -> Void
    @State private var showModels = false
    @State private var query = Screenshots.searchQuery ?? ""
    @State private var related: [UUID] = []

    var body: some View {
        // Pages with the words first (instant), then those Spotlight finds by meaning.
        let words = query.isEmpty ? library.pages : library.pages.filter { $0.matches(query) }
        let byMeaning = related.compactMap { id in
            words.contains { $0.id == id } ? nil : library.pages.first { $0.id == id }
        }
        List(selection: $selection) {
            ForEach(words, content: row)
            if !byMeaning.isEmpty {
                Section("Related") { ForEach(byMeaning, content: row) }
            }
        }
        .searchable(text: $query, prompt: "Search Pages")
        .overlay {
            if !query.isEmpty, words.isEmpty, byMeaning.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .task(id: query) {
            related = []
            guard query.count >= 3 else { return }
            try? await Task.sleep(for: .milliseconds(300))   // let typing settle
            guard !Task.isCancelled else { return }
            related = await PageIndex.search(query)
        }
        .navigationTitle("Pages")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Page", systemImage: "square.and.pencil", action: newPage)
                    .keyboardShortcut("n")
            }
            // Its own glass capsule, apart from New Page.
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button("On-device Models", systemImage: "cpu") { showModels = true }
            }
        }
        .sheet(isPresented: $showModels) { ModelsView() }
    }

    private func row(_ page: WriterCore.Document) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(highlighted(page.heading.isEmpty ? "New Page" : page.heading))
                .font(.headline)
                .lineLimit(1)
            if let snippet = page.snippet(matching: query) {
                // Searching: the line that matched, in place of date and preview.
                Text(highlighted(snippet)).lineLimit(1)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    Text(page.modified, format: .relative(presentation: .named))
                    if !page.preview.isEmpty { Text(page.preview).lineLimit(1) }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { library.delete(page.id) }
        }
    }

    /// `text` with the search match in bold.
    private func highlighted(_ text: String) -> AttributedString {
        var s = AttributedString(text)
        if !query.isEmpty, let r = s.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            s[r].inlinePresentationIntent = .stronglyEmphasized
            s[r].foregroundColor = .primary
        }
        return s
    }
}

/// One page, in Edit mode or Focus mode.
struct EditorView: View {
    @State private var showMentions = false
    @Binding var focusMode: Bool
    @Binding var focusControls: Bool
    let chromeHidden: Bool

    var body: some View {
        ZStack {
            if focusMode {
                FocusEditor(showsControls: $focusControls)
                    .ignoresSafeArea()   // the whole display; bars appear over it
                    .transition(.opacity)
            } else {
                PageEditor()
                    .ignoresSafeArea(.keyboard)   // text scrolls behind the glass format bar, as in Notes
                    .transition(.opacity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // Focus is a mode you step into, so revealing its controls shows only
        // a close button, as full-screen modes do on iOS; no back arrow or
        // sidebar button. The bar draws over the writing, which ignores the
        // safe area and so never reflows.
        .toolbar(chromeHidden ? .hidden : .automatic, for: .navigationBar)
        .navigationBarBackButtonHidden(focusMode)
        .toolbar(removing: focusMode ? .sidebarToggle : nil)
        .animation(.easeInOut(duration: 0.25), value: chromeHidden)
        .sheet(isPresented: $showMentions) { MentionsView() }
        .task {
            // CI: open Mentions once the page is up and writing, as a tap would.
            guard Screenshots.showsMentions else { return }
            try? await Task.sleep(for: .seconds(1))
            showMentions = true
        }
        .toolbar {
            if focusMode {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close Focus", systemImage: "xmark") {
                        withAnimation(.smooth(duration: 0.3)) { focusMode = false }
                    }
                    .keyboardShortcut(.cancelAction)
                }
            } else {
                // Pinned: stays put as the bar narrows (the folded side column).
                ToolbarItem(placement: .topBarPinnedTrailing) {
                    Button("Focus", systemImage: "text.viewfinder") {
                        withAnimation(.smooth(duration: 0.3)) { focusMode = true }
                    }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                }
                // Shown when there's room; first into "•••" when folded.
                ToolbarItem(placement: .primaryAction) {
                    Button("Mentions", systemImage: "at") { showMentions = true }
                }
                .visibilityPriority(.low)
            }
        }
    }
}

/// The pages that `@`-link to the open page. A sheet, as content to browse
/// rather than commands: half height to glance, full to read; tapping one opens it.
struct MentionsView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let mentions = library.mentions(of: library.document.id)
        NavigationStack {
            List(mentions) { page in
                Button {
                    dismiss()
                    library.selection = page.id
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(page.heading.isEmpty ? "New Page" : page.heading).font(.headline)
                        if !page.preview.isEmpty {
                            Text(page.preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                .tint(.primary)
            }
            .overlay {
                if mentions.isEmpty {
                    ContentUnavailableView("No Mentions", systemImage: "at",
                                           description: Text("Pages that link here with @ show up here."))
                }
            }
            .navigationTitle("Mentions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
