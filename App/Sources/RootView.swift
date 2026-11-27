import Combine
import CoreSpotlight
import SwiftUI
import WidgetKit   // NSUserActivityTypeLiveActivity
import WriterCore

/// The world's conversation, its Connections or its Pages, or a page opened from one of them,
/// with the drawer beside it (`Drawer`). The conversation is where the author starts (Kevin,
/// 2026-11-27: "I want to write it conversationally or in any messy way ... and that populates
/// my pages"), and the last one they were in is where the app opens; the pages are where they
/// read their world. Folded, it's a stack (the drawer, then what's in front); unfolded, the
/// drawer slides over. Controls are standard toolbar items, so on iPhone Duo the system lays
/// them out in the side column.
struct RootView: View {
    /// What's in front when no page is open.
    enum Screen { case conversation, connections, pages }

    @Environment(Library.self) private var library
    @Environment(Companion.self) private var companion
    @State private var column: NavigationSplitViewColumn = Self.opensOnList ? .sidebar : .detail
    @State private var focusMode = Self.startsInFocus
    @State private var focusControls = false
    /// The world conversation shown when no page is open (a new one has its id before
    /// anything's said): the last one open, else the newest, else a new one.
    @State private var worldConversation: UUID?
    /// The page being edited; any other opens to be read, as a wiki entry (`EntryView`).
    @State private var editing: UUID?
    /// What's in front when no page is open, and what a page opened from it goes back to.
    @State private var screen = Screen.conversation
    /// Unfolded, the drawer is closed once the app has opened: the conversation (or page) in
    /// front, the drawer a tap away (open for CI's `Screenshots.opensList` shot).
    @State private var columns: NavigationSplitViewVisibility = Self.opensOnList ? .all : .detailOnly
    /// `settleList` has run, or isn't wanted: CI's shots stay where they open.
    @State private var listSettled = Screenshots.isActive
    /// The drawer as it was before Focus mode put it away, to put back after.
    @State private var columnsBeforeFocus: NavigationSplitViewVisibility?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    /// Regular unfolded, where the drawer slides over; compact folded, where it's a stack.
    @Environment(\.horizontalSizeClass) private var sizeClass

    private static var startsInFocus: Bool { UserDefaults.standard.bool(forKey: "startInFocus") }
    /// The app opens on the drawer, for its first layout before the conversation takes its
    /// place (`settleList`). CI's shots open where they're taken: on the drawer only for
    /// `Screenshots.opensList`.
    private static var opensOnList: Bool { !Screenshots.isActive || Screenshots.opensList }

    /// In Focus mode everything but the writing hides (bars, status, home
    /// indicator, drawer) until a tap outside the text brings it back.
    /// VoiceOver users keep the controls: hidden ones would be unreachable.
    private var chromeHidden: Bool { focusMode && !focusControls && !voiceOver }

    /// The screen in front, or nil while a page is open.
    private var inFront: Screen? { library.selection == nil ? screen : nil }

