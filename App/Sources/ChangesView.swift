import SwiftUI
import WriterCore

/// Everything the companion filed into the pages from this conversation (Changes,
/// beside the menu), as a history of the world rather than of the messages (each
/// reply already shows what its message did): a stock grouped list, a section per
/// page and a row per thing changed on it (new page, name, type, each field)
/// showing its latest change, with Undo for it. Undo goes newest first, so a change
/// something filed since built on says "Changed since", and its Undo… takes that back
/// too, after saying what. A field changed more than once opens its timeline (Kevin,
/// 2026-11-24).
struct ChangesView: View {
    @Environment(Library.self) private var library
    @Environment(Companion.self) private var companion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        let pages = history
        NavigationStack {
            List {
                ForEach(pages, id: \.page) { page in
                    Section {
                        ForEach(page.rows, id: \.key) { row($0) }
                    } header: {
                        library.pageName(page.page).font(.subheadline).textCase(nil)
                    }
                }
            }
            .overlay {
                if pages.isEmpty {   // all undone while it's open
                    ContentUnavailableView("No Changes", systemImage: "clock.arrow.circlepath",
                                           description: Text("What the companion adds to your pages from this conversation shows here."))
                }
            }
            .navigationTitle("Changes")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: FieldKey.self) { FieldTimeline(key: $0) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }

    /// One thing changed on a page (made it, renamed it, gave it text, typed it, or one
    /// field), with every change to it from this conversation, oldest first.
    private struct Row {
        enum Key: Hashable { case created, renamed, described, typed, field(UUID) }
        typealias Filing = (action: FilingRecord.Entry, turn: UUID, date: Date)
        let key: Key
        /// Where its first change comes among the conversation's filings.
        let first: Int
        var changes: [Filing] = []
        var latest: Filing { changes[changes.count - 1] }
    }

    /// The conversation's filings by page and thing changed. Pages, and the fields on
    /// each, come newest first by when this conversation first changed them, so no two
    /// tie, and Undo, which takes back a row's latest change (never its first while it
    /// has others), doesn't move a row it leaves or that row's section. On each page,
    /// the page itself (made, renamed, given text, typed) comes before its fields.
    private var history: [(page: UUID, rows: [Row])] {
        var rows: [UUID: [Row.Key: Row]] = [:]
        var pages: [UUID] = []   // in the order first changed
        var order = 0
        for turn in companion.conversation.turns {
            for action in turn.filed?.actions ?? [] {
                guard let page = action.page else { continue }   // a new type or field
                let key: Row.Key = switch action {
                case .created: .created
                case .renamed: .renamed
                case .described: .described
                case .value(_, let field, _), .replaced(_, let field, _, _): .field(field)
                default: .typed   // the only other with a page
                }
                if rows[page] == nil { pages.append(page) }
                rows[page, default: [:]][key, default: Row(key: key, first: order)].changes
                    .append((action: action, turn: turn.id, date: turn.answered ?? turn.asked))
                order += 1
            }
        }
        func rank(_ key: Row.Key) -> Int {
            switch key { case .created: 0; case .renamed: 1; case .described: 2; case .typed: 3; case .field: 4 }
        }
        return pages.reversed().map { page in
            (page: page, rows: rows[page, default: [:]].values.sorted {
                rank($0.key) != rank($1.key) ? rank($0.key) < rank($1.key) : $0.first > $1.first
            })
        }
    }

    @ViewBuilder private func row(_ row: Row) -> some View {
        let latest = row.latest
        let change = Change(latest.action, in: library)
        let later = companion.conversation.changedLater(latest.action, in: latest.turn, elsewhere: companion.others)
        // At the largest text sizes Undo goes under the words rather than squeezing them.
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())
        let content = layout {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    change.detail.font(.body)
                    Ago(date: latest.date, changes: row.changes.count).font(.subheadline).foregroundStyle(.secondary)
                    if later { Text("Changed since").font(.caption).foregroundStyle(.secondary) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint(later ? Text("Something filed since changed this. Undo that first.") : Text(""))
            } icon: {
                Image(systemName: change.symbol)
            }
            if !textSize.isAccessibilitySize { Spacer(minLength: 8) }
            if later {
                // Undo with what was built on it since, after saying what (Kevin, 2026-11-24).
                UndoThroughButton(title: "Undo…", action: latest.action, turn: latest.turn, label: change.spoken)
            } else {
                UndoButton(action: latest.action, turn: latest.turn, label: change.spoken)
            }
        }
        if let key = change.field, row.changes.count > 1 {
            NavigationLink(value: key) { content }
                .accessibilityHint("Shows the values the companion gave this field.")
        } else {
            content
        }
    }
}

