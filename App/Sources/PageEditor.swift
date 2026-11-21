import SwiftUI
import UIKit
import WriterCore

/// Edit mode: the whole page, with real paragraph spacing, lists and a
/// formatting bar above the keyboard. Typing is native UITextView (undo,
/// autocorrect, dictation, selection all behave as iOS users expect).
struct PageEditor: UIViewRepresentable {
    @Environment(Library.self) private var library

    func makeCoordinator() -> Coordinator { Coordinator(library: library) }

    func makeUIView(context: Context) -> PageTextView {
        let tv = PageTextView(usingTextLayoutManager: true)
        tv.delegate = context.coordinator
        tv.backgroundColor = .systemBackground
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.allowsEditingTextAttributes = true      // ⌘B, ⌘I and the Format menu
        tv.inputAccessoryView = context.coordinator.formatBar
        tv.titleField = context.coordinator.titleField
        context.coordinator.textView = tv
        context.coordinator.render(selection: nil)
        context.coordinator.restoreCaret()
        return tv
    }

    func updateUIView(_ tv: PageTextView, context: Context) {}

    /// Bold New York, scaled with Dynamic Type.
    static var titleFont: UIFont { newYork(30, weight: .bold, scaledAs: .title1) }

    /// New York at 19 pt for the default text size, scaled with Dynamic Type.
    static var font: UIFont { newYork(19, weight: .regular, scaledAs: .body) }

