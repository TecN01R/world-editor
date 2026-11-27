import Combine
import CoreSpotlight
import SwiftUI
import WidgetKit   // NSUserActivityTypeLiveActivity
import WriterCore

/// The world's conversation (or its Connections), or the open page, with the pages list beside
/// it. The conversation is where the author starts (Kevin, 2026-11-27: "I want to write it
/// conversationally or in any messy way ... and that populates my pages"): it shows whenever
/// no page or Connections is open, and the pages are where they read their world. Folded, it's a
/// stack (list, then conversation or page); unfolded, the list is a drawer. Controls are standard
/// toolbar items, so on iPhone Duo the system lays them out in the side column.
struct RootView: View {
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
    /// Connections (`WorldMapView`) is in front when no page is open, in place of the conversation.
    @State private var showingMap = false
    /// Unfolded, the drawer is closed once the app has opened: the conversation (or page) in
    /// front, the drawer a tap away (open for CI's shot of the pages list).
    @State private var columns: NavigationSplitViewVisibility = Self.opensOnList ? .all : .detailOnly
    /// `settleList` has run, or isn't wanted: CI's shots stay where they open.
    @State private var listSettled = Screenshots.isActive
    /// The pages list as it was before Focus mode put it away, to put back after.
    @State private var columnsBeforeFocus: NavigationSplitViewVisibility?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    /// Unfolded: the pages list is a sidebar beside the page.
    @Environment(\.horizontalSizeClass) private var sizeClass

    private static var startsInFocus: Bool { UserDefaults.standard.bool(forKey: "startInFocus") }
    /// The app opens on the pages list, for its first layout before the conversation takes
    /// its place (`settleList`). CI's shots open where they're taken: on the list only for
    /// the list's own shot.
    private static var opensOnList: Bool { !Screenshots.isActive || Screenshots.opensList }

    /// In Focus mode everything but the writing hides (bars, status, home
    /// indicator, pages list) until a tap outside the text brings it back.
    /// VoiceOver users keep the controls: hidden ones would be unreachable.
    private var chromeHidden: Bool { focusMode && !focusControls && !voiceOver }