    var body: some View {
        // Focus mode takes the whole display: the drawer steps aside when unfolded.
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $column) {
            Drawer(titleInBar: sizeClass == .regular, current: inFront,
                   currentConversation: inFront == .conversation ? worldConversation : nil,
                   newConversation: startConversation,
                   openConversation: { worldConversation = $0; open(.conversation) },
                   openConnections: { open(.connections) }, openPages: { open(.pages) })
            .onAppear(perform: settleList)
        } detail: {
            detail
        }
        // Unfolded, the drawer slides over the page, in portrait and landscape alike, never
        // squeezing it (Kevin, 2026-11-24: "the drawer would slide over instead").
        .navigationSplitViewStyle(.prominentDetail)
        // Coming back to the app (its icon, the app switcher) opens nothing: it's where
        // the author left it, even while the companion's download runs. Only a tap on the
        // download's Live Activity shows the download (Kevin, 2026-11-24), in the world's
        // conversation, where the companion is. That Live Activity is iOS's own (the
        // continued-processing task), which documents no signal for the tap; if iOS sends
        // the Live Activity user activity, as for any Live Activity without a link, this
        // catches it.
        .onContinueUserActivity(NSUserActivityTypeLiveActivity) { _ in
            trialLog("LIVE ACTIVITY tap, download \(companion.download != nil)")   // TRIAL: does iOS send it?
            guard companion.download != nil, !focusMode else { return }
            open(.conversation)
        }
        // Each world has its own conversations; the last one open is shown, else the newest,
        // else a new one.
        .task(id: library.world.id) {
            companion.loadWorldConversations(in: library)
            worldConversation = library.lastWorldConversation ?? companion.worldConversations.first?.page ?? UUID()
        }
        // Another page opens to be read; the editor is for the page it was asked for on. CI's
        // shots are taken in the editor, where Focus mode is.
        .onChange(of: library.selection, initial: true) { _, page in
            if Screenshots.isActive { editing = page } else if page != editing { editing = nil }
        }
        // Applied at the root: status bar visibility is decided by the top controller.
        .statusBarHidden(chromeHidden)
        // Files this version couldn't read (a newer version's, or damaged): said once, kept as they are.
        .alert("Some of This World Couldn’t Be Read", isPresented: Binding { !library.unreadable.isEmpty } set: { shown in
            if !shown { library.unreadable = [] }
        }) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("World Editor couldn’t read \(library.unreadable.formatted(.list(type: .and))). They may be from a newer version of the app, or damaged. They’re kept exactly as they are and nothing is saved over them, so a version that reads them shows them again.")
        }
        // A page chosen in the system's Spotlight search opens here.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let id = (activity.userInfo?[CSSearchableItemActivityIdentifier] as? String).flatMap(UUID.init) {
                library.open(page: id)   // switching to its world if need be
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
            // Entering, the controls show and then fade on their usual timer
            // (or as soon as you type), so Exit Focus is in sight at first (Kevin).
            focusControls = focus
            // Unfolded, the drawer steps aside, and comes back only if it was out before
            // (always bringing it back opened the drawer over the page in portrait).
            if focus {
                columnsBeforeFocus = columns
                withAnimation { columns = .detailOnly }
            } else if let before = columnsBeforeFocus {
                withAnimation { columns = before }
            }
        }
    }

    /// What's beside the drawer (unfolded) or over it (folded): the open page, or else the
    /// screen in front.
    @ViewBuilder private var detail: some View {
        if let id = library.selection {
            // Read as a wiki entry (Kevin, 2026-11-27: "I do love reading a good wiki"); Edit for
            // the editor, and Read back.
            Group {
                if editing == id {
                    EditorView(focusMode: $focusMode, focusControls: $focusControls, chromeHidden: chromeHidden) { editing = nil }
                } else {
                    EntryView(page: library.document) { editing = id }
                }
            }
            .id(id)
            .lookBackground()
            // Back to where it was opened from, named, rather than to the drawer.
            .navigationBarBackButtonHidden(true)
            .toolbar {
                if !focusMode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(screenName, systemImage: "chevron.backward") { library.selection = nil }
                    }
                }
            }
        } else {
            switch screen {
            case .conversation: conversation
            case .connections:
                WorldMapView { library.selection = $0 }
                    .withDrawerButton(openDrawer, folded: sizeClass == .compact)
            case .pages:
                PageList {
                    library.newPage()
                    editing = library.selection   // a new page is for writing on
                }
                .withDrawerButton(openDrawer, folded: sizeClass == .compact)
            }
        }
    }

    /// What a page goes back to, by name.
    private var screenName: String {
        switch screen {
        case .conversation: "Conversation"
        case .connections: "Connections"
        case .pages: "Pages"
        }
    }

    /// The world conversation in front.
    @ViewBuilder private var conversation: some View {
        if let id = worldConversation {
            CompanionPanel(worldConversation: id, newConversation: startConversation)
            .task(id: id) {
                companion.open(library.worldSubject(id), in: library, aboutWorld: true)
                library.lastWorldConversation = id
            }
            // The one companion (Kevin, 2026-11-27: "radical enough or frictionless enough"):
            // open while its conversation is in front, so it has the model ready before the
            // author sends, and files what they said when they leave it (`Companion.isOpen`).
            .onAppear { companion.isOpen = true }
            .onDisappear { companion.isOpen = false }
            .withDrawerButton(openDrawer, folded: sizeClass == .compact)
        }
    }

    /// The drawer's rows grew and wobbled into place the first time it slid in after launch
    /// (Kevin, 2026-11-27: "all the menu entries wobble and grow and oscillate", the rows, the
    /// first time only): iOS sized them for the first time inside the slide's animation. So the
    /// app opens on the drawer, and once it's laid out (the next turn of the main loop, within
    /// the launch's own animation) the conversation takes its place at once.
    private func settleList() {
        guard !listSettled else { return }
        listSettled = true
        DispatchQueue.main.async {
            withTransaction(\.disablesAnimations, true) {
                column = .detail
                columns = .detailOnly
            }
        }
    }

    /// `screen` in front, leaving the page (an empty one is discarded).
    private func open(_ screen: Screen) {
        self.screen = screen
        library.selection = nil
        column = .detail
        closeDrawer()
    }

    /// A new world conversation, in place of the one open (which stays in the drawer).
    private func startConversation() {
        worldConversation = UUID()
        open(.conversation)
    }

    /// The drawer: folded, back to it; unfolded, sliding over.
    private func openDrawer() {
        if sizeClass == .regular { withAnimation { columns = .all } } else { column = .sidebar }
    }

    /// Unfolded, a choice in the drawer (a conversation, Connections, Pages, a new one)
    /// closes it to show what was chosen, as iOS's own drawer does in portrait (Kevin,
    /// 2026-11-24). Only the author's choices: the drawer is left where iOS and the author
    /// put it as the Duo folds, unfolds and rotates (moving it then too crashed iOS's split
    /// view, 2026-11-24).
    private func closeDrawer() {
        if sizeClass == .regular { withAnimation { columns = .detailOnly } }
    }
}

