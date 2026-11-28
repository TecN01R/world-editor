import SwiftUI
import UIKit
import DesignTokens
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
        let type = library.type(of: page)
        let facts = library.fields(of: page).compactMap { field in page.values[field.id].map { (field: field, value: $0) } }
        let mentions = WikiEntry.mentions(of: page, in: library.pages, schema: library.schema)
        let written = page.paragraphs.contains { !$0.text.allSatisfy(\.isWhitespace) }
        // The writing starts `aboveWriting` under what heads the page. The kind's line, where it's
        // the last of that, keeps part of the room under itself (`pageKindLine`).
        let aboveWriting = type != nil && facts.isEmpty ? PageMetrics.kindLineToWriting : PageMetrics.aboveWriting
        ScrollView {
            // Down the page by `PageMetrics`, as the editor has it (`PageTextView`, `PageFields`).
            VStack(alignment: .leading, spacing: 0) {
                // The whole title, as the editor shows it: a page's name elsewhere stops at 80 characters.
                PageTitle(title: Typeset.printed(page.displayTitle))
                    .padding(.top, PageMetrics.aboveTitle)
                if let type {
                    Text(type.name)
                        .role(.label)
                        .pageKindLine()
                }
                if !facts.isEmpty {
                    factRows(facts)
                }
                if written {
                    PageWriting(text: writing)
                        .padding(.top, aboveWriting)
                } else if facts.isEmpty {
                    Text("Nothing more is known of it yet. Talk about it, and what you say gathers here.")
                        .foregroundStyle(.ink2)
                        .padding(.top, aboveWriting)
                }
                if !mentions.isEmpty {
                    mentionedIn(mentions)
                        .padding(.top, PageMetrics.beforeHeading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .readingColumn()
            .padding(.bottom, PageMetrics.bottom)
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

    /// The writing as the editor sets it (`ReadingType`, with its bold, italic and lists), its
    /// own `@` links and the names of the world's other pages linked, and its punctuation as
    /// print sets it. What's stored stays as typed.
    private var writing: NSAttributedString {
        // Empty lines at the end are where the next words would go: nothing to read.
        let paragraphs = Array(page.paragraphs.reversed().drop { $0.text.allSatisfy(\.isWhitespace) }.reversed())
        // Not in a column yet: the text view sets it for the one it's given (`ReadingTextView`).
        return ReadingType(columnWidth: 0, displayScale: 0).text(of: paragraphs) { paragraph, attributes in
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

    /// The facts as the editor's field rows (`PageFields`), in the same rows (`inFactRow`): each
    /// name beside its value, the two centred on the row, while the two columns fit; else the
    /// name above its value.
    private func factRows(_ facts: [(field: FieldDefinition, value: FieldValue)]) -> some View {
        ViewThatFits(in: .horizontal) {
            Grid(alignment: .leading, horizontalSpacing: PageMetrics.factColumnSpacing,
                 verticalSpacing: PageMetrics.factRowSpacing) {
                ForEach(facts, id: \.field.id) { fact in
                    GridRow { name(fact.field).inFactRow(); value(fact.value).inFactRow() }
                }
            }
            VStack(alignment: .leading, spacing: PageMetrics.factRowSpacing) {
                ForEach(facts, id: \.field.id) { fact in
                    VStack(alignment: .leading, spacing: Spacing.tight) {
                        name(fact.field).inFactRow(alignment: .bottomLeading)   // by its own value
                        value(fact.value).inFactRow()
                    }
                }
            }
        }
    }

    private func name(_ field: FieldDefinition) -> some View {
        Text(field.name).role(.label)
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
        .role(.value)
        .tint(.ink)   // a link underlined, not coloured
    }

    /// Where else the world mentions it: each page as the pages list shows it, with the sentence
    /// there that does, in the author's words.
    private func mentionedIn(_ mentions: [WikiEntry.Mention]) -> some View {
        VStack(alignment: .leading, spacing: PageMetrics.afterHeading) {
            Text("Mentioned In")
                .role(.heading)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Spacing.row) {
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

    func makeUIView(context: Context) -> ReadingTextView {
        let tv = ReadingTextView(usingTextLayoutManager: true)
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

    func updateUIView(_ tv: ReadingTextView, context: Context) {
        tv.show(text)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView tv: ReadingTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        return CGSize(width: width, height: tv.height(in: width))
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

/// The text view of the page's writing where the page is read. It keeps the writing set for the
/// column it's given (`ReadingType`), setting it again in place when that changes, as the
/// editor's does (`PageTextView`).
final class ReadingTextView: UITextView {
    /// The writing as it was handed over, before it was set for a column: what the next is
    /// compared with.
    private var source: NSAttributedString?
    /// How the writing is set now; nil until it's measured for a column.
    private var reading: ReadingType?

    /// Shows `text`, unless it's what is showing.
    func show(_ text: NSAttributedString) {
        guard text != source else { return }
        source = text
        attributedText = text
        reading = nil
    }

    /// How tall the writing is in a column `width` wide, its lines set for that column.
    func height(in width: CGFloat) -> CGFloat {
        set(for: width)
        return ceil(sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Laid out in a column, or on a screen, it wasn't last measured for: set for this one,
        // and measured again.
        if bounds.width > 0, set(for: bounds.width) { invalidateIntrinsicContentSize() }
    }

    /// Sets the writing for a column `width` wide, if it isn't; returns whether it had to.
    @discardableResult private func set(for width: CGFloat) -> Bool {
        let reading = ReadingType(columnWidth: width, displayScale: traitCollection.displayScale)
        guard reading != self.reading else { return false }
        self.reading = reading
        reading.restyle(textStorage)
        return true
    }
}
