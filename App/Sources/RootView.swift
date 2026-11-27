import Combine
import CoreSpotlight
import SwiftUI
import WidgetKit   // NSUserActivityTypeLiveActivity
import WriterCore

/// The world's conversation, or the open page, with the pages list beside it. The
/// conversation is where the author starts (Kevin, 2026-11-27: "I want to write it
/// conversationally or in any messy way ... and that populates my pages"): it shows whenever
/// no page is open, and the pages are where they read their world. Folded, it's a stack
/// (list, then conversation or page); unfolded, the list is a drawer. Controls are standard
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
    /// The world's other conversations, to go back to one (the conversation's menu).
    @State private var showingConversations = false
    /// Unfolded, the drawer is closed once the app has opened: the conversation (or page) in
    /// front, the drawer a tap away (open for CI's shot of the pages list).
    @State private var columns: NavigationSplitViewVisibility = Self.opensOnList ? .all : .detailOnly
    /// `settleList` has run, or isn't wanted: CI's shots stay where they open.
    @State private var listSettled = Screenshots.isActive
    /// The pages list as it was before Focus mode put it away, to put back after.
    @State private var columnsBeforeFocus: NavigationSplitViewVisibility?
    /// Folded, the companion's sheet keeps the height it was left at, half or full,
    /// across folding, reopening and relaunching (iOS's scene state restoration).
    @SceneStorage("companionFullHeight") private var companionFullHeight = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    /// Unfolded: the pages list is a sidebar beside the page.
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The window's width, for the companion's column to open at half of it.
    @State private var windowWidth: CGFloat = 0

    private static var startsInFocus: Bool { UserDefaults.standard.bool(forKey: "startInFocus") }
    /// The app opens on the pages list, for its first layout before the conversation takes
    /// its place (`settleList`). CI's shots open where they're taken: on the list only for
    /// the list's own shot.
    private static var opensOnList: Bool { !Screenshots.isActive || Screenshots.opensList }

    /// In Focus mode everything but the writing hides (bars, status, home
    /// indicator, pages list) until a tap outside the text brings it back.
    /// VoiceOver users keep the controls: hidden ones would be unreachable.
    private var chromeHidden: Bool { focusMode && !focusControls && !voiceOver }
    /// A page is open, not the world's conversation (folded, going back to the pages list
    /// clears the selection).
    private var pageShown: Bool { library.selection != nil }
    /// The page's companion is on screen: whenever it's open over a page. Never over the
    /// pages list or the world's conversation, which is the world's companion
    /// (Kevin, 2026-11-24: a page's companion over the list is "weird"). It goes by this
    /// alone, never by where the pages list is: iOS moves both as the Duo rotates, and the
    /// two following each other mid-layout crashed iOS's split view (2026-11-24).
    private var companionShown: Bool { companion.isOpen && pageShown }
    /// The app is in front. Leaving it, iOS draws the app switcher's snapshots in other
    /// layouts too, taking the companion's column or sheet down and putting it back, and
    /// coming back it closed the companion (Kevin, 2026-11-24): only what happens in front
    /// is the author's. Asked of UIKit at the time, not from when the binding was made.
    private static var inFront: Bool { UIApplication.shared.applicationState == .active }

    var body: some View {
        // Focus mode takes the whole display: the pages list steps aside when unfolded.
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $column) {
            PageList(selection: Binding { library.selection } set: {
                library.selection = $0
                if $0 != nil { closeDrawer() }
            }, titleInBar: sizeClass == .regular, openConversation: openConversation) {
                library.newPage()
                column = .detail
                closeDrawer()
            }
            .onAppear(perform: settleList)
        } detail: {
            detail
        }
        // Unfolded, the pages list is a drawer that slides over the page, in portrait and
        // landscape alike, never squeezing it (Kevin, 2026-11-24: "the drawer would slide
        // over instead"); the companion is a column beside the page, and stays open as the
        // drawer slides in.
        .navigationSplitViewStyle(.prominentDetail)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
        // Coming back to the app (its icon, the app switcher) opens nothing: it's where
        // the author left it, even while the companion's download runs. Only a tap on the
        // download's Live Activity shows the download (Kevin, 2026-11-24), in the companion
        // of what's on screen: a page's own, or else the world's conversation. That Live
        // Activity is iOS's own (the continued-processing task), which documents no signal
        // for the tap; if iOS sends the Live Activity user activity, as for any Live
        // Activity without a link, this catches it.
        .onContinueUserActivity(NSUserActivityTypeLiveActivity) { _ in
            trialLog("LIVE ACTIVITY tap, download \(companion.download != nil)")   // TRIAL: does iOS send it?
            guard companion.download != nil, !focusMode else { return }
            if pageShown {
                companion.isOpen = true
                putPagesListAway()   // as its button does
            } else {
                openConversation()
            }
        }
        // Each world has its own conversation, in front whenever no page is open.
        .task(id: library.world.id) {
            companion.loadWorldConversations(in: library)
            worldConversation = library.lastWorldConversation ?? companion.worldConversations.first?.page ?? UUID()
        }
        .sheet(isPresented: $showingConversations) {
            NavigationStack {
                WorldConversationList(selection: Binding { worldConversation } set: { id in
                    if let id {
                        worldConversation = id   // chosen: back to it
                        showingConversations = false
                    } else {
                        worldConversation = UUID()   // the open one deleted: a new one in its place
                    }
                }, start: {
                    startConversation()
                    showingConversations = false
                }, close: {
                    showingConversations = false
                })
            }
            .presentationDetents([.medium, .large])
        }
        // The pages list is left where iOS and the author put it as the Duo folds, unfolds
        // and rotates: moving it then too crashed iOS's split view (2026-11-24).
        .onChange(of: sizeClass, initial: true) { _, size in companion.folded = size == .compact }
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
            if focus { companion.isOpen = false }   // never in Focus mode
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
            EditorView(focusMode: $focusMode, focusControls: $focusControls, chromeHidden: chromeHidden,
                       onCompanionOpened: putPagesListAway)
            .id(id)
            // The page's companion, on the page but outside its id, so changing pages never
            // rebuilds it (Kevin, 2026-11-24, "stop replacing stock components"): unfolded,
            // iOS's inspector beside the page; folded, iOS's sheet, half or full height. Each
            // shows by the size class this update draws with, so folding and unfolding swap
            // them at once and keep the companion open. (The inspector's own sheet, folded,
            // merged the companion's bar into the page's and showed no conversation; Kevin,
            // 2026-11-24, "this weird companion header".) iOS opens and closes the inspector
            // itself too (it restores it as the Duo unfolds): taken as the author's (never
            // opening it in Focus mode), except as the Duo folds, the page goes or the app
            // isn't in front, when only the column goes. (In a NavigationStack of the
            // detail's own, the page's toolbar went missing.)
            .inspector(isPresented: Binding { companionShown && sizeClass == .regular } set: { open in
                guard sizeClass == .regular, pageShown, !(open && focusMode), Self.inFront else { return }
                companion.isOpen = open
            }) {
                // Opens at half the screen's width (Kevin, 2026-11-24), wider or narrower by
                // dragging its edge within iOS's own limits ("whatever iOS provides").
                CompanionPanel(inSheet: false)
                    .inspectorColumnWidth(ideal: windowWidth / 2)
            }
            // Swiping the sheet down closes the companion, but only in front and folded (by
            // both this update's size class and the posture flag): unfolding dismisses it too.
            .sheet(isPresented: Binding { companionShown && sizeClass == .compact } set: { open in
                if !open, companion.folded, sizeClass == .compact, Self.inFront { companion.isOpen = false }
            }) {
                CompanionPanel(inSheet: true)
                    .presentationDetents([.medium, .large], selection: Binding {
                        companionFullHeight ? .large : .medium
                    } set: { companionFullHeight = $0 == .large })
                    .presentationDragIndicator(.visible)
            }
        } else if let id = worldConversation {
            CompanionPanel(inSheet: false, worldConversation: id, newConversation: startConversation,
                           conversations: { showingConversations = true })
            .task(id: id) {
                companion.open(library.worldSubject(id), in: library, aboutWorld: true)
                library.lastWorldConversation = id
            }
        }
    }

    /// Opening the companion closes the pages list's drawer, to talk about the page under it;
    /// closing the companion leaves the drawer as it is, one tap away with the sidebar button
    /// (bringing it back made the button go between the drawer and the companion; Kevin,
    /// 2026-11-24). Folded too, so unfolding shows the page and the companion side by side
    /// (unseen until then, so not animated). Only the author's taps do this (its button, the
    /// download's Live Activity), never iOS's own layout changes.
    private func putPagesListAway() {
        if sizeClass == .regular {
            withAnimation { columns = .detailOnly }
        } else {
            columns = .detailOnly
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
    /// 2026-11-24). Only the author's choices: never iOS's layout changes.
    private func closeDrawer() {
        if sizeClass == .regular { withAnimation { columns = .detailOnly } }
    }
}

struct PageList: View {
    @Environment(Library.self) private var library
    @Binding var selection: UUID?
    /// Unfolded, the title shares the top row with New Page; folded, the
    /// buttons move to the Duo's side column and the title heads the list.
    let titleInBar: Bool
    /// Back to the world's conversation (its row at the top of the list).
    let openConversation: () -> Void
    let newPage: () -> Void
    @State private var searching = false
    /// Showing only one type's pages, or Recently Deleted.
    private enum Filter: Hashable { case type(UUID), deleted }
    @State private var filter: Filter?
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
                        .selectionDisabled()
                }
            }
            if query.isEmpty {
                // The world's conversation, where the author starts, as a place in the list, as
                // Mail lists its mailboxes: the only chat button is a page's own companion
                // (Kevin, 2026-11-24: with two alike, "which assistant is which?").
                Section {
                    Button(action: openConversation) {
                        Label("Conversation", systemImage: "bubble.left.and.text.bubble.right")
                    }
                    .tint(.primary)
                    .selectionDisabled()
                    .accessibilityHint("Back to your conversation about your world.")
                }
                // Types are managed here, as Notes manages folders; a page's
                // own type menu only chooses its type.
                if !library.schema.types.isEmpty {
                    Section("Types") {
                        ForEach(library.schema.types) { typeRow($0) }
                    }
                }
                if filter == .deleted, !library.recentlyDeleted.isEmpty {
                    Section {
                        ForEach(library.recentlyDeleted) { deletedRow($0) }
                    } header: {
                        Text("Recently Deleted")
                    } footer: {
                        Text("Pages are deleted for good after 30 days.")
                    }
                } else {
                    let type = if case .type(let id)? = filter { library.schema.type(id) } else { PageType?.none }
                    Section {
                        ForEach(library.pages.filter { type == nil || $0.type == type?.id }) { row($0, snippet: nil) }
                    } header: {
                        Text(type?.name ?? "Pages")
                    }
                }
                // Out of the way at the bottom, as Notes and Photos keep it (Kevin, 2026-11-24: cluttered).
                if !library.recentlyDeleted.isEmpty {   // tapped again, back to the pages
                    Section {
                        filterRow("Recently Deleted", systemImage: "trash", count: library.recentlyDeleted.count, .deleted)
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
            if empty, filter == .deleted { filter = nil }   // its row is gone; back to all pages
        }
        .onChange(of: library.world.id) { filter = nil }   // a filter belongs to the world it was set in
        .alert("Couldn’t Save the World", isPresented: Binding { worldError != nil } set: { if !$0 { worldError = nil } }) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(worldError ?? "")
        }
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
                    // Showing one type: the new page is one of them (as a new
                    // note goes in the open folder), so it's in the list.
                    let type = if case .type(let id)? = filter { library.schema.type(id) } else { PageType?.none }
                    if type == nil { filter = nil }
                    newPage()
                    if let type { library.update { $0.type = type.id } }
                }
                .keyboardShortcut("n")
            }
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
        }
    }

    private func row(_ page: WriterCore.Document, snippet: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(highlighted(page.heading.isEmpty ? "New Page" : page.heading))
                .font(.authored(.headline))
                .lineLimit(1)
            if let snippet {
                // Searching: the line that matched, in place of date and preview.
                Text(highlighted(snippet)).lineLimit(1)
                    .font(.authored(.subheadline))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    Text(page.modified, format: .relative(presentation: .named))
                    if !page.preview.isEmpty { Text(page.preview).font(.authored(.subheadline)).lineLimit(1) }
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

    @ViewBuilder private var worldMenu: some View {
        Picker("World", selection: Binding { library.world.id } set: { library.open(world: $0) }) {
            ForEach(library.worlds) { Text($0.name).tag($0.id) }
        }
        Button("New World…", systemImage: "plus") { worldName = ""; creatingWorld = true }
        Button("Rename World…", systemImage: "pencil") { worldName = library.world.name; renamingWorld = true }
        if library.worlds.count > 1 {
            Button("Delete World…", systemImage: "trash", role: .destructive) { deletingWorld = true }
        }
    }

    /// A row that shows only some pages: tap to show them (again to show
    /// all). Not a page, so never selected as one.
    private func filterRow(_ title: String, systemImage: String, count: Int, _ rowFilter: Filter) -> some View {
        let shown = filter == rowFilter
        return Button {
            withAnimation { filter = shown ? nil : rowFilter }
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text(count, format: .number).foregroundStyle(.secondary)
                if shown { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
        .tint(.primary)
        .selectionDisabled()
        .accessibilityAddTraits(shown ? .isSelected : [])
        .accessibilityHint(shown ? "Shows all pages" : "Shows only these pages")
    }

    /// A type: tap to show only its pages; hold or swipe to rename or delete it.
    private func typeRow(_ type: PageType) -> some View {
        filterRow(type.name, systemImage: "square.text.square", count: library.pageCount(ofType: type.id), .type(type.id))
        .contextMenu {
            Button("Rename", systemImage: "pencil") { rename(type) }
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = type }
        }
        // Delete only asks: a destructive role would animate the row away
        // before the answer. No full swipe, so it can't skip the question.
        .swipeActions(allowsFullSwipe: false) {
            Button("Delete", systemImage: "trash") { deleting = type }.tint(.red)
            Button("Rename", systemImage: "pencil") { rename(type) }
        }
        // On the row, so its popover points at the type it's about.
        .confirmationDialog("Delete “\(type.name)”?",
                            isPresented: Binding { deleting?.id == type.id } set: { if !$0 { deleting = nil } },
                            titleVisibility: .visible) {
            Button("Delete Type", role: .destructive) {
                if filter == .type(type.id) { filter = nil }
                library.deleteType(type.id)
            }
        } message: {
            Text(Self.deletingTypeMessage(pages: library.pageCount(ofType: type.id)))
        }
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
    @Environment(Companion.self) private var companion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showMentions = false
    @State private var typeName = ""
    @State private var pageName = ""
    @Binding var focusMode: Bool
    @Binding var focusControls: Bool
    let chromeHidden: Bool
    /// The author opened the companion with its button.
    let onCompanionOpened: () -> Void

    private var newType: Binding<Bool> {
        Binding { library.fieldsRequest == .newType } set: { if !$0 { library.fieldsRequest = nil } }
    }

    private var folded: Bool { sizeClass == .compact }
    /// The keyboard is up (in Focus mode, only ever its writing's).
    @State private var typing = false
    /// The page has the keyboard (its writing, title or a field), not anything else (search
    /// in the pages list, an alert, the companion's message field): the toolbar is for
    /// editing then.
    @State private var editing = false
    /// The page's writing has the keyboard (not its title, a field or the companion).
    @State private var writing = false
    /// The bottom bar (the companion's button) as asked of iOS; see `askForBottomBarAgain`.
    @State private var bottomBar = Visibility.visible

    /// The companion, beside the page (unfolded) or a sheet (folded). ⌥⌘I is the system's
    /// shortcut for an inspector.
    private var companionButton: some View {
        Button(companion.isOpen ? "Hide Companion" : "Companion", systemImage: "bubble.left.and.text.bubble.right") {
            companion.isOpen.toggle()
            if companion.isOpen { onCompanionOpened() }
        }
        .keyboardShortcut("i", modifiers: [.command, .option])
    }

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

    /// Folding or unfolding, iOS builds the page's bar afresh, and unfolded it came back
    /// without the bottom bar (Kevin's screenshot, 2026-11-24, companion button missing): a
    /// request iOS has already had isn't sent again, so it's withdrawn and made once more
    /// after the change has settled.
    private func askForBottomBarAgain() {
        bottomBar = .automatic
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            bottomBar = .visible
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
        // Unfolded, iOS hid the page's bottom bar (the companion's button) while the companion's
        // column was closed, keeping the top's (Kevin's screenshots, 2026-11-24): asked for.
        .toolbar(focusMode ? .automatic : bottomBar, for: .bottomBar)
        .onChange(of: sizeClass) { askForBottomBarAgain() }
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
                // iOS's blue, each its own button, never in "•••". The companion and Mentions
                // wait for the keyboard to go down: folded, the side column above the keyboard
                // holds only three buttons (with a menu as well, iOS put Done in a "•••" of its
                // own; "just looks terrible"). (Swapping the bar while any keyboard was up,
                // search's or an alert's, hid the sidebar button and the companion's.)
                // Focus is for the writing: offered only while it has the keyboard, not the
                // title or a field (Kevin). Where iOS puts the bar's buttons, with Done (pinned to
                // the top row unfolded, it sat over the companion's column; Kevin, 2026-11-24).
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
                // The companion's button at the bottom as on every screen (Kevin, 2026-11-24):
                // folded, at the foot of the Duo's side column; unfolded, at the bottom's
                // trailing end, where the companion opens (alone it sat in the middle:
                // "dumb as fuck").
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) { companionButton }
                // Shown when there's room; first into "•••" when there isn't.
                ToolbarItem(placement: .primaryAction) { mentionsButton }
                    .visibilityPriority(.low)
            }
        }
        .task {
            companion.open(library.document, in: library)
        }
    }
}

