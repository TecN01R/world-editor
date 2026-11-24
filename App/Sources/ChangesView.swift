import SwiftUI
import WriterCore

/// Everything the companion filed into the pages from this conversation (Changes,
/// beside the menu): a stock grouped list, newest message first, each change a
/// row with its kind, page and what it says, and Undo. Undo goes newest first, so
/// a change something filed since built on says "Changed since" instead. A field
/// changed more than once opens its timeline (Kevin, 2026-11-24).
struct ChangesView: View {
    @Environment(Library.self) private var library
    @Environment(Companion.self) private var companion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        NavigationStack {
            List {
                ForEach(turns.reversed()) { turn in
                    Section {
                        ForEach(turn.filed?.actions ?? [], id: \.self) { action in
                            row(Change(action, in: library), from: turn.id)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("“\(turn.answer ?? "")”").font(.authored(.subheadline)).lineLimit(3)
                            Ago(date: turn.answered ?? turn.asked)
                        }
                        .textCase(nil)
                    }
                }
            }
            .overlay {
                if turns.isEmpty {   // all undone while it's open
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

    /// The answers something is still filed from.
    private var turns: [Conversation.Turn] {
        companion.conversation.turns.filter { !($0.filed?.isEmpty ?? true) }
    }

    @ViewBuilder private func row(_ change: Change, from turn: UUID) -> some View {
        let later = companion.conversation.changedLater(change.action, in: turn, elsewhere: companion.others)
        // At the largest text sizes Undo goes under the words rather than squeezing them.
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())
        let content = layout {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.page).font(.authored(.body))
                    change.detail.font(.subheadline).foregroundStyle(.secondary)
                    if later {
                        Text("Changed since").font(.caption).foregroundStyle(.secondary)
                            .accessibilityHint("Something filed since changed this. Undo that first.")
                    }
                }
            } icon: {
                Image(systemName: change.symbol)
            }
            if !textSize.isAccessibilitySize { Spacer(minLength: 8) }
            if !later { UndoButton(action: change.action, turn: turn, label: change.spoken) }
        }
        if let key = change.field,
           companion.conversation.history(of: key.field, on: key.page).count > 1 {
            NavigationLink(value: key) { content }
                .accessibilityHint("Shows the values the companion gave this field.")
        } else {
            content
        }
    }
}

/// A field changed more than once: every value the companion gave it from this
/// conversation, newest first, each with the message it came from and when. Undo
/// on the newest steps back to the one before, while the field still holds it.
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
                            // Only while it's what the field holds: Undo would otherwise change nothing.
                            if current {
                                UndoButton(action: change.action, turn: change.turn, label: Text(library.filedValue(change.value)))
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
                    Text(library.filedName(key.page)).font(.authored(.subheadline)).textCase(nil)
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

/// "5 minutes ago", kept up to date while it's on screen.
private struct Ago: View {
    let date: Date

    var body: some View {
        TimelineView(.everyMinute) { _ in
            Text(date.formatted(.relative(presentation: .named, unitsStyle: .wide)))
        }
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

/// One change as a row: its kind (an icon), the page, and what it says, the
/// author's words and names in New York. Every change has one, even one whose
/// page, type or field has since been deleted: Undo goes newest first, and a
/// hidden change would leave an older one waiting for it with nothing to tap.
private struct Change {
    let action: FilingRecord.Entry
    let symbol: String
    let page: String
    let detail: Text
    /// What VoiceOver says for its Undo.
    let spoken: Text
    /// The field it filled, for its timeline.
    let field: FieldKey?

    @MainActor init(_ action: FilingRecord.Entry, in library: Library) {
        func authored(_ s: String) -> Text { Text(s).font(.authored(.subheadline)) }
        self.action = action
        page = action.page.map(library.filedName) ?? Library.deletedPage
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
        spoken = Text("\(page), \(detail)")
        if let page = action.page, let field = action.field {
            self.field = FieldKey(page: page, field: field)
        } else {
            field = nil
        }
    }
}
