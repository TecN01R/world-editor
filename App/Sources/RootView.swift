import Combine
import CoreSpotlight
import SwiftUI
import WriterCore

/// Pages list beside the open page. Folded, it's a stack (list, then page);
/// unfolded, the list sits alongside. Controls are standard toolbar items, so
/// on iPhone Duo the system lays them out in the side column.
struct RootView: View {
    @Environment(Library.self) private var library
    @Environment(Companion.self) private var companion
    /// The window's width: unfolded, the companion takes half of it.
    @State private var width: CGFloat = 0
    @State private var column: NavigationSplitViewColumn = Screenshots.opensList ? .sidebar : .detail
    @State private var focusMode = Self.startsInFocus
    @State private var focusControls = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var columns: NavigationSplitViewVisibility = Self.startsInFocus ? .detailOnly : .all
    /// Folded, the companion's sheet keeps the height it was left at, half or full,
    /// across folding, reopening and relaunching (iOS's scene state restoration).
    @SceneStorage("companionFullHeight") private var companionFullHeight = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    /// Unfolded: the pages list is a sidebar beside the page.
    @Environment(\.horizontalSizeClass) private var sizeClass

    private static var startsInFocus: Bool { UserDefaults.standard.bool(forKey: "startInFocus") }

    /// In Focus mode everything but the writing hides (bars, status, home
    /// indicator, pages list) until a tap outside the text brings it back.
    /// VoiceOver users keep the controls: hidden ones would be unreachable.
    private var chromeHidden: Bool { focusMode && !focusControls && !voiceOver }
    /// The companion is on screen: folded, whenever it's open; unfolded, only
    /// while the pages list is put away. Never over the world's own conversations,
    /// which are the companion already.
    private var companionShown: Bool {
        companion.isOpen && (sizeClass == .compact || columns == .detailOnly) && library.selection != library.world.id
    }

    var body: some View {
        @Bindable var library = library
        // Focus mode takes the whole display: the pages list steps aside when unfolded.
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $column) {
            PageList(selection: $library.selection, titleInBar: sizeClass == .regular, openCompanion: {
                library.selection = library.world.id
                column = .detail
            }) {
                library.newPage()
                column = .detail
            }
        } detail: {
            if library.selection == library.world.id {
                WorldCompanionView()   // the world's own conversation, from the top of the list
            } else if let id = library.selection {
                // Unfolded, tapping the companion's button sets the page beside it:
                // opening puts the pages list away, closing brings it back. Only the
                // author's taps do this; unfolding with it open is handled below.
                EditorView(focusMode: $focusMode, focusControls: $focusControls, chromeHidden: chromeHidden,
                           companionShown: companionShown) { open in
                    if sizeClass == .regular { withAnimation { columns = open ? .detailOnly : .all } }
                }
                .id(id)
            } else {
                ContentUnavailableView("No Page Open", systemImage: "doc.text",
                                       description: Text("Choose a page or start a new one."))
            }
        }
        // The companion, on the split view itself (folding and unfolding rebuild
        // the page inside it): unfolded, the stock inspector beside the page at half
        // the display; folded, a stock sheet, half or full height. Each shows only
        // in its own posture, decided here, not by the inspector (whose own sheet
        // could outlive an unfold), and from the size class this very update draws
        // with (the posture flag follows a beat later: in between, a still-presented
        // inspector turned itself into a sheet of its own, without the handle or
        // heights). Switching posture swaps them and keeps the companion open; only
        // its button, or swiping the folded sheet down, closes it.
        // The column has no gesture of its own to close it, and iOS reports it closing
        // and reopening as the Duo folds and unfolds (logged 2026-11-23), so what iOS
        // reports here is ignored.
        // Unfolded, the pages list and the companion are never out together: with
        // both, the page between them was squeezed to a sliver and the companion
        // looked like a sheet over it (Kevin, 2026-11-23). Showing the list hides
        // the companion's column; this is worked out, never set from code while
        // iOS folds and unfolds (closing it in the middle of that crashed UIKit).
        .inspector(isPresented: Binding { companionShown && sizeClass == .regular } set: { open in
            trialLog("INSPECTOR set \(open) folded=\(companion.folded)")   // TRIAL: fold/unfold diagnosis
        }) {
            CompanionPanel(inSheet: false)
                .inspectorColumnWidth(min: 320, ideal: max(320, width / 2), max: max(320, width / 2))
        }
        // Swiping the sheet down closes the companion, but only while folded (by both
        // this update's size class and the posture flag): unfolding dismisses it too.
        .sheet(isPresented: Binding { companionShown && sizeClass == .compact } set: { open in
            trialLog("SHEET set \(open) folded=\(companion.folded) size=\(String(describing: sizeClass))")   // TRIAL
            if !open, companion.folded, sizeClass == .compact { companion.isOpen = false }
        }) {
            CompanionPanel(inSheet: true)
                .presentationDetents([.medium, .large], selection: Binding {
                    companionFullHeight ? .large : .medium
                } set: { companionFullHeight = $0 == .large })
                .presentationDragIndicator(.visible)
        }
        // Back in the app while the companion's download runs (from its Live
        // Activity, say): show the download, as the companion it belongs to.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, companion.download != nil, !companion.isOpen, !focusMode { companion.isOpen = true }
        }
        .onChange(of: sizeClass, initial: true) { _, size in
            companion.folded = size == .compact
            // Unfolding with the companion open: the page and the companion side by
            // side, the pages list put away (as opening it unfolded does).
            if size == .regular, companion.isOpen, !focusMode { columns = .detailOnly }
        }
        // Applied at the root: status bar visibility is decided by the top controller.
        .statusBarHidden(chromeHidden)
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: focusMode) { _, focus in
            // Entering, the controls show and then fade on their usual timer
            // (or as soon as you type), so Exit Focus is in sight at first (Kevin).
            focusControls = focus
            if focus { companion.isOpen = false }   // never in Focus mode
            withAnimation { columns = focus ? .detailOnly : .all }   // unfolded: list beside the page
        }
    }
}

