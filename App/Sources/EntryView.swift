import SwiftUI
import UIKit
import WriterCore

/// A page read (Kevin, 2026-11-27: "I do love reading a good wiki", but not keeping one: "I want to
/// feel like my world is growing itself and I'm uncovering it"): the editor's page with typing off
/// (docs/design.md: "Read and Edit are the same page"). Its title, its kind and its facts sit where
/// the editor has them, and its writing is set as the editor sets it, with its punctuation as print
/// sets it (`Typeset`) and the names of the world's other pages linked, as a wiki links them. Under
/// it, where else the world mentions it, quoting the sentence. Edit opens the page's editor.
/// Everything shown is the author's own words.
struct EntryView: View {
    @Environment(Library.self) private var library
    /// Read so a new text size sets the page again at that size.
    @Environment(\.dynamicTypeSize) private var textSize
    let page: WriterCore.Document
    let edit: () -> Void

    var body: some View {
        let facts = library.fields(of: page).compactMap { field in page.values[field.id].map { (field: field, value: $0) } }
        let mentions = WikiEntry.mentions(of: page, in: library.pages, schema: library.schema)
        let written = page.paragraphs.contains { !$0.text.allSatisfy(\.isWhitespace) }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(Typeset.printed(page.displayName))
                    .font(Font(PageEditor.titleFont))
                    .foregroundStyle(Color(Look.ink))
                    .padding(.top, PageLayout.titleTop)
                    .accessibilityAddTraits(.isHeader)
                if let type = library.type(of: page) {
                    Text(type.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, PageLayout.kindGap)
                }
                if !facts.isEmpty {
                    factRows(facts)
                        .padding(.top, 14)   // as the editor's fields sit under the kind (`PageFields`)
                }
                if written {
                    PageWriting(text: writing)
                        .padding(.top, PageLayout.writingGap)
                } else if facts.isEmpty {
                    Text("Nothing more is known of it yet. Talk about it, and what you say gathers here.")
                        .foregroundStyle(.secondary)
                        .padding(.top, PageLayout.writingGap)
                }
                if !mentions.isEmpty {
                    mentionedIn(mentions)
                        .padding(.top, 32)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .readingColumn()
            .padding(.bottom, PageLayout.bottom)
        }
        // A fact's page link opens its page; the writing's links go through `PageWriting`.
        .environment(\.openURL, OpenURLAction { url in
            guard let id = RichText.page(url) else { return .systemAction }
            library.selection = id
            return .handled
        })
        .toolbar {
            // The screen's one main action, pinned at the trailing end (docs/design.md).
            ToolbarItem(placement: .topBarPinnedTrailing) {
                Button("Edit", systemImage: "pencil", action: edit)
            }
        }
    }

    /// The writing as the editor sets it (`PageEditor.attributes`, with its bold, italic and
    /// lists), its own `@` links and the names of the world's other pages linked, and its
    /// punctuation as print sets it. What's stored stays as typed.
    private var writing: NSAttributedString {
        // Empty lines at the end are where the next words would go: nothing to read.
        let paragraphs = Array(page.paragraphs.reversed().drop { $0.text.allSatisfy(\.isWhitespace) }.reversed())
        return PageEditor.text(of: paragraphs) { paragraph, attributes in
            let text = RichText.attributed(paragraph.text, runs: paragraph.runs, links: paragraph.links, attributes: attributes)
            var at = 0
            for piece in WikiEntry.pieces(of: paragraph.text, linking: library.pages, except: page.id) {
                let range = NSRange(location: at, length: piece.text.utf16.count)
                // The author's own `@` link wins where there is one.
                if let id = piece.page, text.attribute(.link, at: at, effectiveRange: nil) == nil {
                    text.addAttribute(.link, value: RichText.url(id), range: range)
                }
                at += range.length
            }
            // Last to first, so each change's place is still where it was in the typed text.
            for change in Typeset.changes(in: paragraph.text).reversed() {
                text.replaceCharacters(in: NSRange(location: change.range.lowerBound, length: change.range.count),
                                       with: change.replacement)
            }
            return text
        }
    }

