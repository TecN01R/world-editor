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
    @State private var searching = false

    var body: some View {
        @Bindable var library = library
        let query = library.searchQuery
        // Searching: Spotlight's results, in its order, each with the line that matched.
        let results: [(page: WriterCore.Document, paragraph: Int?)] = library.searchResults.compactMap { found in
            guard let page = library.pages.first(where: { $0.id == found.page }) else { return nil }
            return (page, found.paragraph.flatMap { p in page.paragraphs.firstIndex { $0.id == p } })
        }
        List(selection: $selection) {
            if query.isEmpty {
                ForEach(library.pages) { row($0, snippet: nil) }
            } else {
                ForEach(results, id: \.page.id) { found in
                    row(found.page, snippet: found.paragraph.map { i in
                        found.page.excerpt(paragraph: i, at: found.page.offset(of: query, inParagraph: i) ?? 0)
                    })
                }
            }
        }
        .searchable(text: $library.searchQuery, prompt: "Search Pages")
        .searchSuggestions {
            ForEach(library.searchSuggestions, id: \.self) { Text($0).searchCompletion($0) }
        }
        .overlay {
            if !query.isEmpty, !searching, results.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .task(id: query) {
            searching = true
            guard !query.isEmpty else { library.searchResults = []; library.searchSuggestions = []; return }
            try? await Task.sleep(for: .milliseconds(150))   // let typing settle
            guard !Task.isCancelled else { return }
            library.searchResults = []
            await PageIndex.search(query) { results, suggestions in
                library.searchResults = results
                library.searchSuggestions = suggestions
            }
            searching = false
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

    private func row(_ page: WriterCore.Document, snippet: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(highlighted(page.heading.isEmpty ? "New Page" : page.heading))
                .font(.headline)
                .lineLimit(1)
            if let snippet {
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

    /// `text` with every search term in bold.
    private func highlighted(_ text: String) -> AttributedString {
        var s = AttributedString(text)
        for term in Search.terms(library.searchQuery) {
            var from = s.startIndex
            while let r = s[from...].range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
                s[r].inlinePresentationIntent = .stronglyEmphasized
                s[r].foregroundColor = .primary
                from = r.upperBound
            }
        }
        return s
    }
}

/// One page, in Edit mode or Focus mode.
struct EditorView: View {
    @Environment(Library.self) private var library
    @State private var showMentions = false
    @State private var typeName = ""
    @State private var pageName = ""
    @Binding var focusMode: Bool
    @Binding var focusControls: Bool
    let chromeHidden: Bool

    private var newType: Binding<Bool> {
        Binding { library.fieldsRequest == .newType } set: { if !$0 { library.fieldsRequest = nil } }
    }

    /// A page field's "New Place…": the field it fills.
    private var newPageField: FieldDefinition? {
        guard case .newPage(let id)? = library.fieldsRequest else { return nil }
        return library.schema.fields.first { $0.id == id }
    }
    private var newPage: Binding<Bool> {
        Binding { newPageField != nil } set: { if !$0 { library.fieldsRequest = nil } }
    }

    /// Adding or editing a field (New Type and New Page are alerts).
    private var fieldSheet: Binding<Library.FieldsRequest?> {
        Binding {
            switch library.fieldsRequest {
            case .addField?, .editField?: library.fieldsRequest
            default: nil
            }
        } set: { library.fieldsRequest = $0 }
    }

    /// "New Place", or "New Page" for a field that takes any page.
    private var newPageTitle: String {
        "New \(library.schema.type(newPageField?.pageType)?.name ?? "Page")"
    }

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
        .sheet(item: fieldSheet) { request in
            switch request {
            case .addField(let type): FieldSheet(type: type)
            case .editField(let id): FieldSheet(editing: library.schema.fields.first { $0.id == id })
            case .newType, .newPage: EmptyView()
            }
        }
        .alert("New Type", isPresented: newType) {
            TextField("Name, such as Character or Place", text: $typeName)
            Button("Cancel", role: .cancel) { typeName = "" }
            Button("Create") {
                let name = typeName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { library.addType(named: name) }
                typeName = ""
            }
        } message: {
            Text("Pages of a type share its fields.")
        }
        .alert(newPageTitle, isPresented: newPage, presenting: newPageField) { field in
            TextField("Title", text: $pageName)
            Button("Cancel", role: .cancel) { pageName = "" }
            Button("Create") {
                let title = pageName.trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    let page = library.addPage(titled: title, type: field.pageType)
                    library.update { $0.values[field.id] = .page(page) }
                }
                pageName = ""
            }
        } message: { field in
            Text("It becomes this page’s \(field.name).")
        }
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