    var body: some View {
        // Focus mode takes the whole display: the pages list steps aside when unfolded.
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $column) {
            PageList(selection: Binding { library.selection } set: {
                library.selection = $0
                if $0 != nil { closeDrawer() }
            }, titleInBar: sizeClass == .regular,
               current: library.selection == nil && !showingMap ? worldConversation : nil,
               newConversation: startConversation, openConversation: { worldConversation = $0; openConversation() },
               openMap: openMap) {
                library.newPage()
                editing = library.selection   // a new page is for writing on
                column = .detail
                closeDrawer()
            }
            .onAppear(perform: settleList)
        } detail: {
            detail
        }
        // Unfolded, the pages list is a drawer that slides over the page, in portrait and
        // landscape alike, never squeezing it (Kevin, 2026-11-24: "the drawer would slide
        // over instead").
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
            openConversation()
        }
        // Each world has its own conversation, in front whenever no page is open.
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
            // Unfolded, the pages list steps aside, and comes back only if it was out before
            // (always bringing it back opened the drawer over the page in portrait).
            if focus {
                columnsBeforeFocus = columns
                withAnimation { columns = .detailOnly }
            } else if let before = columnsBeforeFocus {
                withAnimation { columns = before }
            }
        }
    }

    /// What's beside the pages list (unfolded) or over it (folded): the open page, or else
    /// the world's conversation.
    @ViewBuilder private var detail: some View {
        if let id = library.selection {
            // Read as a wiki entry (Kevin, 2026-11-27: "I do love reading a good wiki"); Edit for
            // the editor, and Read back.
            Group {
                if editing == id {
                    EditorView(focusMode: $focusMode, focusControls: $focusControls, chromeHidden: chromeHidden) { editing = nil }
                } else {
                    EntryView(page: library.document, talk: openConversation) { editing = id }
                }
            }
            .id(id)
            .lookBackground()
        } else if showingMap {
            WorldMapView { library.selection = $0 }
        } else if let id = worldConversation {
            CompanionPanel(worldConversation: id, newConversation: startConversation, openMap: openMap)
            .task(id: id) {
                companion.open(library.worldSubject(id), in: library, aboutWorld: true)
                library.lastWorldConversation = id
            }
            // The one companion (Kevin, 2026-11-27: "radical enough or frictionless enough"):
            // open while its conversation is in front, so it has the model ready before the
            // author sends, and files what they said when they leave it (`Companion.isOpen`).
            .onAppear { companion.isOpen = true }
            .onDisappear { companion.isOpen = false }
        }
    }

    /// The pages list's rows grew and wobbled into place the first time it slid in after
    /// launch (Kevin, 2026-11-27: "all the menu entries wobble and grow and oscillate", the
    /// rows, the first time only): iOS sized them for the first time inside the slide's
    /// animation. So the app opens on the list, and once it's laid out (the next turn of the
    /// main loop, within the launch's own animation) the conversation takes its place at once.
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

    /// Back to the world's conversation, leaving the page (an empty one is discarded).
    private func openConversation() {
        showingMap = false
        library.selection = nil
        column = .detail
        closeDrawer()
    }

    /// The world's connections, leaving the page; a page opened from them goes back to them.
    private func openMap() {
        showingMap = true
        library.selection = nil
        column = .detail
        closeDrawer()
    }

    /// A new world conversation, in place of the one open (which stays in the list).
    private func startConversation() {
        worldConversation = UUID()
        openConversation()
    }

    /// Unfolded, a choice in the pages list's drawer (a page, a conversation, a new one)
    /// closes it to show what was chosen, as iOS's own drawer does in portrait (Kevin,
    /// 2026-11-24). Only the author's choices: the pages list is left where iOS and the author
    /// put it as the Duo folds, unfolds and rotates (moving it then too crashed iOS's split
    /// view, 2026-11-24).
    private func closeDrawer() {
        if sizeClass == .regular { withAnimation { columns = .detailOnly } }
    }
}

struct PageList: View {
    @Environment(Library.self) private var library
    @Environment(Companion.self) private var companion
    @Binding var selection: UUID?
    /// Unfolded, the title shares the top row with New Page; folded, the
    /// buttons move to the Duo's side column and the title heads the list.
    let titleInBar: Bool
    /// The world conversation in front, if one is (its row is marked).
    let current: UUID?
    /// A new world conversation, and one of the others, from the rows at the top.
    let newConversation: () -> Void
    let openConversation: (UUID) -> Void
    /// The world's connections.
    let openMap: () -> Void
    let newPage: () -> Void
    /// A world conversation whose deletion is being asked about.
    @State private var deletingTalk: Conversation?
    @State private var searching = false
    /// Showing Recently Deleted in place of the pages.
    @State private var showingDeleted = false
    /// A deleted page whose choices (recover, delete now) are showing.
    @State private var choosing: WriterCore.Document?
    @State private var renaming: PageType?
    @State private var deleting: PageType?
    @State private var newName = ""
    /// The world dialogs, from the title menu.
    @State private var creatingWorld = false
    @State private var renamingWorld = false
    @State private var deletingWorld = false
    @State private var worldName = ""
    @State private var worldError: String?