/// The world's pages, by kind, with search and Recently Deleted: the Pages screen, opened from
/// the drawer.
struct PageList: View {
    @Environment(Library.self) private var library
    let newPage: () -> Void
    @State private var searching = false
    /// Showing Recently Deleted in place of the pages.
    @State private var showingDeleted = false
    /// A deleted page whose choices (recover, delete now) are showing.
    @State private var choosing: WriterCore.Document?
    @State private var renaming: PageType?
    @State private var deleting: PageType?
    @State private var newName = ""
    /// A kind of page whose fields are being edited, from its heading.
    @State private var editingFields: PageType?

    var body: some View {
        @Bindable var library = library
        let query = library.searchQuery
        // Searching: Spotlight's results, in its order, each with the line that matched.
        let results: [(page: WriterCore.Document, paragraph: Int?)] = library.searchResults.compactMap { found in
            guard let page = library.pages.first(where: { $0.id == found.page }) else { return nil }
            return (page, found.paragraph.flatMap { p in page.paragraphs.firstIndex { $0.id == p } })
        }
        List(selection: $library.selection) {
            if query.isEmpty {
                if showingDeleted, !library.recentlyDeleted.isEmpty {
                    Section {
                        ForEach(library.recentlyDeleted) { deletedRow($0) }
                    } header: {
                        Text("Recently Deleted")
                    } footer: {
                        Text("Pages are deleted for good after 30 days.")
                    }
                } else {
                    // The pages, under their kind (Characters, Places…), as a book's contents
                    // rather than a database (Kevin, 2026-11-27, of the list with its Types section:
                    // "This looks awful and not inviting or relaxing or frictionless").
                    ForEach(groups, id: \.type?.id) { group in
                        Section {
                            ForEach(group.pages) { row($0, snippet: nil) }
                        } header: {
                            if let heading = group.heading {
                                // Each kind's own options, on its heading (Kevin, 2026-11-27: "shouldn't
                                // the edit character fields be also in the header label for each").
                                if let type = group.type {
                                    Text(heading).contextMenu { kindMenu(type) }
                                } else {
                                    Text(heading)
                                }
                            }
                        }
                    }
                }
                // Out of the way at the bottom, as Notes and Photos keep it (Kevin, 2026-11-24: cluttered).
                if !library.recentlyDeleted.isEmpty {   // tapped again, back to the pages
                    Section {
                        Button {
                            withAnimation { showingDeleted.toggle() }
                        } label: {
                            HStack {
                                Label("Recently Deleted", systemImage: "trash")
                                Spacer()
                                if showingDeleted { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .tint(.secondary)
                        .selectionDisabled()
                        .accessibilityAddTraits(showingDeleted ? .isSelected : [])
                        .accessibilityHint(showingDeleted ? "Shows your pages" : "Shows the pages you deleted")
                        .calmRow()
                    }
                }
            } else {
                ForEach(results, id: \.page.id) { found in
                    row(found.page, snippet: found.paragraph.map { i in
                        found.page.excerpt(paragraph: i, at: found.page.offset(of: query, inParagraph: i) ?? 0)
                    })
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $library.searchQuery, prompt: "Search Pages")
        .searchSuggestions {
            ForEach(library.searchSuggestions, id: \.self) { Text($0).searchCompletion($0) }
        }
        .overlay {
            if !query.isEmpty {
                if !searching, results.isEmpty { ContentUnavailableView.search(text: query) }
            } else if library.pages.isEmpty, !showingDeleted {
                ContentUnavailableView("No Pages Yet", systemImage: "books.vertical",
                                       description: Text("Your world’s pages appear here as you talk about it in the conversation."))
            }
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
        .alert("Rename Type", isPresented: Binding { renaming != nil } set: { if !$0 { renaming = nil } },
               presenting: renaming) { type in
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { library.renameType(type.id, to: name) }
            }
        }
        .onChange(of: library.recentlyDeleted.isEmpty) { _, empty in
            if empty { showingDeleted = false }   // its row is gone; back to the pages
        }
        .onChange(of: library.world.id) { showingDeleted = false }   // it belongs to the world it was shown in
        // From a kind's heading: deleting it asks first.
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?",
                            isPresented: Binding { deleting != nil } set: { if !$0 { deleting = nil } },
                            titleVisibility: .visible, presenting: deleting) { type in
            Button("Delete Type", role: .destructive) { library.deleteType(type.id) }
        } message: { type in
            Text(Self.deletingTypeMessage(pages: library.pageCount(ofType: type.id)))
        }
        .lookBackground()
        .navigationTitle("Pages")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingFields) { TypeFieldsSheet(type: $0.id) }
        .toolbar {
            // Kevin, 2026-11-24: search at the very bottom, New Page in its usual place at the
            // top. Search where iOS puts it (he asked for the Duo's best practice): in the
            // bottom bar, which the folded Duo's side column shows as a button.
            // New Page is the screen's one main action, pinned (docs/design.md): as a primary
            // action, even at high priority, iOS put it alone unfolded in a "•••" menu the same
            // size as the button (Kevin, 2026-11-24); a pinned item goes there only while
            // searching with no room.
            ToolbarItem(placement: .topBarPinnedTrailing) {
                Button("New Page", systemImage: "doc.badge.plus") {
                    showingDeleted = false   // the new page shows in the list
                    newPage()
                }
                .keyboardShortcut("n")
            }
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
        }
    }

    /// A page; searching, with the line that matched in place of how it begins.
    private func row(_ page: WriterCore.Document, snippet: String?) -> some View {
        PageRow(page: page, line: snippet, marking: Search.terms(library.searchQuery))
            .calmRow()
            .swipeActions {
                Button("Delete", systemImage: "trash", role: .destructive) { library.delete(page.id) }
            }
    }

    /// A kind of page's own options, from its heading: its fields, its name, or it gone.
    @ViewBuilder private func kindMenu(_ type: PageType) -> some View {
        Button("Edit Fields\u{2026}", systemImage: "list.bullet.rectangle") { editingFields = type }
        Button("Rename\u{2026}", systemImage: "pencil") { rename(type) }
        Button("Delete\u{2026}", systemImage: "trash", role: .destructive) { deleting = type }
    }

    /// A section of the pages list: one type's pages under its heading, or the rest's.
    private typealias PageGroup = (type: PageType?, heading: String?, pages: [WriterCore.Document])

    /// The pages by kind: each type's, in the types' order, under its name in the plural;
    /// then the rest, headed "Other Pages" only when some pages are typed. Empty kinds are
    /// left out.
    private var groups: [PageGroup] {
        let typed = library.schema.types.compactMap { type -> PageGroup? in
            let pages = library.pages.filter { $0.type == type.id }
            return pages.isEmpty ? nil : (type, Self.plural(type.name), pages)
        }
        let known = Set(library.schema.types.map(\.id))
        let others = library.pages.filter { $0.type.map { !known.contains($0) } ?? true }
        guard !others.isEmpty else { return typed }
        return typed + [(nil, typed.isEmpty ? nil : "Other Pages", others)]
    }

    /// A kind of page in the plural ("Character", "Characters"), by Foundation's grammar
    /// agreement; as it is where that doesn't know the word.
    private static func plural(_ name: String) -> String {
        var morphology = Morphology()
        morphology.number = .plural
        var text = AttributedString(name)
        text.inflect = InflectionRule(morphology: morphology)
        return String(text.inflected().characters)
    }

    private static func deletingTypeMessage(pages count: Int) -> String {
        switch count {
        case 0: "No pages use it."
        case 1: "1 page uses it. It’ll have no type; its field values stay saved."
        default: "\(count) pages use it. They’ll have no type; their field values stay saved."
        }
    }

    /// A page in Recently Deleted: tap for Recover or Delete Now; swipe
    /// right to recover.
    private func deletedRow(_ page: WriterCore.Document) -> some View {
        let title = page.displayName, days = page.daysLeft() ?? 0
        return Button { choosing = page } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.authored(.headline)).lineLimit(1)
                Text(days == 1 ? "1 day left" : "\(days) days left").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .tint(.primary)
        .selectionDisabled()
        .accessibilityHint("Recover it, or delete it now")
        .calmRow()
        .swipeActions(edge: .leading) {
            Button("Recover", systemImage: "arrow.uturn.backward") { library.recover(page.id) }.tint(.gray)
        }
        .swipeActions(allowsFullSwipe: false) {
            Button("Delete Now", systemImage: "trash") { choosing = page }.tint(.red)
        }
        .confirmationDialog(title, isPresented: Binding { choosing?.id == page.id } set: { if !$0 { choosing = nil } },
                            titleVisibility: .visible) {
            Button("Recover Page") { library.recover(page.id) }
            Button("Delete Now", role: .destructive) { library.deleteForGood(page.id) }
        } message: {
            Text("Deleting it now can’t be undone.")
        }
    }

    private func rename(_ type: PageType) {
        newName = type.name
        renaming = type
    }
}

/// A page as every list of pages shows it (Pages, Mentions, a page's "Mentioned In"): its name,
/// then how it begins, or the line the list has for it in its place (a search's match, a quote);
/// what's on it, not its bookkeeping. A white dot while the companion has made or added to it
/// and the author hasn't opened it (`Library.unseen`).
struct PageRow: View {
    @Environment(Library.self) private var library
    let page: WriterCore.Document
    /// The line under the name in place of how the page begins.
    var line: String?
    /// Words to show in bold in the name and that line: a search's terms.
    var marking: [String] = []
    /// How many lines the line under the name may take; nil for as many as it needs.
    var lineLimit: Int? = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(marked(page.displayName))
                    .font(.authored(.headline))
                    .lineLimit(1)
                if library.unseen.contains(page.id) {
                    Circle()
                        .fill(Color(Look.emphasis))
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("New")
                }
            }
            if let line = line.map(marked) ?? (page.preview.isEmpty ? nil : AttributedString(page.preview)) {
                Text(line)
                    .font(.authored(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(lineLimit)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// `text` with every word of `marking` in bold.
    private func marked(_ text: String) -> AttributedString {
        var s = AttributedString(text)
        for term in marking {
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
    /// Back to reading the page (`EntryView`).
    let read: () -> Void

    private var newType: Binding<Bool> {
        Binding { library.fieldsRequest == .newType } set: { if !$0 { library.fieldsRequest = nil } }
    }

    /// The keyboard is up (in Focus mode, only ever its writing's).
    @State private var typing = false
    /// The page has the keyboard (its writing, title or a field), not anything else (search
    /// in the pages list, an alert): the toolbar is for editing then.
    @State private var editing = false
    /// The page's writing has the keyboard (not its title or a field).
    @State private var writing = false

    /// Closes the keyboard (the iPhone keyboard has no key for it) and, in
    /// Focus, leaves it: Focus is for editing, so there's nothing to stay for.
    private var doneButton: some View {
        Button("Done", systemImage: "checkmark") {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            // Done now, not when the keyboard's notice arrives: the page coming
            // back from Focus would otherwise take the keyboard straight back.
            typing = false
            if focusMode { withAnimation(.smooth(duration: 0.3)) { focusMode = false } }
        }
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
            case .addField?, .editField?, .editFields?: library.fieldsRequest
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
                PageEditor(keepsKeyboard: typing, onWriting: { writing = $0 }, onEditing: { editing = $0 }) {   // stops at the keyboard, as iOS lays pages out
                    withAnimation(.smooth(duration: 0.3)) { focusMode = true }
                }
                    .transition(.opacity)
                    .onDisappear { (editing, writing) = (false, false) }   // to Focus mode, which has its own
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
        // While the page has the keyboard, Done shows, as in Notes. Focus is for
        // writing, so the keyboard going down (Done, or swiped away) leaves it (Kevin).
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in typing = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            typing = false
            if focusMode { withAnimation(.smooth(duration: 0.3)) { focusMode = false } }
        }
        .sheet(isPresented: $showMentions) { MentionsView() }
        .sheet(item: fieldSheet) { request in
            switch request {
            case .addField(let type): FieldSheet(type: type)
            case .editField(let id): FieldSheet(editing: library.schema.fields.first { $0.id == id })
            case .editFields(let type): TypeFieldsSheet(type: type)
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
                    Button("Exit Focus", systemImage: "arrow.down.right.and.arrow.up.left") {
                        withAnimation(.smooth(duration: 0.3)) { focusMode = false }
                    }
                    .keyboardShortcut(.cancelAction)
                }
                // Done here also leaves Focus, an editing-only mode (Kevin).
                if typing { ToolbarItem(placement: .confirmationAction) { doneButton } }
            } else if editing {
                // Editing the page, folded and unfolded alike (Kevin, 2026-11-24): Back or the
                // sidebar button, Focus, and Done (the iPhone keyboard has no key to close it),
                // each its own button, never in "•••". Read and More wait for
                // the keyboard to go down: folded, the side column above the keyboard holds
                // only three buttons (with a menu as well, iOS put Done in a "•••" of its own;
                // "just looks terrible"). (Swapping the bar while any keyboard was up, search's
                // or an alert's, hid the sidebar button.)
                // Focus is for the writing: offered only while it has the keyboard, not the
                // title or a field (Kevin). Where iOS puts the bar's buttons, with Done (Kevin,
                // 2026-11-24).
                if writing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right") {
                            withAnimation(.smooth(duration: 0.3)) { focusMode = true }
                        }
                    }
                    .visibilityPriority(.high)
                }
                ToolbarItem(placement: .confirmationAction) { doneButton }
            } else {
                // Read is the screen's one main action, pinned; the rest in More (docs/design.md).
                ToolbarItem(placement: .topBarPinnedTrailing) { Button("Read", systemImage: "book", action: read) }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Mentions", systemImage: "at") { showMentions = true }
                    } label: { Label("More", systemImage: "ellipsis") }
                }
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
                    PageRow(page: page)
                }
                .tint(.primary)
                .calmRow()
            }
            .listStyle(.plain)   // as the pages list: plain, no lines between rows
            .overlay {
                if mentions.isEmpty {
                    ContentUnavailableView("No Mentions", systemImage: "at",
                                           description: Text("Pages that link here with @ or in a field show up here."))
                }
            }
            .lookBackground()
            .navigationTitle("Mentions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            // A stock sheet: its bar across the top, not in the folded Duo's side column.
            .toolbarVerticalBehavior(.disabled)
        }
        .presentationDetents([.medium, .large])
    }
}

private extension View {
    /// A pages-list row with no line between it and the next: the list as a book's contents
    /// rather than a settings screen (Kevin, 2026-11-27).
    func calmRow() -> some View {
        listRowSeparator(.hidden)
    }

    /// Folded, the drawer's button where Back would be, as ChatGPT has it (Kevin, 2026-11-27:
    /// "an easy way to see all conversations"); unfolded, iOS's own sidebar button does it.
    @ViewBuilder func withDrawerButton(_ open: @escaping () -> Void, folded: Bool) -> some View {
        if folded {
            navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Conversations and Pages", systemImage: "sidebar.leading", action: open)
                    }
                }
        } else {
            self
        }
    }
}
