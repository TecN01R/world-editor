import SwiftUI
import WriterCore

/// A page read as a wiki entry (`WikiEntry`; Kevin, 2026-11-27: "I do love reading a good wiki",
/// but not keeping one: "I want to feel like my world is growing itself and I'm uncovering it"):
/// its kind and name, how it begins as the lead, its facts in a box, the rest of what the author
/// wrote, the names of the world's other pages linked as a wiki links them, and where else the
/// world mentions it, quoting the sentence. Read only; Edit opens the page's editor. Everything
/// shown is the author's own words.
struct EntryView: View {
    @Environment(Library.self) private var library
    let page: WriterCore.Document
    let edit: () -> Void

    var body: some View {
        let paragraphs = page.paragraphs.map(\.text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let facts = library.fields(of: page).compactMap { field in page.values[field.id].map { (field: field, value: $0) } }
        let mentions = WikiEntry.mentions(of: page, in: library.pages, schema: library.schema)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    if let type = library.type(of: page) {
                        Text(type.name.uppercased())
                            .font(.caption.weight(.medium))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                    }
                    Text(page.heading.isEmpty ? "Untitled" : page.heading)
                        .font(.authored(.largeTitle).bold())
                        .accessibilityAddTraits(.isHeader)
                }
                if let lead = paragraphs.first {
                    linked(lead).font(.authored(.title3))
                }
                if !facts.isEmpty {
                    infobox(facts)
                }
                ForEach(Array(paragraphs.dropFirst().enumerated()), id: \.offset) { _, text in
                    linked(text).font(.authored(.body))
                }
                if paragraphs.isEmpty && facts.isEmpty {
                    Text("Nothing more is known of it yet. Talk about it, and what you say gathers here.")
                        .foregroundStyle(.secondary)
                }
                if !mentions.isEmpty {
                    mentionedIn(mentions)
                }
            }
            .foregroundStyle(Color(Look.ink))
            .lineSpacing(3)
            .frame(maxWidth: 640, alignment: .leading)   // a readable line, as the page's editor keeps
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .environment(\.openURL, OpenURLAction { url in
            guard let id = RichText.page(url) else { return .systemAction }
            library.selection = id
            return .handled
        })
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Edit", action: edit) }
        }
    }

    /// `text` with the world's other names linked, as a wiki links them.
    private func linked(_ text: String) -> Text {
        var string = AttributedString()
        for piece in WikiEntry.pieces(of: text, linking: library.pages, except: page.id) {
            string += piece.page.map { Self.link(piece.text, to: $0) } ?? AttributedString(piece.text)
        }
        return Text(string)
    }

    /// The facts, as a wiki's box of them: each field's name and the author's value.
    private func infobox(_ facts: [(field: FieldDefinition, value: FieldValue)]) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
            ForEach(facts, id: \.field.id) { fact in
                GridRow {
                    Text(fact.field.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    value(fact.value).font(.authored(.body))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(Look.raised), in: .rect(cornerRadius: 16))
    }

    /// A value as text; a page it holds, linked to it.
    private func value(_ value: FieldValue) -> Text {
        if case .page(let id) = value, let title = heading(of: id) {
            return Text(Self.link(title.isEmpty ? "Untitled" : title, to: id))
        }
        return Text(value.display { heading(of: $0) } ?? "")
    }

    /// Where else the world mentions it: each page, and the sentence there, in the author's words.
    private func mentionedIn(_ mentions: [WikiEntry.Mention]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mentioned in")
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(mentions, id: \.page) { mention in
                Button { library.selection = mention.page } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(heading(of: mention.page) ?? "Untitled")
                            .font(.authored(.headline))
                            .foregroundStyle(Color(Look.accent))
                        if let quote = mention.quote {
                            Text("\u{201C}\(quote)\u{201D}")
                                .font(.authored(.subheadline))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
    }

    /// `text` as a link to the page `id` (the form `@` links take, `RichText.url`), in the accent.
    private static func link(_ text: String, to id: UUID) -> AttributedString {
        var link = AttributedString(text)
        link.link = RichText.url(id)
        link.foregroundColor = Color(Look.accent)
        return link
    }

    /// The name of the world's page `id`, if it's there.
    private func heading(of id: UUID) -> String? {
        library.pages.first { $0.id == id }.map { $0.heading.isEmpty ? "Untitled" : $0.heading }
    }
}