/// The world's conversations with the companion, about the whole world rather than
/// one page, from the conversation's menu: a stock list in a sheet, newest first, each
/// titled by the author's first words; choosing one goes back to it.
struct WorldConversationList: View {
    @Environment(Library.self) private var library
    @Environment(Companion.self) private var companion
    @Binding var selection: UUID?
    let start: () -> Void
    let close: () -> Void
    @State private var deleting: Conversation?

    var body: some View {
        List(selection: $selection) {
            ForEach(companion.worldConversations, id: \.page) { talk in
                VStack(alignment: .leading, spacing: 3) {
                    Text(talk.title ?? "New Conversation").font(.authored(.headline)).lineLimit(1)
                    if let when = talk.lastActive {
                        Text(when, format: .relative(presentation: .named)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                // Delete only asks, as for a type: no destructive role or full swipe, and
                // the question comes from the row.
                .swipeActions(allowsFullSwipe: false) {
                    Button("Delete", systemImage: "trash") { deleting = talk }.tint(.red)
                }
                .confirmationDialog("Delete this conversation?",
                                    isPresented: Binding { deleting?.page == talk.page } set: { if !$0 { deleting = nil } },
                                    titleVisibility: .visible) {
                    Button("Delete Conversation", role: .destructive) {
                        if selection == talk.page { selection = nil }
                        companion.deleteWorldConversation(talk.page, in: library)
                    }
                } message: {
                    Text("What it added to your pages stays.")
                }
            }
        }
        .overlay {
            if companion.worldConversations.isEmpty {
                ContentUnavailableView {
                    Label("No Conversations", systemImage: "bubble.left.and.text.bubble.right")
                } description: {
                    Text("Talk with the companion about your whole world.")
                } actions: {
                    Button("New Conversation", action: start).buttonStyle(.bordered)
                }
            }
        }
        .navigationTitle("Conversations")
        .navigationBarTitleDisplayMode(.inline)
        // A stock sheet: its bar across the top, not in the folded Duo's side column.
        .toolbarVerticalBehavior(.disabled)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark", action: close)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("New Conversation", systemImage: "square.and.pencil", action: start)
            }
        }
        .task(id: library.world.id) { companion.loadWorldConversations(in: library) }
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
            .navigationTitle("Mentions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            // A stock sheet, as the companion's: its bar across the top, not in the folded Duo's side column.
            .toolbarVerticalBehavior(.disabled)
        }
        .presentationDetents([.medium, .large])
    }
}
