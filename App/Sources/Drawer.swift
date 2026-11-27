import SwiftUI
import WriterCore

/// The drawer, as ChatGPT's (Kevin, 2026-11-27: "Shouldn't it be easier to get to the full
/// conversation list?"; "do you really want to throw everything together in the same main list?"):
/// the world's name (its menu switches, makes and manages worlds), New Conversation, the world's
/// Connections and Pages, then only the conversations, newest first, the one in front marked.
/// Folded, the drawer button (where Back would be) goes back to it; unfolded, it slides over.
struct Drawer: View {
    @Environment(Library.self) private var library
    @Environment(Companion.self) private var companion
    /// Unfolded, the world's name is iOS's title with its menu; folded, where the bar's
    /// buttons move to the Duo's side column, it heads the list, large.
    let titleInBar: Bool
    /// What's in front (nil while a page is open), its row marked: Connections, Pages, or the
    /// conversation `currentConversation`.
    let current: RootView.Screen?
    let currentConversation: UUID?
    let newConversation: () -> Void
    let openConversation: (UUID) -> Void
    let openConnections: () -> Void
    let openPages: () -> Void
    /// A conversation whose deletion is being asked about.
    @State private var deleting: Conversation?
    /// The world dialogs, from the title menu.
    @State private var creatingWorld = false
    @State private var renamingWorld = false
    @State private var deletingWorld = false
    @State private var worldName = ""
    @State private var worldError: String?

    var body: some View {
        List {
            if !titleInBar {
                Section {
                    TitleMenu(title: library.world.name, hint: "Switches, creates and manages worlds") { worldMenu }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 14, trailing: 20))   // the rows' own left edge, with room around it
                        .listRowSeparator(.hidden)
                }
            }
            Section {
                place("New Conversation", systemImage: "square.and.pencil", marked: false, action: newConversation)
                place("Connections", systemImage: "point.3.connected.trianglepath.dotted", marked: current == .connections,
                      action: openConnections)
                    .accessibilityHint("How the people, places and things of your world connect, growing as you talk.")
                place("Pages", systemImage: "books.vertical", marked: current == .pages, action: openPages)
                    .accessibilityHint("Your world's pages, by kind.")
            }
            if !companion.worldConversations.isEmpty {
                Section("Conversations") {
                    ForEach(companion.worldConversations, id: \.page) { conversationRow($0) }
                }
            }
        }
        .listStyle(.plain)
        .lookBackground()
        .navigationTitle(library.world.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: titleInBar ? nil : .title)
        .toolbarTitleMenu { if titleInBar { worldMenu } }
        .alert("New World", isPresented: $creatingWorld) {
            TextField("Name, such as a book or a setting", text: $worldName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = worldName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                do { try library.newWorld(named: name) } catch { worldError = "\u{201C}\(name)\u{201D} couldn\u{2019}t be created: \(error.localizedDescription)" }
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
                do { try library.renameWorld(library.world.id, to: name) } catch { worldError = "It couldn\u{2019}t be renamed: \(error.localizedDescription)" }
            }
        }
        .confirmationDialog("Delete \u{201C}\(library.world.name)\u{201D}?", isPresented: $deletingWorld, titleVisibility: .visible) {
            Button("Delete World", role: .destructive) { library.deleteWorld(library.world.id) }
        } message: {
            let count = library.pageCount(inWorld: library.world.id)
            Text(count == 0 ? "It has no pages. This can\u{2019}t be undone."
                 : "Its \(count == 1 ? "page" : "\(count) pages") will be deleted for good, with its types and fields. This can\u{2019}t be undone.")
        }
        .alert("Couldn\u{2019}t Save the World", isPresented: Binding { worldError != nil } set: { if !$0 { worldError = nil } }) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(worldError ?? "")
        }
    }

    /// A row that opens something, the whole width a button, with no line under it, on a
    /// raised background while what it opens is in front.
    private func row<Content: View>(marked: Bool, action: @escaping () -> Void,
                                    @ViewBuilder label: () -> Content) -> some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .tint(.primary)
        .accessibilityAddTraits(marked ? .isSelected : [])
        .listRowSeparator(.hidden)
        .listRowBackground(marked ? Color(Look.raised) : nil)
    }

    /// A place in the world to go to, marked while it's in front.
    private func place(_ title: String, systemImage: String, marked: Bool, action: @escaping () -> Void) -> some View {
        row(marked: marked, action: action) { Label(title, systemImage: systemImage) }
    }

    /// A conversation: its first words and when it was last talked in, marked while it's the
    /// one in front; swipe to delete (it asks first).
    private func conversationRow(_ talk: Conversation) -> some View {
        let marked = currentConversation == talk.page
        return row(marked: marked, action: { openConversation(talk.page) }) {
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
        }
        .swipeActions(allowsFullSwipe: false) {
            Button("Delete", systemImage: "trash") { deleting = talk }.tint(.red)
        }
        .confirmationDialog("Delete this conversation?",
                            isPresented: Binding { deleting?.page == talk.page } set: { if !$0 { deleting = nil } },
                            titleVisibility: .visible) {
            Button("Delete Conversation", role: .destructive) {
                companion.deleteWorldConversation(talk.page, in: library)
                if marked { newConversation() }   // never left on one that's gone
            }
        } message: {
            Text("What it added to your pages stays.")
        }
    }

    @ViewBuilder private var worldMenu: some View {
        Picker("World", selection: Binding { library.world.id } set: { library.open(world: $0) }) {
            ForEach(library.worlds) { Text($0.name).tag($0.id) }
        }
        Button("New World\u{2026}", systemImage: "plus") { worldName = ""; creatingWorld = true }
        Button("Rename World\u{2026}", systemImage: "pencil") { worldName = library.world.name; renamingWorld = true }
        if library.worlds.count > 1 {
            Button("Delete World\u{2026}", systemImage: "trash", role: .destructive) { deletingWorld = true }
        }
    }
}