    private static func newYork(_ size: CGFloat, weight: UIFont.Weight, scaledAs style: UIFont.TextStyle) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let serif = UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: serif)
    }

    static func attributes(_ kind: ParagraphKind) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.35
        p.paragraphSpacing = kind.isList ? 4 : 14
        if let list = RichText.list(for: kind) { p.textLists = [list] }
        return [.font: font, .foregroundColor: UIColor.label, .paragraphStyle: p]
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UITextFieldDelegate {
        let library: Library
        weak var textView: UITextView?
        /// Replacing the text moves the selection; that isn't the user moving the caret.
        private var isRendering = false
        lazy var formatBar = FormatBar { [weak self] action in self?.perform(action) }

        lazy var titleField: UITextField = {
            let f = UITextField()
            f.font = PageEditor.titleFont
            f.adjustsFontForContentSizeCategory = true
            f.textColor = .label
            f.placeholder = "Title"
            f.text = library.document.title
            f.returnKeyType = .next
            f.autocapitalizationType = .words
            f.accessibilityLabel = "Title"
            f.delegate = self
            f.addAction(UIAction { [weak self, weak f] _ in
                self?.library.update { $0.setTitle(f?.text ?? "") }
            }, for: .editingChanged)
            return f
        }()

        /// Return in the title moves on to the writing.
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textView?.becomeFirstResponder()
            return false
        }

        init(library: Library) {
            self.library = library
            super.init()
            // Text size changed in Settings: show the page at the new size.
            NotificationCenter.default.addObserver(forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let tv = self.textView else { return }
                    self.titleField.font = PageEditor.titleFont
                    self.render(selection: tv.selectedRange)
                }
            }
        }

        private var selection: Range<Int> {
            let r = textView?.selectedRange ?? NSRange()
            return r.location..<(r.location + r.length)
        }

        // MARK: Model → view

        /// Shows the page as stored, keeping the selection.
        func render(selection: NSRange?) {
            guard let tv = textView else { return }
            isRendering = true
            defer { isRendering = false }
            let doc = library.document
            let s = NSMutableAttributedString()
            for (i, p) in doc.paragraphs.enumerated() {
                let attrs = PageEditor.attributes(p.kind)
                s.append(RichText.attributed(p, attributes: attrs))
                if i < doc.paragraphs.count - 1 { s.append(NSAttributedString(string: "\n", attributes: attrs)) }
            }
            tv.attributedText = s
            if let selection { tv.selectedRange = selection }
            updateTypingAttributes()
            updateFormatBar()
        }

        /// New text takes the style before the caret and the caret paragraph's kind.
        private func updateTypingAttributes() {
            guard let tv = textView else { return }
            let (i, offset) = library.document.locate(tv.selectedRange.location)
            let p = library.document.paragraphs[i]
            var attrs = PageEditor.attributes(p.kind)
            attrs[.font] = RichText.font(PageEditor.font, p.style(at: offset))
            tv.typingAttributes = attrs
        }

        // MARK: View → model

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Return on an empty list item ends the list, as in Notes.
            guard text == "\n", range.length == 0 else { return true }
            let p = library.document.paragraphs[library.document.locate(range.location).index]
            guard p.kind.isList, p.text.isEmpty else { return true }
            library.update { $0.toggleKind(p.kind, in: range.location..<range.location) }
            render(selection: range)
            return false
        }

        func textViewDidChange(_ tv: UITextView) {
            let trailing = RichText.kind(of: tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle)
            let paragraphs = RichText.paragraphs(from: tv.attributedText, trailingKind: trailing)
            library.update { $0.setParagraphs(paragraphs) }
            updateFormatBar()
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            tv.typingAttributes[.link] = nil   // typing beside a link never extends it
            guard !isRendering else { return }
            let (i, offset) = library.document.locate(tv.selectedRange.location)
            library.cursor = (i, offset)
            updateFormatBar()
        }

        /// Tapping a link opens its page.
        func textView(_ tv: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            guard case .link(let url) = textItem.content, let page = RichText.page(url) else { return defaultAction }
            return UIAction { [weak self] _ in self?.open(page) }
        }

        // MARK: @ links

        private func open(_ page: UUID) {
            guard library.pages.contains(where: { $0.id == page }) else { return }
            DispatchQueue.main.async { [library] in library.selection = page }   // this editor goes away
        }

        /// Turns the typed `@query` into a link to `page`.
        private func link(to page: UUID, title: String, replacing range: Range<Int>, in index: Int) {
            var caret = 0
            library.update { caret = $0.insertLink(to: page, title: title, replacing: range, in: index) }
            render(selection: NSRange(location: library.document.paragraphStarts[index] + caret, length: 0))
            UISelectionFeedbackGenerator().selectionChanged()
        }

        /// Pages matching the `@query` at the caret, then a new page by that name.
        private func suggestions(at caret: (index: Int, offset: Int)) -> [FormatBar.Suggestion] {
            let doc = library.document, p = doc.paragraphs[caret.index]
            let others = library.pages.filter { $0.id != doc.id && !$0.heading.isEmpty }
            guard selection.isEmpty, p.link(at: caret.offset) == nil,
                  let mention = Mention.query(in: p.text, caret: caret.offset, titles: others.map(\.heading))
            else { return [] }
            var items = others.filter { Mention.matches(mention.query, $0.heading) }.prefix(3).map { page in
                FormatBar.Suggestion(title: page.heading, label: "Link to \(page.heading)") { [weak self] in
                    self?.link(to: page.id, title: page.heading, replacing: mention.range, in: caret.index)
                }
            }
            let title = mention.query.trimmingCharacters(in: .whitespaces)
            if !title.isEmpty, !others.contains(where: { $0.heading.localizedCaseInsensitiveCompare(title) == .orderedSame }) {
                items.append(FormatBar.Suggestion(title: "New Page “\(title)”", label: "Link to a new page, \(title)") { [weak self] in
                    guard let self else { return }
                    link(to: library.addPage(titled: title), title: title, replacing: mention.range, in: caret.index)
                })
            }
            return items
        }

        // MARK: Formatting

        private func perform(_ action: FormatBar.Action) {
            guard let tv = textView else { return }
            let range = selection
            switch action {
            case .style(let style) where range.isEmpty:
                // No selection: the next characters typed take the style.
                let current = RichText.style(of: tv.typingAttributes[.font] as? UIFont)
                tv.typingAttributes[.font] = RichText.font(PageEditor.font, current.symmetricDifference(style))
                updateFormatBar()
                return
            case .style(let style):
                library.update { $0.toggle(style, in: range) }
            case .list(let kind):
                library.update { $0.toggleKind(kind, in: range) }
            }
            render(selection: tv.selectedRange)
            UISelectionFeedbackGenerator().selectionChanged()
        }

        private func updateFormatBar() {
            guard let tv = textView else { return }
            let doc = library.document, range = selection
            func active(_ style: InlineStyle) -> Bool {
                range.isEmpty ? RichText.style(of: tv.typingAttributes[.font] as? UIFont).contains(style)
                              : doc.has(style, in: range)
            }
            let caret = doc.locate(range.lowerBound)
            let p = doc.paragraphs[caret.index]
            // Caret in a link: a button to open its page (tapping the link itself may just place the caret).
            let linked = range.isEmpty ? p.link(at: caret.offset).flatMap { link in library.pages.first { $0.id == link.page } } : nil
            let open = linked.map { page in
                FormatBar.Suggestion(title: "Open \(page.heading)", label: "Open \(page.heading)") { [weak self] in
                    self?.open(page.id)
                }
            }
            formatBar.update(bold: active(.bold), italic: active(.italic), kind: p.kind,
                             open: open, suggestions: suggestions(at: caret))
        }

        func restoreCaret() {
            guard let tv = textView else { return }
            let doc = library.document
            let p = min(library.cursor.paragraph, doc.paragraphs.count - 1)
            let loc = doc.paragraphStarts[p] + min(library.cursor.offset, doc.paragraphs[p].length)
            tv.selectedRange = NSRange(location: loc, length: 0)
            updateTypingAttributes()
            // A new page starts in its title; otherwise carry on writing.
            let startInTitle = doc.isEmpty && !Screenshots.isActive
            DispatchQueue.main.async { [titleField] in
                if startInTitle { titleField.becomeFirstResponder(); return }
                tv.becomeFirstResponder()
                tv.scrollRangeToVisible(tv.selectedRange)
            }
        }
    }
}