    var body: some View {
        @Bindable var library = library
        let query = library.searchQuery
        // Searching: Spotlight's results, in its order, each with the line that matched.
        let results: [(page: WriterCore.Document, paragraph: Int?)] = library.searchResults.compactMap { found in
            guard let page = library.pages.first(where: { $0.id == found.page }) else { return nil }
            return (page, found.paragraph.flatMap { p in page.paragraphs.firstIndex { $0.id == p } })
        }
        List(selection: $selection) {
            // Folded: the world's name, large, as the screen's title: tap it to
            // switch, make or manage worlds.
            if !titleInBar {
                Section {
                    TitleMenu(title: library.world.name, hint: "Switches, creates and manages worlds") { worldMenu }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 0))   // clear of the card's rounded corners, which clip a flush M's serifs
                        .listRowSeparator(.hidden)
                        .selectionDisabled()
                }
            }
            if query.isEmpty {
                // The drawer's top, as ChatGPT's (Kevin, 2026-11-27: "Shouldn't it be easier to
                // get to the full conversation list?"): a new conversation, the world's
                // connections, then every conversation, newest first, then the pages.
                Section {
                    Button(action: newConversation) {
                        Label("New Conversation", systemImage: "square.and.pencil")
                    }
                    .tint(.primary)
                    .selectionDisabled()
                    .calmRow()
                    Button(action: openMap) {
                        Label("Connections", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .tint(.primary)
                    .selectionDisabled()
                    .accessibilityHint("How the people, places and things of your world connect, growing as you talk.")
                    .calmRow()
                }
                if !companion.worldConversations.isEmpty {
                    Section("Conversations") {
                        ForEach(companion.worldConversations, id: \.page) { conversationRow($0) }
                    }
                }
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
                            if let heading = group.heading { Text(heading) }
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
        // From the world menu's Types: deleting a type asks first.
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?",
                            isPresented: Binding { deleting != nil } set: { if !$0 { deleting = nil } },
                            titleVisibility: .visible, presenting: deleting) { type in
            Button("Delete Type", role: .destructive) { library.deleteType(type.id) }
        } message: { type in
            Text(Self.deletingTypeMessage(pages: library.pageCount(ofType: type.id)))
        }
        .alert("Couldn’t Save the World", isPresented: Binding { worldError != nil } set: { if !$0 { worldError = nil } }) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(worldError ?? "")
        }
        .lookBackground()
        .navigationTitle(library.world.name)
        // The world's name, with a menu to switch, make, rename and delete
        // worlds. Unfolded: iOS's own small title in the bar's row, with its
        // title menu. Folded, where the bar's buttons sit in the Duo's side
        // column: the name large at the top of the list (TitleMenu), since iOS
        // gives a large title no menu (Kevin asked for it large there).
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: titleInBar ? nil : .title)
        .toolbarTitleMenu { if titleInBar { worldMenu } }
        .alert("New World", isPresented: $creatingWorld) {
            TextField("Name, such as a book or a setting", text: $worldName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = worldName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                do { try library.newWorld(named: name) } catch { worldError = "“\(name)” couldn’t be created: \(error.localizedDescription)" }
            }
        } message: {
            Text("A world has its own pages, types and fields.")
        }
        .alert("Rename World", isPresented: $renamingWorld) {
            TextField("Name", text: $worldName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let name = worldName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                do { try library.renameWorld(library.world.id, to: name) } catch { worldError = "It couldn’t be renamed: \(error.localizedDescription)" }
            }
        }
        .confirmationDialog("Delete “\(library.world.name)”?", isPresented: $deletingWorld, titleVisibility: .visible) {
            Button("Delete World", role: .destructive) { library.deleteWorld(library.world.id) }
        } message: {
            let count = library.pageCount(inWorld: library.world.id)
            Text(count == 0 ? "It has no pages. This can’t be undone."
                 : "Its \(count == 1 ? "page" : "\(count) pages") will be deleted for good, with its types and fields. This can’t be undone.")
        }
        .toolbar {
            // Kevin, 2026-11-24: search at the very bottom, New Page in its usual place at the
            // top. Search where iOS puts it (he asked for the Duo's best practice): in the
            // bottom bar, which the folded Duo's side column shows as a button.
            // New Page is pinned: as a primary action, even at high priority, iOS put it alone
            // unfolded in a "•••" menu the same size as the button (Kevin, 2026-11-24); a
            // pinned item goes there only while searching with no room.
            ToolbarItem(placement: .topBarPinnedTrailing) {
                Button("New Page", systemImage: "square.and.pencil") {
                    showingDeleted = false   // the new page shows in the list
                    newPage()
                }
                .keyboardShortcut("n")
            }
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
        }
    }

    /// A world conversation: its first words and when it was last talked in, marked while it's
    /// the one in front; swipe to delete (it asks first).
    private func conversationRow(_ talk: Conversation) -> some View {
        Button { openConversation(talk.page) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(talk.title ?? "New Conversation")
                    .font(.authored(.body))
                    .lineLimit(1)
                if let when = talk.lastActive {
                    Text(when, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .tint(.primary)
        .selectionDisabled()
        .accessibilityAddTraits(current == talk.page ? .isSelected : [])
        .listRowSeparator(.hidden)
        .listRowBackground(current == talk.page ? Color(Look.raised) : nil)
        .swipeActions(allowsFullSwipe: false) {
            Button("Delete", systemImage: "trash") { deletingTalk = talk }.tint(.red)
        }
        .confirmationDialog("Delete this conversation?",
                            isPresented: Binding { deletingTalk?.page == talk.page } set: { if !$0 { deletingTalk = nil } },
                            titleVisibility: .visible) {
            Button("Delete Conversation", role: .destructive) {
                companion.deleteWorldConversation(talk.page, in: library)
                if current == talk.page { newConversation() }   // never left on one that's gone
            }
        } message: {
            Text("What it added to your pages stays.")
        }
    }

    private func row(_ page: WriterCore.Document, snippet: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(highlighted(page.heading.isEmpty ? "New Page" : page.heading))
                    .font(.authored(.headline))
                    .lineLimit(1)
                // New or added to by the companion, not yet opened (`Library.unseen`).
                if library.unseen.contains(page.id) {
                    Circle()
                        .fill(Color(Look.accent))
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("New")
                }
            }
            if let snippet {
                // Searching: the line that matched, in place of how it begins.
                Text(highlighted(snippet)).lineLimit(1)
                    .font(.authored(.subheadline))
                    .foregroundStyle(.secondary)
            } else if !page.preview.isEmpty {
                // How it begins, in place of when it changed: what's on it, not its bookkeeping.
                Text(page.preview).font(.authored(.subheadline)).lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .calmRow()
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { library.delete(page.id) }
        }
    }

    @ViewBuilder private var worldMenu: some View {
        Picker("World", selection: Binding { library.world.id } set: { library.open(world: $0) }) {
            ForEach(library.worlds) { Text($0.name).tag($0.id) }
        }
        Button("New World…", systemImage: "plus") { worldName = ""; creatingWorld = true }
        Button("Rename World…", systemImage: "pencil") { worldName = library.world.name; renamingWorld = true }
        if library.worlds.count > 1 {
            Button("Delete World…", systemImage: "trash", role: .destructive) { deletingWorld = true }
        }
        // The world's kinds of page, to rename or delete: out of the list, where they read as
        // machinery above the pages (Kevin, 2026-11-27); a page's own type menu chooses its type.
        if !library.schema.types.isEmpty {
            Menu("Types", systemImage: "square.text.square") {
                ForEach(library.schema.types) { type in
                    Menu(type.name) {
                        Button("Rename…", systemImage: "pencil") { rename(type) }
                        Button("Delete…", systemImage: "trash", role: .destructive) { deleting = type }
                    }
                }
            }
        }
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
        let title = page.heading.isEmpty ? "New Page" : page.heading, days = page.daysLeft() ?? 0
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
            Button("Recover", systemImage: "arrow.uturn.backward") { library.recover(page.id) }.tint(.blue)
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

    private var mentionsButton: some View {
        Button("Mentions", systemImage: "at") { showMentions = true }
    }

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
                // sidebar button, Focus, and Done (the iPhone keyboard has no key to close it) in
                // iOS's blue, each its own button, never in "•••". Read and Mentions wait for
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
                ToolbarItem(placement: .primaryAction) { Button("Read", systemImage: "book", action: read) }
                // Shown when there's room; first into "•••" when there isn't.
                ToolbarItem(placement: .primaryAction) { mentionsButton }
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
                        Text(page.heading.isEmpty ? "New Page" : page.heading).font(.authored(.headline))
                        if !page.preview.isEmpty {
                            Text(page.preview).font(.authored(.subheadline)).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                .tint(.primary)
            }
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
}
