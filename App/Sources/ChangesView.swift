import SwiftUI
import WriterCore

/// Everything the companion filed into the pages from this conversation (Changes, in
/// the conversation's More menu), as a timeline (Kevin, 2026-11-24: "it should be a timeline"):
/// newest at the top, a point for each of the author's messages that changed
/// something, with what it changed under it. A field's change shows the value it
/// replaced, and opens that field's own timeline. Undo on a point takes back what
/// that message filed and everything filed after it, after listing them when it's
/// more than one. The rail is custom (Kevin asked for a timeline; iOS has no stock
/// one); the rest is a stock plain list.
struct ChangesView: View {
    @Environment(Library.self) private var library
    @Environment(Companion.self) private var companion
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let conversation = companion.conversation
        // The author's messages that changed something, newest first.
        let moments = conversation.turns.reversed().filter { $0.filed?.isEmpty == false }
        NavigationStack {
            List {
                ForEach(Array(moments.enumerated()), id: \.element.id) { i, turn in
                    let message = turn.answer ?? ""
                    TimelineRow(mark: .point, top: i > 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Ago(date: turn.filed?.date ?? turn.answered ?? turn.asked)
                                .font(.subheadline).foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            UndoPointButton(newest: i == 0, label: Text("what “\(message)” changed")) {
                                companion.rewindChain(to: turn.id)
                            }
                        }
                        Text("“\(message)”").font(.authored(.body))
                    }
                    ForEach(turn.filed?.actions ?? [], id: \.self) { action in
                        change(action, on: conversation.page)
                    }
                }
                if !moments.isEmpty, let first = conversation.turns.first {
                    TimelineRow(mark: .start, bottom: false) {
                        Text("Conversation began").font(.subheadline)
                        Ago(date: first.asked).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .overlay {
                if moments.isEmpty {   // all undone while it's open
                    ContentUnavailableView("No Changes", systemImage: "clock.arrow.circlepath",
                                           description: Text("What the companion adds to your pages from this conversation shows here."))
                }
            }
            .lookBackground()
            .navigationTitle("Changes")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: FieldKey.self) { FieldTimeline(key: $0) }
            .toolbar {
                // Undo applies at once: nothing to save, so Close.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .toolbarVerticalBehavior(.disabled)   // its bar across the top, not in the folded Duo's side column
        }
    }

    /// One thing a message changed, under its point; a field opens its own timeline.
    @ViewBuilder private func change(_ action: FilingRecord.Entry, on page: UUID) -> some View {
        let change = Change(action, in: library)
        let line = TimelineRow {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    change.detail
                    // A change to another page says which (a world conversation's are all elsewhere).
                    if action.page != page { change.page }
                }
            } icon: {
                Image(systemName: change.symbol).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(change.spoken)
        }
        if let key = change.field {
            // The link is the row, so it takes the timeline's insets itself.
            NavigationLink(value: key) { line }
                .accessibilityHint("Shows every value the companion gave this field.")
                .timelineInsets()
        } else {
            line
        }
    }
}

/// A field's own timeline: every value the companion gave it from this conversation,
/// newest first, each with the message it came from and when, down to what it held
/// before. Undo on a value takes it back and every later one, and what was built on
/// them, so the field goes back to the value under it.
struct FieldTimeline: View {
    let key: FieldKey
    @Environment(Library.self) private var library
    @Environment(Companion.self) private var companion