/// Bold, italic, bulleted and numbered list above the keyboard, or pages to
/// link while typing `@`. One glass capsule centred on the keyboard, with a
/// small gap above it as in Notes. It scrolls sideways when its buttons don't
/// fit, as Notes' does: customised at Kevin's request, since the stock toolbar
/// folds extra items into "•••" and centres on the app rather than the keyboard.
final class FormatBar: UIView {
    enum Action { case style(InlineStyle), list(ParagraphKind) }

    /// A page to link to while typing `@`, or to open from a link.
    struct Suggestion {
        let title: String
        let label: String
        let action: () -> Void
    }

    private static let gap: CGFloat = 8
    private static let barHeight: CGFloat = 44
    private let capsule = UIVisualEffectView(effect: UIGlassEffect())
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var buttons: [UIButton] = []

    init(onAction: @escaping (Action) -> Void) {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: Self.barHeight + Self.gap))
        autoresizingMask = .flexibleHeight
        buttons = [Self.button(symbol: "bold", label: "Bold") { onAction(.style(.bold)) },
                   Self.button(symbol: "italic", label: "Italic") { onAction(.style(.italic)) },
                   Self.button(symbol: "list.bullet", label: "Bulleted List") { onAction(.list(.bullet)) },
                   Self.button(symbol: "list.number", label: "Numbered List") { onAction(.list(.numbered)) }]

        capsule.cornerConfiguration = .capsule()
        capsule.clipsToBounds = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = false
        stack.axis = .horizontal
        for v in [capsule, scroll, stack] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false }
        scroll.addSubview(stack)
        capsule.contentView.addSubview(scroll)
        addSubview(capsule)

        let pad: CGFloat = 6
        let fit = capsule.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: 2 * pad)
        fit.priority = .defaultHigh   // as wide as its buttons, until the keyboard's width runs out
        NSLayoutConstraint.activate([
            capsule.centerXAnchor.constraint(equalTo: centerXAnchor),   // the keyboard's centre
            capsule.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            capsule.topAnchor.constraint(equalTo: topAnchor),
            capsule.heightAnchor.constraint(equalToConstant: Self.barHeight),
            fit,
            scroll.leadingAnchor.constraint(equalTo: capsule.contentView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: capsule.contentView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: capsule.contentView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: capsule.contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: pad),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -pad),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        show(buttons)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.barHeight + Self.gap) }

    private static func button(symbol: String? = nil, title: String? = nil, label: String,
                               action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = symbol.flatMap { UIImage(systemName: $0) }
        config.title = title
        config.baseForegroundColor = .label
        config.cornerStyle = .capsule
        config.titleLineBreakMode = .byTruncatingTail   // one line; the bar scrolls instead
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
        let b = UIButton(configuration: config, primaryAction: UIAction { _ in action() })
        b.accessibilityLabel = label
        b.configurationUpdateHandler = { b in
            b.configuration?.background.backgroundColor = b.isSelected ? .tertiarySystemFill : .clear
        }
        return b
    }

    private func show(_ views: [UIView]) {
        for v in stack.arrangedSubviews { v.removeFromSuperview() }
        for v in views { stack.addArrangedSubview(v) }
        scroll.contentOffset = .zero
    }

    /// The formatting items shown, so they're only rebuilt when they change.
    /// (Suggestions are rebuilt on every keystroke: their actions hold the query.)
    private var shown: [String]? = ["format"]

    /// While typing `@`, the bar offers pages instead of formatting, like the
    /// keyboard's own suggestions. Otherwise it shows formatting, plus a button
    /// to open the link at the caret.
    func update(bold: Bool, italic: Bool, kind: ParagraphKind, open: Suggestion?, suggestions: [Suggestion]) {
        for (b, on) in zip(buttons, [bold, italic, kind == .bullet, kind == .numbered]) { b.isSelected = on }
        let extra = suggestions.isEmpty ? open.map { [$0] } ?? [] : suggestions
        let key = suggestions.isEmpty ? ["format"] + extra.map(\.label) : nil
        if key != nil, key == shown { return }
        shown = key
        let items = extra.map { s in Self.button(title: s.title, label: s.label, action: s.action) }
        show(suggestions.isEmpty ? buttons + items : items)
    }
}

