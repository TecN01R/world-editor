import SwiftUI
import UIKit
import WriterCore

/// Edit mode: the whole page, with real paragraph spacing, lists and a
/// formatting bar above the keyboard. Typing is native UITextView (undo,
/// autocorrect, dictation, selection all behave as iOS users expect).
struct PageEditor: UIViewRepresentable {
    @Environment(Library.self) private var library
    /// Steps into Focus mode with ⇧⌘F (its button is in the toolbar).
    private let onFocus: () -> Void
    /// The keyboard was up when the page appeared (coming back from Focus):
    /// keep writing, keyboard up, instead of waiting for a tap.
    private let keepsKeyboard: Bool
    /// The writing (not the title or a field) has the keyboard, or no longer does.
    private let onWriting: (Bool) -> Void
    /// The page (its writing, title or a field) has the keyboard, or no longer does: not
    /// a keyboard elsewhere (search in the pages list, an alert, the companion).
    private let onEditing: (Bool) -> Void

    init(keepsKeyboard: Bool = false, onWriting: @escaping (Bool) -> Void = { _ in },
         onEditing: @escaping (Bool) -> Void = { _ in }, onFocus: @escaping () -> Void) {
        self.keepsKeyboard = keepsKeyboard
        self.onWriting = onWriting
        self.onEditing = onEditing
        self.onFocus = onFocus
    }

    func makeCoordinator() -> Coordinator { Coordinator(library: library, onFocus: onFocus) }

    func makeUIView(context: Context) -> PageView {
        let tv = PageTextView(usingTextLayoutManager: true)
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear   // the page's screen shows the look's background (`lookBackground`)
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.textContainer.lineFragmentPadding = 0   // the writing lines up under the title and fields
        tv.linkTextAttributes = Look.link
        tv.allowsEditingTextAttributes = true      // ⌘B, ⌘I and the Format menu
        tv.textFormattingConfiguration = RichText.formatting
        tv.titleField = context.coordinator.titleField
        tv.onFocus = { [weak coordinator = context.coordinator] in coordinator?.onFocus() }
        let fields = UIHostingController(rootView: PageFields { [weak tv] in tv?.fieldsHeight = $0 }.environment(library))
        fields.view.backgroundColor = .clear
        fields.safeAreaRegions = []
        tv.fieldsController = fields
        context.coordinator.textView = tv
        context.coordinator.keepsKeyboard = keepsKeyboard
        context.coordinator.onWriting = onWriting
        context.coordinator.onEditing = onEditing
        context.coordinator.render(selection: nil)
        context.coordinator.restoreCaret()
        return PageView(textView: tv, bar: context.coordinator.formatBar)
    }

    func updateUIView(_ view: PageView, context: Context) {
        context.coordinator.onFocus = onFocus
        // Renamed from elsewhere (the companion filing "Her name is Florica", or its Undo):
        // the title shows it, unless the author is typing in it.
        let title = context.coordinator.titleField
        if !title.isFirstResponder, title.text != library.document.title { title.text = library.document.title }
        context.coordinator.showChanges()
    }

    /// Bold New York, scaled with Dynamic Type.
    static var titleFont: UIFont { newYork(34, weight: .bold, scaledAs: .largeTitle) }   // a large title

    /// New York at 19 pt for the default text size, scaled with Dynamic Type.
    static var font: UIFont { newYork(19, weight: .regular, scaledAs: .body) }