    var body: some View {
        let history = Array(companion.conversation.history(of: key.field, on: key.page).reversed())
        let now = library.pages.first { $0.id == key.page }?.values[key.field]
        // Changed since outside this conversation (by hand, or from another's): Undo here would change nothing.
        let elsewhere = history.first.map { now != $0.value } ?? false
        List {
            if elsewhere {
                TimelineRow(mark: .point, top: false) {
                    value(now)
                    Text("Now, changed outside this conversation").font(.subheadline).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            ForEach(Array(history.enumerated()), id: \.element) { i, change in
                TimelineRow(mark: .point, top: i > 0 || elsewhere) {
                    HStack(alignment: .firstTextBaseline) {
                        value(change.value)
                        Spacer(minLength: 8)
                        if !elsewhere {
                            UndoPointButton(newest: i == 0, label: Text(library.filedValue(change.value))) {
                                companion.undoChain(change.action, from: change.turn)
                            }
                        }
                    }
                    Text("“\(change.message)”").font(.authored(.footnote)).foregroundStyle(.secondary).lineLimit(3)
                    Ago(date: change.date, current: i == 0 && !elsewhere).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if let oldest = history.last {
                TimelineRow(mark: .start, bottom: false) {
                    value(oldest.action.was)
                    Text("Before").font(.subheadline).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .lookBackground()
        .navigationTitle(library.schema.fields.first { $0.id == key.field }?.name ?? "Field")
        .navigationSubtitle(library.pageName(key.page))
        .toolbarVerticalBehavior(.disabled)   // as the Changes it's pushed from
        .overlay {
            if history.isEmpty {   // all undone while it's open
                ContentUnavailableView("No Changes", systemImage: "clock.arrow.circlepath")
            }
        }
    }

    private func value(_ value: FieldValue?) -> Text {
        value.map { Text(library.filedValue($0)).font(.authored(.body)) } ?? Text("Empty").foregroundStyle(.secondary)
    }
}

/// A page's field, for a field's timeline.
struct FieldKey: Hashable {
    var page: UUID
    var field: UUID
}

/// A row of a timeline: `content` beside the rail, which has a point (`mark`) at the
/// content's first line, or just runs past. The rail comes down from the row above
/// (`top`) and goes on to the row below (`bottom`).
private struct TimelineRow<Content: View>: View {
    enum Mark { case none, point, start }
    var mark = Mark.none
    var top = true
    var bottom = true
    @ViewBuilder var content: Content
    @ScaledMetric(relativeTo: .subheadline) private var dot: CGFloat = 11
    @ScaledMetric(relativeTo: .subheadline) private var column: CGFloat = 20
    /// How far down the row its point sits, to the middle of the first line.
    @ScaledMetric(relativeTo: .subheadline) private var center: CGFloat = 20

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Group {
                switch mark {
                case .point: Circle().fill(.tint)
                case .start: Circle().strokeBorder(.tertiary, lineWidth: 2)
                case .none: Color.clear
                }
            }
            .frame(width: dot, height: dot)
            // Centred on the first line's lower-case letters.
            .alignmentGuide(.firstTextBaseline) { [lift = dot * 0.35] in $0[VerticalAlignment.center] + lift }
            .frame(width: column)
            VStack(alignment: .leading, spacing: 4) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, mark == .none ? 6 : 10)
        .background(alignment: .leading) {
            VStack(spacing: 0) {
                Rectangle().frame(width: 2, height: center).opacity(top ? 1 : 0)
                Rectangle().frame(width: 2).frame(maxHeight: .infinity).opacity(bottom ? 1 : 0)
            }
            .foregroundStyle(.tertiary)
            .frame(width: column)
        }
        .timelineInsets()
    }
}

extension View {
    /// A timeline's rows touch, so the rail runs unbroken from point to point.
    fileprivate func timelineInsets() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
    }
}

/// "5 minutes ago" ("Current · 5 minutes ago" for the value a field holds), kept up
/// to date while it's on screen.
private struct Ago: View {
    let date: Date
    var current = false

    var body: some View {
        TimelineView(.everyMinute) { _ in
            let ago = date.formatted(.relative(presentation: .named, unitsStyle: .wide))
            Text(current ? "Current · \(ago)" : ago)
        }
    }
}

extension Library {
    /// A filed page's name as Changes shows it: its title in New York at the size
    /// around it; "Untitled" while it has none (as everywhere) and "Deleted page"
    /// are the app's words, in San Francisco.
    fileprivate func pageName(_ id: UUID) -> Text {
        switch (pages.first { $0.id == id } ?? recentlyDeleted.first { $0.id == id })?.heading {
        case nil: Text(Self.deletedPage)
        case ""?: Text(WriterCore.Document.untitled)
        case let heading?: Text(heading).fontDesign(.serif)
        }
    }
}

/// Undo on a timeline's point: what it changed and everything after it there
/// (`find`), newest first, after a stock confirmation that lists them when it's
/// more than one (Kevin, 2026-11-24: "undo to this point and all layered changes
/// would be undone"). Built on from another conversation: says so instead.
private struct UndoPointButton: View {
    /// The newest point: nothing after it, so no "…".
    let newest: Bool
    /// What it takes back, for VoiceOver.
    let label: Text
    let find: () -> [Conversation.Filed]?
    @Environment(Library.self) private var library
    @Environment(Companion.self) private var companion
    @State private var chain: [Conversation.Filed]?
    @State private var blocked = false

    var body: some View {
        UndoButton {
            switch find() {
            case nil: blocked = true
            case let found? where found.count == 1: companion.undo(found, in: library)
            case let found?: chain = found
            }
        }
        .accessibilityLabel(newest ? Text("Undo \(label)") : Text("Undo \(label), and everything after it"))
        .confirmationDialog(chain.map { "Undo \($0.count) changes?" } ?? "",
                            isPresented: Binding { chain != nil } set: { if !$0 { chain = nil } },
                            titleVisibility: .visible, presenting: chain) { chain in
            Button("Undo \(chain.count) Changes", role: .destructive) { companion.undo(chain, in: library) }
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
        if case .renamed(_, let was, _) = action { return "\(line.page) · renamed, was \(was.isEmpty ? WriterCore.Document.untitled : was)" }
        return line.detail.map { "\(line.page) · \($0)" } ?? line.page
    }
}

/// One change as a line on the timeline: an icon for its kind and what it did, the
/// author's words and page names in New York, types and fields in San Francisco; a
/// corrected value shows the one it replaced ("Age: about sixteen → seventeen"). Every
/// change has one, even one whose page, type or field has since been deleted, so its
/// point can still be undone.
private struct Change {
    let symbol: String
    let detail: Text
    /// What VoiceOver says for it.
    let spoken: Text
    /// The field it filled, for its timeline.
    let field: FieldKey?
    /// The page it changed, to show under it when that isn't the conversation's;
    /// nil for a new page, whose line names it.
    let page: Text?

    @MainActor init(_ action: FilingRecord.Entry, in library: Library) {
        func authored(_ s: String) -> Text { Text(s).fontDesign(.serif) }   // New York at the row's own size
        func value(_ v: FieldValue) -> Text { authored(library.filedValue(v)) }
        let page = action.page.map(library.pageName) ?? Text(Library.deletedPage)
        switch action {
        case .created(let created, _):
            symbol = "doc.badge.plus"
            let type = library.schema.type((library.pages.first { $0.id == created }
                                            ?? library.recentlyDeleted.first { $0.id == created })?.type)?.name
            detail = Text("New \(type ?? "page"): \(page)")
            spoken = detail
        case .typed(_, let type):
            symbol = "tag"
            detail = Text("Type: \(library.schema.type(type)?.name ?? "Deleted type")")
            spoken = Text("\(page), \(detail)")
        case .renamed(_, let was, let title):
            symbol = "character.cursor.ibeam"
            let old = was.isEmpty ? Text(WriterCore.Document.untitled) : authored(was)
            detail = Text("Renamed: \(old) → \(authored(title))")
            spoken = Text("Renamed from \(old) to \(authored(title))")
        case .described(_, let text):
            symbol = "text.alignleft"
            detail = Text("Page text: \(authored(text))")
            spoken = Text("\(page), \(detail)")
        case .placed(let placement):
            symbol = "text.append"
            detail = Text("Added to the page: \(authored(placement.texts.joined(separator: " ")))")
            spoken = Text("\(page), \(detail)")
        case .value(_, let fieldID, let new), .replaced(_, let fieldID, _, let new):
            let field = library.schema.fields.first { $0.id == fieldID }?.name ?? "Deleted field"
            if let was = action.was {
                symbol = "pencil"
                detail = Text("\(field): \(value(was)) → \(value(new))")
                spoken = Text("\(page), \(field) changed from \(value(was)) to \(value(new))")
            } else {
                symbol = "text.badge.plus"
                detail = Text("\(field): \(value(new))")
                spoken = Text("\(page), \(detail)")
            }
        case .newType, .newField, .fieldAdded:   // never among `actions`
            symbol = "questionmark"
            detail = Text("")
            spoken = detail
        }
        if case .created = action {
            self.page = nil
        } else {
            self.page = page.font(.subheadline).foregroundStyle(.secondary)
        }
        if let page = action.page, let field = action.field {
            self.field = FieldKey(page: page, field: field)
        } else {
            field = nil
        }
    }
}