/// The page's text view. Lays out the title above the writing whenever its
/// width changes (rotation, fold), in a readable column of ~36em.
final class PageTextView: PlainPasteTextView {
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        keyboardLayoutGuide.followsUndockedKeyboard = true
    }
    required init?(coder: NSCoder) { fatalError() }

    var titleField: UITextField? {
        didSet { oldValue?.removeFromSuperview(); titleField.map(addSubview) }   // scrolls with the page
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let title = titleField else { return }
        let width = bounds.width
        let column = min(width - 44, 36 * PageEditor.font.pointSize)
        let side = max(22, (width - column) / 2)
        let titleHeight = ceil(title.font?.lineHeight ?? 34) + 8
        title.frame = CGRect(x: side, y: 8, width: max(0, width - 2 * side), height: titleHeight)

        let inset = UIEdgeInsets(top: title.frame.maxY + 14, left: side, bottom: 40, right: side)
        if textContainerInset != inset { textContainerInset = inset }

        // The view runs under the keyboard; keep everything scrollable above it.
        let covered = max(0, bounds.maxY - keyboardLayoutGuide.layoutFrame.minY)
        if contentInset.bottom != covered {
            contentInset.bottom = covered
            verticalScrollIndicatorInsets.bottom = covered
        }
    }
}