    private static func newYork(_ size: CGFloat, weight: UIFont.Weight, scaledAs style: UIFont.TextStyle) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let serif = UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: serif)
    }

    /// A paragraph as the page shows it, read or edited: line height ×1.35, 14 pt between
    /// paragraphs, light hyphenation (a long word breaks only where the ragged edge would
    /// otherwise gape), ragged right, in the author's ink.
    static func attributes(_ kind: ParagraphKind) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.35
        p.paragraphSpacing = kind.isList ? 4 : 14
        p.hyphenationFactor = 0.4
        if let list = RichText.list(for: kind) { p.textLists = [list] }
        return [.font: font, .foregroundColor: Look.ink, .paragraphStyle: p]
    }

    /// `paragraphs` as the page sets them, read or edited: each made by `paragraph` from it and
    /// its kind's `attributes`, with a line break in those attributes between one and the next.
    static func text(of paragraphs: [Paragraph],
                     _ paragraph: (Paragraph, [NSAttributedString.Key: Any]) -> NSAttributedString) -> NSAttributedString {
        let s = NSMutableAttributedString()
        for (i, p) in paragraphs.enumerated() {
            let attrs = attributes(p.kind)
            s.append(paragraph(p, attrs))
            if i < paragraphs.count - 1 { s.append(NSAttributedString(string: "\n", attributes: attrs)) }
        }
        return s
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UITextFieldDelegate {
        let library: Library
        weak var textView: UITextView?
        /// Replacing the text moves the selection; that isn't the user moving the caret.
        private var isRendering = false
        /// The paragraphs the text view holds, as last shown or typed: the page differing
        /// from them was changed by something else.
        private var shown: [Paragraph] = []
        var onFocus: () -> Void
        var keepsKeyboard = false
        var onWriting: (Bool) -> Void = { _ in }
        var onEditing: (Bool) -> Void = { _ in }
        lazy var formatBar = FormatBar(onAction: { [weak self] action in self?.perform(action) })

        lazy var titleField: UITextField = {
            let f = UITextField()
            f.font = PageEditor.titleFont
            f.adjustsFontForContentSizeCategory = true
            f.textColor = Look.ink   // the writing's colour: it's the user's too
            f.placeholder = "Title"
            f.clearButtonMode = .never   // the fields' clear buttons are for short values, not the title
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

        init(library: Library, onFocus: @escaping () -> Void) {
            self.library = library
            self.onFocus = onFocus
            super.init()
            // UIKit posts these on the main thread; selector observers go away with the coordinator.
            let center = NotificationCenter.default
            // Text size changed in Settings: show the page at the new size.
            center.addObserver(self, selector: #selector(textSizeChanged), name: UIContentSizeCategory.didChangeNotification, object: nil)
            // The page's writing, title or a field (all inside the text view) taking the
            // keyboard or giving it up.
            for name in [UITextView.textDidBeginEditingNotification, UITextField.textDidBeginEditingNotification] {
                center.addObserver(self, selector: #selector(beganEditing), name: name, object: nil)
            }
            for name in [UITextView.textDidEndEditingNotification, UITextField.textDidEndEditingNotification] {
                center.addObserver(self, selector: #selector(endedEditing), name: name, object: nil)
            }
            // Undo and Redo (iOS's for typing and styles, the page's own for lists): the page
            // as the text view now shows it.
            for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
                center.addObserver(self, selector: #selector(undid), name: name, object: nil)
            }
        }

        @objc private func textSizeChanged() {
            guard let tv = textView else { return }
            titleField.font = PageEditor.titleFont
            render(selection: tv.selectedRange)
        }

        @objc private func beganEditing(_ note: Notification) { editing(note, begins: true) }
        @objc private func endedEditing(_ note: Notification) { editing(note, begins: false) }

        private func editing(_ note: Notification, begins: Bool) {
            guard let tv = textView, let view = note.object as? UIView, view.isDescendant(of: tv) else { return }
            onEditing(begins)
        }

        @objc private func undid(_ note: Notification) {
            guard let tv = textView, note.object as? UndoManager === tv.undoManager else { return }
            textViewDidChange(tv)
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
            let s = PageEditor.text(of: doc.paragraphs) { RichText.attributed($0, attributes: $1) }
            tv.attributedText = s
            shown = doc.paragraphs
            if let selection {   // within the text, which may now be shorter
                let start = min(selection.location, s.length)
                tv.selectedRange = NSRange(location: start, length: min(selection.length, s.length - start))
            }
            updateTypingAttributes()
            updateFormatBar()
        }

        /// The writing changed underneath (filing a description into this page, its Undo, a
        /// linked page renamed): shown as it is now, or the next keystroke would write the old
        /// text back over it. Not mid-word (marked text) or while Writing Tools works on it.
        func showChanges() {
            guard let tv = textView, tv.markedTextRange == nil, !tv.isWritingToolsActive,
                  library.document.paragraphs != shown else { return }
            render(selection: tv.selectedRange)
            tv.undoManager?.removeAllActions()   // its steps were for the old text
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
            if RichText.unlinkIfEditing(tv, range: range, replacement: text) { return false }
            // Return on an empty list item ends the list, as in Notes.
            guard text == "\n", range.length == 0 else { return true }
            let p = library.document.paragraphs[library.document.locate(range.location).index]
            guard p.kind.isList, p.text.isEmpty else { return true }
            toggleKind(p.kind, in: range.location..<range.location)
            return false
        }

        func textViewDidChange(_ tv: UITextView) {
            // An empty last line has no character to carry its list: the typing attributes
            // say it while the caret is there; otherwise it stays as it was.
            let atEnd = tv.selectedRange.location == tv.textStorage.length
            let trailing = atEnd ? RichText.kind(of: tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle)
                                 : library.document.paragraphs.last?.kind ?? .body
            let paragraphs = RichText.paragraphs(from: tv.attributedText, trailingKind: trailing)
            library.update { $0.setParagraphs(paragraphs) }
            shown = library.document.paragraphs
            updateFormatBar()
        }

        func textViewDidBeginEditing(_ tv: UITextView) {
            (tv.superview as? PageView)?.showBar(true)
            onWriting(true)
            updateFormatBar()   // the @ menu can only appear once writing
        }
        func textViewDidEndEditing(_ tv: UITextView) {
            (tv.superview as? PageView)?.showBar(false)
            onWriting(false)
            closeMentionMenu()
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            RichText.typeAsTheAuthor(tv)
            guard !isRendering else { return }
            let (i, offset) = library.document.locate(tv.selectedRange.location)
            library.cursor = (i, offset)
            updateFormatBar()
        }

        /// Holding a link: Open its page, as tapping it does when not writing.
        func textView(_ tv: UITextView, menuConfigurationFor textItem: UITextItem,
                      defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
            guard case .link(let url) = textItem.content, let id = RichText.page(url) else { return .init(menu: defaultMenu) }
            guard let page = library.pages.first(where: { $0.id == id }) else { return nil }
            let open = UIAction(title: "Open “\(page.heading)”", image: UIImage(systemName: "arrow.up.right")) { [weak self] _ in
                self?.open(id)
            }
            return .init(menu: UIMenu(children: [open]))
        }

        /// Holding or selecting text: iOS's edit menu, its Format what pages keep: Bold and
        /// Italic, and the lists, ticked as the format bar shows them.
        func textView(_ tv: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            let selected = range.location..<(range.location + range.length)
            let kind = library.document.paragraphs[library.document.locate(range.location).index].kind
            let lists = [(ParagraphKind.bullet, "Bulleted List", "list.bullet"), (.numbered, "Numbered List", "list.number")]
                .map { list, title, symbol in
                    UIAction(title: title, image: UIImage(systemName: symbol), state: kind == list ? .on : .off) { [weak self] _ in
                        self?.toggleKind(list, in: selected)
                        self?.updateFormatBar()
                    }
                }
            return RichText.editMenu(suggestedActions, more: lists)
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

        /// Turns the typed `@query` into a link to `page`, then a plain space.
        /// Typed into the text view like any text, so Undo takes it back.
        private func link(to page: UUID, title: String, replacing range: Range<Int>, in index: Int) {
            guard let tv = textView else { return }
            let start = library.document.paragraphStarts[index] + range.lowerBound
            tv.selectedRange = NSRange(location: start, length: range.count)
            tv.insertText(title + " ")
            tv.textStorage.addAttribute(.link, value: RichText.url(page),
                                        range: NSRange(location: start, length: title.utf16.count))
            textViewDidChange(tv)   // save the link with the text
            UISelectionFeedbackGenerator().selectionChanged()
        }

        /// The `@` menu: shown while the caret ends an `@query`, updated as it grows.
        private var mentionMenu: MentionMenu?

        private func updateMentionMenu(at caret: (index: Int, offset: Int)) {
            let sections = mentionSections(at: caret)
            guard let tv = textView, tv.window != nil, tv.isFirstResponder, !sections.isEmpty,
                  let end = tv.selectedTextRange?.end else { return closeMentionMenu() }
            let rect = tv.caretRect(for: end)
            if let menu = mentionMenu, menu.presentingViewController != nil {
                menu.sections = sections
                menu.popoverPresentationController?.sourceRect = rect
                return
            }
            var host = tv.window?.rootViewController
            while let next = host?.presentedViewController { host = next }
            let menu = MentionMenu()
            menu.sections = sections
            menu.popoverPresentationController?.sourceView = tv
            menu.popoverPresentationController?.sourceRect = rect
            menu.popoverPresentationController?.passthroughViews = [tv]   // keep typing; taps move the caret
            host?.present(menu, animated: true)
            mentionMenu = menu
        }

        private func closeMentionMenu() {
            mentionMenu?.dismiss(animated: true)
            mentionMenu = nil
        }

        /// This page, then the others matching the `@query` at the caret (all of
        /// them for a bare `@`), then a new page by that name if none has it.
        private func mentionSections(at caret: (index: Int, offset: Int)) -> [[MentionMenu.Item]] {
            let doc = library.document, p = doc.paragraphs[caret.index]
            guard selection.isEmpty, p.link(at: caret.offset) == nil,
                  let mention = Mention.query(in: p.text, caret: caret.offset) else { return [] }
            func item(_ page: WriterCore.Document) -> MentionMenu.Item {
                MentionMenu.Item(title: page.heading, date: page.modified) { [weak self] in
                    self?.link(to: page.id, title: page.heading, replacing: mention.range, in: caret.index)
                }
            }
            var others = library.pages
                .filter { $0.id != doc.id && !$0.heading.isEmpty && Mention.matches(mention.query, $0.heading) }
                .map(item)
            let title = mention.query.trimmingCharacters(in: .whitespaces)
            if !title.isEmpty, !library.pages.contains(where: { $0.heading.localizedCaseInsensitiveCompare(title) == .orderedSame }) {
                others.append(MentionMenu.Item(title: "Create page “\(title)”", creates: true, creating: title) { [weak self] in
                    guard let self else { return }
                    link(to: library.addPage(titled: title), title: title, replacing: mention.range, in: caret.index)
                })
            }
            // This page by its title: an untitled page's heading is its own first line, @query and all.
            let current = !doc.heading.isEmpty && (mention.query.isEmpty || Search.range(of: mention.query, in: doc.title) != nil)
                ? [item(doc)] : []
            return [current, others].filter { !$0.isEmpty }
        }

        // MARK: Formatting

        private func perform(_ action: FormatBar.Action) {
            guard let tv = textView else { return }
            switch action {
            case .style(let style):
                // iOS's own Bold and Italic, as ⌘B, ⌘I and the edit menu's Format: Undo takes
                // them back, and with nothing selected they're for what's typed next.
                if style == .bold { tv.toggleBoldface(nil) } else { tv.toggleItalics(nil) }
                if !selection.isEmpty { textViewDidChange(tv) }
            case .list(let kind):
                toggleKind(kind, in: selection)
            }
            updateFormatBar()
            UISelectionFeedbackGenerator().selectionChanged()
        }

        /// Makes the paragraphs in `range` a `kind` list, or plain when all already are, as one
        /// step Undo takes back.
        private func toggleKind(_ kind: ParagraphKind, in range: Range<Int>) {
            let before = library.document.paragraphs
            library.update { $0.toggleKind(kind, in: range) }
            render(selection: textView?.selectedRange)
            undoably(back: before, named: kind == .numbered ? "Numbered List" : "Bulleted List")
        }

        /// Registers putting the page's paragraphs back as they were, and redoing it the same way.
        private func undoably(back paragraphs: [Paragraph], named name: String) {
            guard let undo = textView?.undoManager else { return }
            undo.registerUndo(withTarget: self) { coordinator in
                let now = coordinator.library.document.paragraphs
                coordinator.library.update { $0.setParagraphs(paragraphs) }
                coordinator.render(selection: coordinator.textView?.selectedRange)
                coordinator.undoably(back: now, named: name)
            }
            undo.setActionName(name)
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
                FormatBar.OpenButton(name: page.heading, page: page.id) { [weak self] in
                    self?.open(page.id)
                }
            }
            formatBar.update(bold: active(.bold), italic: active(.italic), kind: p.kind, open: open)
            updateMentionMenu(at: caret)
        }

        func restoreCaret() {
            guard let tv = textView else { return }
            let doc = library.document
            let p = min(library.cursor.paragraph, doc.paragraphs.count - 1)
            let loc = doc.paragraphStarts[p] + min(library.cursor.offset, doc.paragraphs[p].length)
            tv.selectedRange = NSRange(location: loc, length: 0)
            updateTypingAttributes()
            // A new page starts in its title, keyboard up, as a new note does in
            // Notes; any other page opens where you left off, keyboard down
            // until you tap (Kevin, 2026-11-23), unless it was already up (back
            // from Focus, which hands it over).
            let startInTitle = doc.isEmpty && !Screenshots.isActive
            guard !Screenshots.opensMara || Screenshots.showsMentions else { return }   // CI: the page at rest
            DispatchQueue.main.async { [titleField, keepsKeyboard] in
                if startInTitle { titleField.becomeFirstResponder(); return }
                if keepsKeyboard { tv.becomeFirstResponder() }
                tv.scrollRangeToVisible(tv.selectedRange)
            }
        }
    }
}

/// Bold, italic, bulleted and numbered list above the keyboard, plus Open
/// while the caret is in a link. One glass capsule with a small gap below it, in
/// the page's column, scrolling sideways when its buttons don't fit, as in Notes.
/// Customised at Kevin's request: the stock toolbar folds extra items into
/// "•••" and spans the whole keyboard.
final class FormatBar: UIView {
    enum Action { case style(InlineStyle), list(ParagraphKind) }

    /// Open, for the link at the caret.
    struct OpenButton {
        /// The page's name.
        let name: String
        /// The page it opens, so a button is never reused for another page.
        let page: UUID
        let action: () -> Void
    }

    private static let gap: CGFloat = 8
    /// 44 pt at the default text size, growing with Dynamic Type.
    private var barHeight: CGFloat { UIFontMetrics.default.scaledValue(for: 44, compatibleWith: traitCollection) }
    private lazy var heightConstraint = capsule.heightAnchor.constraint(equalToConstant: barHeight)
    private let capsule = UIVisualEffectView(effect: UIGlassEffect())
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var buttons: [UIButton] = []

    init(onAction: @escaping (Action) -> Void) {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 44 + Self.gap))
        buttons = [Self.button(symbol: "bold", label: "Bold") { onAction(.style(.bold)) },
                   Self.button(symbol: "italic", label: "Italic") { onAction(.style(.italic)) },
                   Self.button(symbol: "list.bullet", label: "Bulleted List") { onAction(.list(.bullet)) },
                   Self.button(symbol: "list.number", label: "Numbered List") { onAction(.list(.numbered)) }]

        capsule.cornerConfiguration = .capsule()
        capsule.clipsToBounds = true
        scroll.showsHorizontalScrollIndicator = false
        stack.axis = .horizontal
        for v in [capsule, scroll, stack] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false }
        scroll.addSubview(stack)
        capsule.contentView.addSubview(scroll)
        addSubview(capsule)

        let pad: CGFloat = 8
        let fit = capsule.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: 2 * pad)
        fit.priority = .defaultHigh   // as wide as its buttons, until the column's width runs out
        NSLayoutConstraint.activate([
            capsule.centerXAnchor.constraint(equalTo: centerXAnchor),
            capsule.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            capsule.topAnchor.constraint(equalTo: topAnchor),
            heightConstraint,
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
        tintAdjustmentMode = .normal   // stays bright while the @ menu is up, as in Notes
        addInteraction(UILargeContentViewerInteraction())   // press and hold at large text sizes
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (bar: FormatBar, _: UITraitCollection) in
            bar.heightConstraint.constant = bar.barHeight
            bar.invalidateIntrinsicContentSize()
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: barHeight + Self.gap) }

    /// Only the capsule takes touches; taps beside or below it reach the page.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        capsule.frame.contains(point)
    }

    private static func button(symbol: String? = nil, title: String? = nil, label: String,
                               action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = symbol.flatMap { UIImage(systemName: $0) }
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .title3)
        config.title = title
        config.baseForegroundColor = .label
        config.cornerStyle = .capsule
        config.titleLineBreakMode = .byTruncatingTail   // one line; the bar scrolls instead
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
        let b = UIButton(configuration: config, primaryAction: UIAction { _ in action() })
        b.accessibilityLabel = label
        b.showsLargeContentViewer = true
        b.largeContentTitle = label
        b.largeContentImage = config.image
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true   // even slots, as in Notes
        b.setContentCompressionResistancePriority(.required, for: .horizontal)   // scroll, never squeeze
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

    /// The extra button beside formatting, so the bar's only rebuilt when it changes.
    private var shownExtra: String?

    /// Formatting, plus a button to open the link at the caret.
    func update(bold: Bool, italic: Bool, kind: ParagraphKind, open: OpenButton?) {
        for (b, on) in zip(buttons, [bold, italic, kind == .bullet, kind == .numbered]) { b.isSelected = on }
        let key = open.map { "\($0.name) \($0.page)" }
        guard key != shownExtra else { return }
        shownExtra = key
        show(buttons + (open.map { [Self.button(for: $0)] } ?? []))
    }

    private static func button(for open: OpenButton) -> UIButton {
        let label = "Open \(open.name)"
        let b = button(title: label, label: label, action: open.action)
        // The page's name is the author's: New York; "Open" is the app's.
        var title = AttributedString("Open ")
        title.uiKit.font = .preferredFont(forTextStyle: .body)
        var name = AttributedString(open.name)
        name.uiKit.font = .authored(.body)
        b.configuration?.attributedTitle = title + name
        return b
    }
}

