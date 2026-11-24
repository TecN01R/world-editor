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

    /// Counts taps on the toolbar's Format button: each one shows iOS's Format panel.
    private let formatRequest: Int

    init(keepsKeyboard: Bool = false, formatRequest: Int = 0, onWriting: @escaping (Bool) -> Void = { _ in },
         onEditing: @escaping (Bool) -> Void = { _ in }, onFocus: @escaping () -> Void) {
        self.keepsKeyboard = keepsKeyboard
        self.formatRequest = formatRequest
        self.onWriting = onWriting
        self.onEditing = onEditing
        self.onFocus = onFocus
    }

    func makeCoordinator() -> Coordinator { Coordinator(library: library, onFocus: onFocus) }

    func makeUIView(context: Context) -> PageView {
        let tv = PageTextView(usingTextLayoutManager: true)
        tv.delegate = context.coordinator
        tv.backgroundColor = .systemBackground
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.textContainer.lineFragmentPadding = 0   // the writing lines up under the title and fields
        tv.allowsEditingTextAttributes = true      // ⌘B, ⌘I, ⌘U and the edit menu's Format
        tv.textFormattingConfiguration = PageEditor.formatting
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
        context.coordinator.formatRequest = formatRequest
        return PageView(textView: tv)
    }

    func updateUIView(_ view: PageView, context: Context) {
        context.coordinator.onFocus = onFocus
        if formatRequest != context.coordinator.formatRequest {   // the Format button, tapped
            context.coordinator.formatRequest = formatRequest
            context.coordinator.showFormatting()
        }
        // Renamed from elsewhere (the companion filing "Her name is Florica", or its Undo):
        // the title shows it, unless the author is typing in it.
        let title = context.coordinator.titleField
        if !title.isFirstResponder, title.text != library.document.title { title.text = library.document.title }
        context.coordinator.showChanges()
    }

    /// What iOS's Format panel offers on a page (the edit menu's, and the bar's button's), all
    /// of which pages keep (Kevin, 2026-11-24): Notes' text styles (Title, Heading, Subheading,
    /// Body: New York, growing with Dynamic Type), the four styles for text and its highlight,
    /// alignment, lists and indent. No fonts, sizes or colours: the writing is always New York,
    /// sized by Dynamic Type, and a fixed colour can vanish in dark mode.
    static let formatting: UITextFormattingViewController.Configuration = {
        let configuration = UITextFormattingViewController.Configuration(groups: [
            .group([.component(.formattingStyles, .automatic)]),
            .group([.component(.fontAttributes, .automatic), .component(.highlight, .automatic)]),
            .group([.component(.textAlignment, .automatic), .component(.listStyles, .automatic),
                    .component(.textIndentation, .automatic)]),
        ])
        configuration.formattingStyles = [(ParagraphRole.title, "Title"), (.heading, "Heading"),
                                          (.subheading, "Subheading"), (.body, "Body")].map { role, title in
            // Its face unscaled: the panel scales it itself (a font scaled twice crashed it).
            .init(styleKey: role.rawValue, title: LocalizedStringResource(stringLiteral: title), attributes: [.font: face(role)])
        }
        return configuration
    }()

    /// Bold New York, scaled with Dynamic Type.
    static var titleFont: UIFont { newYork(34, weight: .bold, scaledAs: .largeTitle) }   // the size of the world's title

    /// New York at 19 pt for the default text size, scaled with Dynamic Type.
    static var font: UIFont { newYork(19, weight: .regular, scaledAs: .body) }

    private static func newYork(_ size: CGFloat, weight: UIFont.Weight, scaledAs style: UIFont.TextStyle) -> UIFont {
        UIFontMetrics(forTextStyle: style).scaledFont(for: serif(size, weight: weight))
    }

    /// New York at `size`, unscaled.
    private static func serif(_ size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        return UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size)
    }

    /// Each text style's face, New York, scaled with Dynamic Type.
    static func font(_ role: ParagraphRole) -> UIFont {
        UIFontMetrics(forTextStyle: textStyle(role)).scaledFont(for: face(role))
    }

    /// Each text style's face at the default text size: the sizes of Notes' Title, Heading,
    /// Subheading and Body, a little larger for a serif.
    static func face(_ role: ParagraphRole) -> UIFont {
        switch role {
        case .body: serif(19, weight: .regular)
        case .title: serif(28, weight: .bold)
        case .heading: serif(23, weight: .bold)
        case .subheading: serif(20, weight: .semibold)
        }
    }

    private static func textStyle(_ role: ParagraphRole) -> UIFont.TextStyle {
        switch role {
        case .body: .body
        case .title: .title1
        case .heading: .title2
        case .subheading: .title3
        }
    }

    /// How a paragraph is set: its text style, list, alignment and indent.
    static func attributes(_ paragraph: Paragraph) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = paragraph.role == .body ? 1.35 : 1.15
        p.paragraphSpacing = paragraph.kind.isList ? 4 : 14
        if let list = RichText.list(for: paragraph.kind) { p.textLists = [list] }
        p.alignment = RichText.alignments.first { $0.alignment == paragraph.alignment }?.text ?? .natural
        p.firstLineHeadIndent = CGFloat(paragraph.indent) * RichText.indentStep
        p.headIndent = p.firstLineHeadIndent
        return [.font: font(paragraph.role), .foregroundColor: ink, .paragraphStyle: p]
    }

    /// The writing's colour: a touch off-white in dark mode (88%; pure white
    /// on black shimmers and reads heavy), the standard label colour in light.
    static let ink = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.88) : .label }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UITextFieldDelegate, UITextFormattingViewController.Delegate {
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
        private var observers: [NSObjectProtocol] = []
        /// The Format button's taps shown so far.
        var formatRequest = 0

        lazy var titleField: UITextField = {
            let f = UITextField()
            f.font = PageEditor.titleFont
            f.adjustsFontForContentSizeCategory = true
            f.textColor = PageEditor.ink   // the writing's colour: it's the user's too
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
            let center = NotificationCenter.default
            // Text size changed in Settings: show the page at the new size.
            observers.append(center.addObserver(forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let tv = self.textView else { return }
                    self.titleField.font = PageEditor.titleFont
                    self.render(selection: tv.selectedRange)
                }
            })
            // The page's writing, title or a field (all inside the text view) taking the
            // keyboard or giving it up.
            let editing: [(Notification.Name, Bool)] = [
                (UITextView.textDidBeginEditingNotification, true), (UITextField.textDidBeginEditingNotification, true),
                (UITextView.textDidEndEditingNotification, false), (UITextField.textDidEndEditingNotification, false),
            ]
            for (name, begins) in editing {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated {
                        guard let self, let tv = self.textView, let view = note.object as? UIView,
                              view.isDescendant(of: tv) else { return }
                        self.onEditing(begins)
                    }
                })
            }
            // Undo and Redo (iOS's for typing and styles, the page's own for lists): the page
            // as the text view now shows it.
            for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated {
                        guard let self, let tv = self.textView, note.object as? UndoManager === tv.undoManager else { return }
                        self.textViewDidChange(tv)
                    }
                })
            }
        }

        deinit {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
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
                let attrs = PageEditor.attributes(p)
                s.append(RichText.attributed(p, attributes: attrs))
                if i < doc.paragraphs.count - 1 { s.append(NSAttributedString(string: "\n", attributes: attrs)) }
            }
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
            var attrs = PageEditor.attributes(p)
            attrs.merge(RichText.attributes(p.style(at: offset), base: PageEditor.font(p.role))) { $1 }
            tv.typingAttributes = attrs
        }

        // MARK: View → model

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if RichText.unlinkIfEditing(tv, range: range, replacement: text) { return false }
            guard text == "\n", range.length == 0 else { return true }
            let (i, offset) = library.document.locate(range.location)
            let p = library.document.paragraphs[i]
            // Return on an empty list item ends the list, as in Notes.
            if p.kind.isList, p.text.isEmpty {
                toggleKind(p.kind, in: range.location..<range.location)
                return false
            }
            // Return at the end of a title or heading: the next line is writing, as in Notes.
            guard p.role != .body, offset == p.length else { return true }
            change("New Line", caret: range.location + 1) { _ = $0.split(at: i, offset: offset) }
            return false
        }

        func textViewDidChange(_ tv: UITextView) {
            // An empty last line has no character to carry its style, list, alignment or indent:
            // the typing attributes say them while the caret is there; otherwise they stay.
            let atEnd = tv.selectedRange.location == tv.textStorage.length
            let trailing = atEnd ? RichText.layout(of: tv.typingAttributes) : library.document.paragraphs.last ?? Paragraph()
            let paragraphs = RichText.paragraphs(from: tv.attributedText, trailing: trailing)
            library.update { $0.setParagraphs(paragraphs) }
            shown = library.document.paragraphs
            updateFormatBar()
        }

        func textViewDidBeginEditing(_ tv: UITextView) {
            onWriting(true)
            updateFormatBar()   // the @ menu can only appear once writing
        }
        func textViewDidEndEditing(_ tv: UITextView) {
            onWriting(false)
            closeMentionMenu()
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            tv.typingAttributes[.link] = nil   // typing beside a link never extends it
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

        /// iOS's own Format panel, from the toolbar's Format button (Kevin, 2026-11-24: "Can I
        /// just get a button for this then?"): iOS offers no way to open the edit menu's, so the
        /// page shows it and makes the changes it asks for, through iOS's own commands where
        /// there are some. A popover at the selection unfolded, a sheet folded.
        func showFormatting() {
            guard let tv = textView else { return }
            let panel = UITextFormattingViewController(configuration: PageEditor.formatting)
            panel.delegate = self
            panel.formattingDescriptor = formattingNow(tv)
            panel.modalPresentationStyle = .popover
            if let popover = panel.popoverPresentationController {
                popover.sourceView = tv
                popover.sourceRect = tv.selectedTextRange.map { tv.firstRect(for: $0) }
                    .flatMap { $0.isNull || $0.isEmpty ? nil : $0 } ?? tv.caretRect(for: tv.selectedTextRange?.start ?? tv.beginningOfDocument)
                popover.adaptiveSheetPresentationController.detents = [.medium()]
            }
            var host = tv.window?.rootViewController
            while let next = host?.presentedViewController { host = next }
            // The keyboard steps aside while it shows, as for the edit menu's (it covered the
            // panel folded); the selection stays, and the writing gets the keyboard back after.
            tv.resignFirstResponder()
            host?.present(panel, animated: true)
        }

        /// What the selection (or, with none, what's typed next) has, for the panel to show.
        private func formattingNow(_ tv: UITextView) -> UITextFormattingViewController.FormattingDescriptor {
            var now: UITextFormattingViewController.FormattingDescriptor = tv.selectedRange.length > 0
                ? .init(string: tv.textStorage, range: tv.selectedRange)
                : .init(attributes: tv.typingAttributes)
            now.formattingStyleKey = paragraph.role.rawValue
            return now
        }

        /// The paragraph the selection starts in.
        private var paragraph: Paragraph { library.document.paragraphs[library.document.locate(selection.lowerBound).index] }

        func textFormattingViewController(_ panel: UITextFormattingViewController,
                                          didChangeValue value: UITextFormattingViewController.ChangeValue) {
            guard let tv = textView else { return }
            // iOS's own Bold, Italic and Underline, as ⌘B, ⌘I, ⌘U: Undo takes them back, and
            // with nothing selected they're for what's typed next.
            switch value {
            case .bold: tv.toggleBoldface(nil)
            case .italic: tv.toggleItalics(nil)
            case .underline: tv.toggleUnderline(nil)
            case .strikethrough(let on): strike(on, in: tv)
            case .textList(let list):
                let kind: ParagraphKind = switch list {
                case nil: .body
                case .decimal?: .numbered
                default: .bullet
                }
                let current = paragraph.kind
                // No list: the current one toggled off.
                if kind != current { toggleKind(kind == .body ? current : kind, in: selection) }
            case .formattingStyle(let key):
                if let role = ParagraphRole(rawValue: key) { change("Text Style") { $0.setRole(role, in: self.selection) } }
            case .textAlignment(let alignment):
                let alignment = RichText.alignments.first { $0.panel == alignment }?.alignment ?? .natural
                change("Alignment") { $0.setAlignment(alignment, in: self.selection) }
            case .increaseIndentation: change("Indent") { $0.indent(by: 1, in: self.selection) }
            case .decreaseIndentation: change("Indent") { $0.indent(by: -1, in: self.selection) }
            case .highlight(let highlight):
                mark(RichText.highlights.first { $0.panel == highlight }?.highlight, in: tv)
            default: break   // not offered (`PageEditor.formatting`)
            }
            if !selection.isEmpty { textViewDidChange(tv) }
            panel.formattingDescriptor = formattingNow(tv)
        }

        /// Back to writing once the panel closes.
        func textFormattingDidFinish(_ panel: UITextFormattingViewController) {
            textView?.becomeFirstResponder()
        }

        /// The edit menu's Format panel, iOS's own, changed the text itself: the page as shown,
        /// then shown as pages set it (its spacing, its indent's steps).
        func textView(_ tv: UITextView, didEndFormattingWith viewController: UITextFormattingViewController) {
            textViewDidChange(tv)
            render(selection: tv.selectedRange)
        }

        /// Highlight (iOS's, in one of its colours; nil: none), on the selection, as one step
        /// Undo takes back, or with none, on what's typed next.
        private func mark(_ highlight: InlineStyle.Highlight?, in tv: UITextView) {
            var style = InlineStyle()
            style.highlight = highlight
            let marks = RichText.attributes(style, base: PageEditor.font)
            let range = tv.selectedRange
            guard range.length > 0 else {
                for key in [NSAttributedString.Key.textHighlightStyle, .textHighlightColorScheme] {
                    tv.typingAttributes[key] = marks[key]
                }
                return
            }
            let before = library.document.paragraphs
            tv.textStorage.removeAttribute(.textHighlightStyle, range: range)
            tv.textStorage.removeAttribute(.textHighlightColorScheme, range: range)
            for key in [NSAttributedString.Key.textHighlightStyle, .textHighlightColorScheme] {
                if let value = marks[key] { tv.textStorage.addAttribute(key, value: value, range: range) }
            }
            textViewDidChange(tv)
            undoably(back: before, named: "Highlight")
        }

        /// Strikethrough (iOS has no command for it): on the selection, as one step Undo takes
        /// back, or with none, on what's typed next.
        private func strike(_ on: Bool, in tv: UITextView) {
            let range = tv.selectedRange
            let value: Int? = on ? NSUnderlineStyle.single.rawValue : nil
            guard range.length > 0 else {
                tv.typingAttributes[.strikethroughStyle] = value
                return
            }
            let before = library.document.paragraphs
            if let value {
                tv.textStorage.addAttribute(.strikethroughStyle, value: value, range: range)
            } else {
                tv.textStorage.removeAttribute(.strikethroughStyle, range: range)
            }
            textViewDidChange(tv)
            undoably(back: before, named: "Strikethrough")
        }

        /// Makes the paragraphs in `range` a `kind` list, or plain when all already are, as one
        /// step Undo takes back.
        private func toggleKind(_ kind: ParagraphKind, in range: Range<Int>) {
            change(kind == .numbered ? "Numbered List" : "Bulleted List") { $0.toggleKind(kind, in: range) }
        }

        /// Changes the page's paragraphs (a list, a text style, alignment, indent, a new line)
        /// and shows them, as one step Undo takes back named `name`; the caret then at `caret`.
        private func change(_ name: String, caret: Int? = nil, _ edit: (inout WriterCore.Document) -> Void) {
            let before = library.document.paragraphs
            library.update(edit)
            render(selection: caret.map { NSRange(location: $0, length: 0) } ?? textView?.selectedRange)
            undoably(back: before, named: name)
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

        /// The `@` menu, as the caret moves.
        private func updateFormatBar() {
            updateMentionMenu(at: library.document.locate(selection.lowerBound))
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

/// The page: its text view. Formatting is iOS's own Format panel, from the toolbar's
/// Format button.
final class PageView: UIView {
    let textView: PageTextView

    init(textView: PageTextView) {
        self.textView = textView
        super.init(frame: .zero)
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// The page's text view. Lays out the title above the writing whenever its
/// width changes (rotation, fold), in a readable column of ~33 em.
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
    }
    required init?(coder: NSCoder) { fatalError() }

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

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let title = titleField else { return }
        let width = bounds.width
        let column = min(width - 44, 33 * PageEditor.font.pointSize)   // at most ~66 characters a line
        let side = max(22, (width - column) / 2)
        // The title, fields and writing share a left edge, 7 px (2⅓ pt) in from
        // `side`, where the pages list's title sits (measured on the Duo), so
        // going into a page the title stays put.
        let lead = side + 7.0 / 3
        let lineWidth = max(0, width - lead - side)
        let titleHeight = ceil(title.font?.lineHeight ?? 34) + 8
        // Offset so the title's letters, not its field, land on that edge and
        // level with the list's title (also measured on the Duo).
        title.frame = CGRect(x: lead - 1.0 / 3, y: 8 - 20.0 / 3, width: lineWidth, height: titleHeight)
        var top = title.frame.maxY
        if let fields = fieldsController?.view {
            fields.frame = CGRect(x: lead, y: top + 6, width: lineWidth, height: fieldsHeight)
            top = fields.frame.maxY
        }

        let inset = UIEdgeInsets(top: top + 14, left: lead, bottom: 40, right: side)
        if textContainerInset != inset { textContainerInset = inset }

        // The page stops at the keyboard, though any part still under it counts: keep
        // everything scrollable above it.
        let covered = max(0, bounds.maxY - keyboardLayoutGuide.layoutFrame.minY)
        if contentInset.bottom != covered {
            contentInset.bottom = covered
            verticalScrollIndicatorInsets.bottom = covered
        }
    }
}