    /// The facts as the editor's field rows (`PageFields`): each name beside its value while
    /// the two columns fit, else above it.
    private func factRows(_ facts: [(field: FieldDefinition, value: FieldValue)]) -> some View {
        ViewThatFits(in: .horizontal) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 10) {
                ForEach(facts, id: \.field.id) { fact in
                    GridRow { name(fact.field); value(fact.value) }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(facts, id: \.field.id) { fact in
                    VStack(alignment: .leading, spacing: 2) { name(fact.field); value(fact.value) }
                }
            }
        }
    }

    private func name(_ field: FieldDefinition) -> some View {
        Text(field.name).font(.subheadline).foregroundStyle(.secondary)
    }

    /// A value as print sets it; a page it holds, linked to it.
    private func value(_ value: FieldValue) -> some View {
        Group {
            if case .page(let id) = value, let title = pageName(id) {
                Text(Self.link(title, to: id))
            } else {
                Text(Typeset.printed(value.display { pageName($0) } ?? ""))
            }
        }
        .font(.authored(.body))
        .foregroundStyle(Color(Look.ink))
        .tint(Color(Look.ink))   // a link underlined, not coloured
    }

    /// Where else the world mentions it: each page as the pages list shows it, with the sentence
    /// there that does, in the author's words.
    private func mentionedIn(_ mentions: [WikiEntry.Mention]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mentioned In")
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(mentions, id: \.page) { mention in
                if let other = library.pages.first(where: { $0.id == mention.page }) {
                    Button { library.selection = other.id } label: {
                        PageRow(page: other, line: mention.quote.map { Typeset.printed("\"\($0)\"") }, lineLimit: nil)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// `text` as a link to the page `id` (the form `@` links take, `RichText.url`), underlined.
    private static func link(_ text: String, to id: UUID) -> AttributedString {
        var link = AttributedString(text)
        link.link = RichText.url(id)
        link.underlineStyle = .single   // links underlined, not coloured (one look, grey and white)
        return link
    }

    /// The name of the world's page `id`, if it's there.
    private func pageName(_ id: UUID) -> String? {
        library.pages.first { $0.id == id }.map { Typeset.printed($0.displayName) }
    }
}

/// The page's writing as the editor shows it, with typing off: a stock text view that doesn't
/// scroll, sized to its text, so its lines break as the editor's do. A link opens its page.
private struct PageWriting: UIViewRepresentable {
    @Environment(Library.self) private var library
    let text: NSAttributedString

    func makeCoordinator() -> Coordinator { Coordinator(library: library) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView(usingTextLayoutManager: true)
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0   // as the editor's, on the column's edge
        tv.linkTextAttributes = Look.link
        tv.delegate = context.coordinator
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.attributedText != text { tv.attributedText = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView tv: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        let fitted = tv.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
    }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        let library: Library

        init(library: Library) { self.library = library }

        /// Tapping a link opens its page.
        func textView(_ tv: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            guard case .link(let url) = textItem.content, let page = RichText.page(url) else { return defaultAction }
            return UIAction { [weak self] _ in self?.open(page) }
        }

        /// Holding a link: Open its page, as in the editor.
        func textView(_ tv: UITextView, menuConfigurationFor textItem: UITextItem,
                      defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
            guard case .link(let url) = textItem.content, let id = RichText.page(url) else { return .init(menu: defaultMenu) }
            guard let page = library.pages.first(where: { $0.id == id }) else { return nil }
            let open = UIAction(title: "Open “\(page.displayName)”", image: UIImage(systemName: "arrow.up.right")) { [weak self] _ in
                self?.open(id)
            }
            return .init(menu: UIMenu(children: [open]))
        }

        private func open(_ page: UUID) {
            guard library.pages.contains(where: { $0.id == page }) else { return }
            DispatchQueue.main.async { [library] in library.selection = page }   // this page goes away
        }
    }
}