/// The page: its text view, with the format bar floating just above the
/// keyboard while writing. The bar is part of the page, not the keyboard's
/// accessory view: an accessory counts as keyboard, which shortens the Duo's
/// side column and pushes toolbar items into "•••" (Notes does the same).
final class PageView: UIView {
    let textView: PageTextView
    private let bar: FormatBar

    init(textView: PageTextView, bar: FormatBar) {
        self.textView = textView
        self.bar = bar
        super.init(frame: .zero)
        keyboardLayoutGuide.followsUndockedKeyboard = true
        for v in [textView, bar] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
        ])
        showBar(textView.isFirstResponder)
        // Tells the text view the bar floats over its bottom edge, so iOS
        // softens the writing under it, as under a stock toolbar (scroll edge
        // effect). "Automatic" would resolve to none without a stock toolbar.
        let edge = UIScrollEdgeElementContainerInteraction()
        edge.scrollView = textView
        edge.edge = .bottom
        bar.addInteraction(edge)
        textView.bottomEdgeEffect.style = .soft
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = bar.isHidden ? 0 : bar.intrinsicContentSize.height   // follows Dynamic Type
        if textView.barHeight != height { textView.barHeight = height }
    }

    /// The bar shows only while writing, like the keyboard it sits on.
    func showBar(_ shown: Bool) {
        bar.isHidden = !shown
        textView.barHeight = shown ? bar.intrinsicContentSize.height : 0
    }
}