/// A field changed more than once: every value the companion gave it from this
/// conversation, newest first, each with the message it came from and when. While
/// the field still holds the newest, its Undo steps back to the one before, and Undo
/// to Here on an older one goes back to it.
struct FieldTimeline: View {
    let key: FieldKey
    @Environment(Library.self) private var library
    @Environment(Companion.self) private var companion
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        let history = Array(companion.conversation.history(of: key.field, on: key.page).reversed())
        let now = library.pages.first { $0.id == key.page }?.values[key.field]
        List {
            if let newest = history.first {
                Section {
                    // Changed since outside this conversation (by hand, or from another page's).
                    if now != newest.value {
                        VStack(alignment: .leading, spacing: 4) {
                            if let now { Text(library.filedValue(now)).font(.authored(.body)) } else { Text("Empty") }
                            Text("Current, changed outside this conversation").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    ForEach(Array(history.enumerated()), id: \.element) { i, change in
                        let current = i == 0 && now == change.value
                        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading))
                                                                  : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                        layout {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(library.filedValue(change.value)).font(.authored(.body))
                                if current { Text("Current").font(.subheadline).foregroundStyle(.secondary) }
                                Text("“\(change.message)”").font(.authored(.footnote)).foregroundStyle(.secondary).lineLimit(3)
                                Ago(date: change.date).font(.caption).foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            if !textSize.isAccessibilitySize { Spacer(minLength: 8) }
                            // Only while the newest is what the field holds: Undo would otherwise change nothing.
                            if now == newest.value {
                                let label = Text(library.filedValue(change.value))
                                if i == 0 {
                                    UndoButton(action: change.action, turn: change.turn, label: label)
                                } else {
                                    // Back to this value: every later change to the field, and what was built on them.
                                    UndoThroughButton(title: "Undo to Here", action: history[i - 1].action,
                                                      turn: history[i - 1].turn, label: label)
                                }
                            }
                        }
                    }
                    // What it held before the companion's first change here.
                    if case .replaced(_, _, let was, _) = history.last?.action {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(library.filedValue(was)).font(.authored(.body))
                            Text("Before").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    library.pageName(key.page).font(.subheadline).textCase(nil)
                } footer: {
                    Text("Newest first. Undo the newest to go back to the one before.")
                }
            }
        }
        .navigationTitle(library.schema.fields.first { $0.id == key.field }?.name ?? "Field")
        .overlay {
            if history.isEmpty {   // all undone while it's open
                ContentUnavailableView("No Changes", systemImage: "clock.arrow.circlepath")
            }
        }
    }
}

/// A page's field, for a field's timeline.
struct FieldKey: Hashable {
    var page: UUID
    var field: UUID
}

/// "5 minutes ago", or "3 changes · 5 minutes ago" for something changed more than
/// once, kept up to date while it's on screen. One Text, so it wraps as one sentence.
private struct Ago: View {
    let date: Date
    var changes = 1

    var body: some View {
        TimelineView(.everyMinute) { _ in
            let ago = date.formatted(.relative(presentation: .named, unitsStyle: .wide))
            Text(changes > 1 ? "\(changes) changes · \(ago)" : ago)
        }
    }
}

extension Library {
    /// A filed page's name as Changes shows it: its title in New York at the size
    /// around it; "New Page" while it has none (as the pages list says) and
    /// "Deleted page" are the app's words, in San Francisco.
    fileprivate func pageName(_ id: UUID) -> Text {
        switch (pages.first { $0.id == id } ?? recentlyDeleted.first { $0.id == id })?.heading {
        case nil: Text(Self.deletedPage)
        case ""?: Text("New Page")
        case let heading?: Text(heading).fontDesign(.serif)
        }
    }
}

/// Undo with everything filed since that built on it, newest first, after a stock
/// confirmation that lists it (Kevin, 2026-11-24: "undo to this point and all layered
/// changes would be undone"). Built on from another conversation: says so instead.
private struct UndoThroughButton: View {
    let title: LocalizedStringKey
    let action: FilingRecord.Entry
    let turn: UUID
    let label: Text
    @Environment(Library.self) private var library
    @Environment(Companion.self) private var companion
    @State private var chain: [Conversation.Filed]?
    @State private var blocked = false