struct PageList: View {
    @Environment(Library.self) private var library
    @Binding var selection: UUID?
    /// Unfolded, the sidebar's buttons share a row with the title; folded,
    /// they move to the Duo's side column and the title heads the list.
    let titleInBar: Bool
    /// The world's own conversation with the companion (its button beside New Page).
    let openCompanion: () -> Void
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
                        if let type { Text(type.name).fontDesign(.serif) } else { Text("Pages") }
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
            // The companion for the whole world, not one page (Kevin, 2026-11-24): opens like
            // a page, full screen folded and beside the list unfolded.
            ToolbarItem(placement: .primaryAction) {
                Button("Companion", systemImage: "bubble.left.and.text.bubble.right", action: openCompanion)
                    .accessibilityHint("Talk with the companion about your whole world.")
            }
            ToolbarItem(placement: .primaryAction) {
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
                Label {
                    // A type's name is the user's; "Recently Deleted" is the app's.
                    if case .type = rowFilter { Text(title).fontDesign(.serif) } else { Text(title) }
                } icon: {
                    Image(systemName: systemImage)
                }
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
    /// The companion is on screen (unfolded, the pages list hides it).
    let companionShown: Bool
    /// The author opened (true) or closed the companion with its button.
    let onCompanionToggled: (Bool) -> Void

    private var newType: Binding<Bool> {
        Binding { library.fieldsRequest == .newType } set: { if !$0 { library.fieldsRequest = nil } }
    }

    private var folded: Bool { sizeClass == .compact }
    /// The keyboard is up: the toolbar shows Done (and Focus, while writing), and nothing else.
    @State private var typing = false
    /// The page's writing has the keyboard (not its title, a field or the companion).
    @State private var writing = false

    /// Closes the keyboard (the iPhone keyboard has no key for it) and, in
    /// Focus, leaves it: Focus is for editing, so there's nothing to stay for.
    private var done: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", systemImage: "checkmark") {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                // Done now, not when the keyboard's notice arrives: the page coming
                // back from Focus would otherwise take the keyboard straight back.
                typing = false
                if focusMode { withAnimation(.smooth(duration: 0.3)) { focusMode = false } }
            }
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
                PageEditor(keepsKeyboard: typing, onWriting: { writing = $0 }) {   // stops at the keyboard, as iOS lays pages out
                    withAnimation(.smooth(duration: 0.3)) { focusMode = true }
                }
                    .transition(.opacity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // Focus is a mode you step into, so revealing its controls shows only
        // a close button, as full-screen modes do on iOS; no back arrow or
        // sidebar button. The bar draws over the writing, which ignores the
        // safe area and so never reflows.
        .toolbar(chromeHidden ? .hidden : .automatic, for: .navigationBar)
        .navigationBarBackButtonHidden(focusMode || typing)
        .toolbar(removing: focusMode || typing ? .sidebarToggle : nil)
        // While the keyboard is up, Done shows, as in Notes. Focus is for
        // writing, so the keyboard going down (Done, or swiped away) leaves it (Kevin).
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in typing = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            typing = false
            if focusMode { withAnimation(.smooth(duration: 0.3)) { focusMode = false } }
        }
        .animation(.easeInOut(duration: 0.25), value: chromeHidden)
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
                if typing { done }
            } else {
                // Two sets, swapped by the keyboard (Kevin, 2026-11-23). Typing: Done
                // (the iPhone keyboard has no key to close it) and Focus, a writing
                // tool, in its own glass. Not typing: Back, the sidebar button, the
                // companion and Mentions.
                if typing {
                    done
                    // Focus is for the writing: offered only while it has the keyboard,
                    // not the title, a field or the companion (Kevin). Unfolded, kept
                    // in the top row at its right end; folded, in the side column.
                    if writing {
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right") {
                                withAnimation(.smooth(duration: 0.3)) { focusMode = true }
                            }
                        }
                        .axisBehavior(folded ? .automatic : .horizontalOnly)
                    }
                } else {
                    // The companion, beside the page (unfolded) or a sheet (folded); on
                    // the Duo the side column. ⌥⌘I is the system's shortcut for an inspector.
                    ToolbarItem(placement: .primaryAction) {
                        Button(companionShown ? "Hide Companion" : "Companion", systemImage: "bubble.left.and.text.bubble.right") {
                            companion.isOpen = !companionShown
                            onCompanionToggled(companion.isOpen)
                        }
                        .keyboardShortcut("i", modifiers: [.command, .option])
                    }
                    // Shown when there's room; first into "•••" when there isn't.
                    ToolbarItem(placement: .primaryAction) {
                        Button("Mentions", systemImage: "at") { showMentions = true }
                    }
                    .visibilityPriority(.low)
                }
            }
        }
        .task {
            companion.open(library.document, in: library)
        }
    }
}