/// Where a page's parts sit, read (`EntryView`) or edited (`PageTextView`), so going between the
/// two nothing moves (docs/design.md: "Read and Edit are the same page").
enum PageLayout {
    /// From the top of the page to the title's line.
    static let titleTop: CGFloat = 6
    /// From the title's line to the kind under it.
    static let kindGap: CGFloat = 14
    /// From what's above the writing to its first line.
    static let writingGap: CGFloat = 14
    /// Below the writing's last line.
    static let bottom: CGFloat = 40
}

/// The page's text view. Lays out the title above the writing whenever its
/// width changes (rotation, fold), in the reading column (`Look.column`).
final class PageTextView: PlainPasteTextView {
    /// HIG text fields: a Clear button at the trailing end. SwiftUI has no modifier for it,
    /// so the page's fields take UIKit's own, set once for every page.
    private static let clearButtons: Void = {
        UITextField.appearance(whenContainedInInstancesOf: [PageTextView.self]).clearButtonMode = .whileEditing
    }()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        keyboardLayoutGuide.followsUndockedKeyboard = true
        _ = Self.clearButtons
        // Leaving the app, iOS lays the page out for the app switcher's snapshots, at full
        // width as if the companion were closed, and coming back it kept those margins beside
        // the companion (Kevin, 2026-11-24): back in front, it's laid out at its real width.
        NotificationCenter.default.addObserver(self, selector: #selector(layOutAgain),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func layOutAgain() { setNeedsLayout() }

    /// ⇧⌘F steps into Focus mode while writing (listed when ⌘ is held).
    var onFocus: (() -> Void)?
    override var keyCommands: [UIKeyCommand]? {
        let focus = UIKeyCommand(title: "Focus Mode", action: #selector(enterFocus), input: "f", modifierFlags: [.command, .shift])
        return (super.keyCommands ?? []) + [focus]
    }
    @objc private func enterFocus() { onFocus?() }

    var titleField: UITextField? {
        didSet { oldValue?.removeFromSuperview(); titleField.map(addSubview) }   // scrolls with the page
    }

    /// The page's type and fields (SwiftUI), under the title; scrolls with the page.
    var fieldsController: UIViewController? {
        didSet { oldValue?.view.removeFromSuperview(); fieldsController.map { addSubview($0.view) } }
    }

    /// The fields join the screen's view controller, so their menus and
    /// date picker can present.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let fields = fieldsController else { return }
        if window == nil {
            fields.willMove(toParent: nil)
            fields.removeFromParent()
            return
        }
        var responder = next
        while let r = responder, !(r is UIViewController) { responder = r.next }
        guard fields.parent == nil, let parent = responder as? UIViewController else { return }
        parent.addChild(fields)
        fields.didMove(toParent: parent)
    }
    var fieldsHeight: CGFloat = 0 { didSet { if fieldsHeight != oldValue { setNeedsLayout() } } }


    /// The format bar's height while it floats over the bottom of the page.
    var barHeight: CGFloat = 0 { didSet { setNeedsLayout() } }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let title = titleField else { return }
        // The title, fields and writing share the reading column's left edge.
        let column = Look.column(bounds.width)
        let side = (bounds.width - column) / 2
        // The field centres the title's line in 8 pt more than its height.
        let titleHeight = ceil(title.font?.lineHeight ?? 34) + 8
        title.frame = CGRect(x: side, y: PageLayout.titleTop - 4, width: column, height: titleHeight)
        var top = title.frame.maxY - 4   // where the title's line ends
        if let fields = fieldsController?.view {
            // The kind's line lands `kindGap` under the title; its menu has 4 pt above it.
            fields.frame = CGRect(x: side, y: top + PageLayout.kindGap - 4, width: column, height: fieldsHeight)
            top = fields.frame.maxY
        }

        let inset = UIEdgeInsets(top: top + PageLayout.writingGap, left: side, bottom: PageLayout.bottom, right: side)
        if textContainerInset != inset { textContainerInset = inset }

        // The format bar floats over the bottom of the page (which stops at the
        // keyboard, though any part still under it counts); keep everything
        // scrollable above them.
        let covered = max(0, bounds.maxY - keyboardLayoutGuide.layoutFrame.minY) + barHeight
        if contentInset.bottom != covered {
            contentInset.bottom = covered
            verticalScrollIndicatorInsets.bottom = covered
        }
    }
}