    var body: some View {
        Button(title) {
            if let found = companion.undoChain(action, from: turn) { chain = found } else { blocked = true }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(Text("Undo to here: \(label)"))
        .confirmationDialog(chain.map { $0.count == 1 ? "Undo this change?" : "Undo \($0.count) changes?" } ?? "",
                            isPresented: Binding { chain != nil } set: { if !$0 { chain = nil } },
                            titleVisibility: .visible, presenting: chain) { chain in
            Button(chain.count == 1 ? "Undo" : "Undo \(chain.count) Changes", role: .destructive) {
                companion.undoThrough(action, from: turn, in: library)
            }
        } message: { chain in
            Text(chain.map { summary($0.action) }.joined(separator: "\n"))
        }
        .alert("Changed in Another Conversation", isPresented: $blocked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Something filed while talking about another page built on this. Undo it there first.")
        }
    }

    /// "The Harbour · Vessel: bireme (was trireme)", "New page: The Isles (Place)": one line each.
    private func summary(_ action: FilingRecord.Entry) -> String {
        guard let line = library.describe(FilingRecord(entries: [action])).first else { return "" }
        if line.isNew { return "New page: \(line.page)" + (line.type.map { " (\($0))" } ?? "") }
        if case .renamed(_, let was, _) = action { return "\(line.page) · renamed, was \(was.isEmpty ? "untitled" : was)" }
        return line.detail.map { "\(line.page) · \($0)" } ?? line.page
    }
}

/// Undo for one change: a small bordered button, as iOS shows an action in a row.
private struct UndoButton: View {
    let action: FilingRecord.Entry
    let turn: UUID
    let label: Text
    @Environment(Library.self) private var library
    @Environment(Companion.self) private var companion

    var body: some View {
        Button("Undo") { companion.undoFiling(action, from: turn, in: library) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(Text("Undo: \(label)"))
    }
}

/// One change as a row: its kind (an icon) and what it says (the page is the
/// section's), the author's words and names in New York. Every change has one, even
/// one whose page, type or field has since been deleted: Undo goes newest first, and
/// a hidden change would leave an older one waiting for it with nothing to tap.
private struct Change {
    let symbol: String
    let detail: Text
    /// What VoiceOver says for its Undo.
    let spoken: Text
    /// The field it filled, for its timeline.
    let field: FieldKey?

    @MainActor init(_ action: FilingRecord.Entry, in library: Library) {
        func authored(_ s: String) -> Text { Text(s).fontDesign(.serif) }   // New York at the row's own size
        switch action {
        case .created(let created, _):
            symbol = "doc.badge.plus"
            let type = library.schema.type((library.pages.first { $0.id == created }
                                            ?? library.recentlyDeleted.first { $0.id == created })?.type)?.name
            detail = type.map { Text("New \(authored($0)) page") } ?? Text("New page")
        case .typed(_, let type):
            symbol = "tag"
            detail = Text("Type: \(authored(library.schema.type(type)?.name ?? "Deleted type"))")
        case .renamed(_, let was, _):
            symbol = "character.cursor.ibeam"
            detail = Text("Renamed, was \(was.isEmpty ? Text("untitled") : authored(was))")
        case .described(_, let text):
            symbol = "text.alignleft"
            detail = Text("Page text: \(authored(text))")
        case .value(_, let fieldID, let value), .replaced(_, let fieldID, _, let value):
            let field = library.schema.fields.first { $0.id == fieldID }?.name ?? "Deleted field"
            if case .replaced(_, _, let was, _) = action {
                symbol = "pencil"
                detail = Text("\(authored(field)): \(authored(library.filedValue(value))), was \(authored(library.filedValue(was)))")
            } else {
                symbol = "text.badge.plus"
                detail = Text("\(authored(field)): \(authored(library.filedValue(value)))")
            }
        case .newType, .newField, .fieldAdded:   // never among `actions`
            symbol = "questionmark"
            detail = Text("")
        }
        spoken = Text("\(action.page.map(library.pageName) ?? Text(Library.deletedPage)), \(detail)")
        if let page = action.page, let field = action.field {
            self.field = FieldKey(page: page, field: field)
        } else {
            field = nil
        }
    }
}