/// The world's conversations with the companion, about the whole world rather than
/// one page (its button beside New Page; Kevin, 2026-11-24): a stock list, newest
/// first, each titled by the author's first words, with New Conversation. It goes
/// back into the one the author was in; with none yet, straight into a new one.
/// Every page is background, none is open; what's said is filed into the pages it
/// names, and page conversations remember it, as they remember each other.
struct WorldCompanionView: View {
    @Environment(Library.self) private var library
    @Environment(Companion.self) private var companion
    @State private var path: [UUID] = []
    @State private var deleting: Conversation?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(companion.worldConversations, id: \.page) { talk in
                    NavigationLink(value: talk.page) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(talk.title ?? "New Conversation").font(.authored(.headline)).lineLimit(1)
                            if let when = talk.lastActive {
                                Text(when, format: .relative(presentation: .named)).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = talk }
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Conversation", systemImage: "square.and.pencil", action: start)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                CompanionPanel(inSheet: false, worldConversation: id, newConversation: start)
                    .task(id: id) {
                        companion.open(library.worldSubject(id), in: library, aboutWorld: true)
                        library.lastWorldConversation = id
                    }
            }
            .confirmationDialog("Delete this conversation?", isPresented: Binding { deleting != nil } set: { if !$0 { deleting = nil } },
                                titleVisibility: .visible, presenting: deleting) { talk in
                Button("Delete Conversation", role: .destructive) { companion.deleteWorldConversation(talk.page, in: library) }
            } message: { _ in
                Text("What it added to your pages stays.")
            }
        }
        .task(id: library.world.id) {
            companion.loadWorldConversations(in: library)
            if let last = library.lastWorldConversation, companion.worldConversations.contains(where: { $0.page == last }) {
                path = [last]   // back where they were
            } else if companion.worldConversations.isEmpty {
                start()         // nothing to list: begin
            }
        }
        // Back at the list: next time, the list.
        .onChange(of: path) { _, now in
            guard now.isEmpty else { return }
            library.lastWorldConversation = nil
            companion.loadWorldConversations(in: library)   // newest first again
        }
    }

    /// A new conversation, in place of the one open (which stays in the list).
    private func start() { path = [UUID()] }
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
