import SwiftUI
import UIKit
import WriterCore

/// Edit mode: the whole page, with real paragraph spacing, lists and a
/// formatting bar above the keyboard. Typing is native UITextView (undo,
/// autocorrect, dictation, selection all behave as iOS users expect).
struct PageEditor: UIViewRepresentable {
    @Environment(Library.self) private var library

    func makeCoordinator() -> Coordinator { Coordinator(library: library) }

    func makeUIView(context: Context) -> PageView {
        let tv = PageTextView(usingTextLayoutManager: true)
        tv.delegate = context.coordinator
        tv.backgroundColor = .systemBackground
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.allowsEditingTextAttributes = true      // ⌘B, ⌘I and the Format menu
        tv.titleField = context.coordinator.titleField
        let fields = UIHostingController(rootView: PageFields { [weak tv] in tv?.fieldsHeight = $0 }.environment(library))
        fields.view.backgroundColor = .clear
        fields.safeAreaRegions = []
        tv.fieldsController = fields
        context.coordinator.textView = tv
        context.coordinator.render(selection: nil)
        context.coordinator.restoreCaret()
        return PageView(textView: tv, bar: context.coordinator.formatBar)
    }

    func updateUIView(_ view: PageView, context: Context) {}

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
            if RichText.unlinkIfEditing(tv, range: range, replacement: text) { return false }
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

        func textViewDidBeginEditing(_ tv: UITextView) {
            (tv.superview as? PageView)?.showBar(true)
            updateFormatBar()   // the @ menu can only appear once writing
        }
        func textViewDidEndEditing(_ tv: UITextView) {
            (tv.superview as? PageView)?.showBar(false)
            closeMentionMenu()
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
                others.append(MentionMenu.Item(title: "Create page “\(title)”", creates: true) { [weak self] in
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
                FormatBar.OpenButton(title: "Open \(page.heading)", page: page.id) { [weak self] in
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
            // A new page starts in its title; otherwise carry on writing.
            let startInTitle = doc.isEmpty && !Screenshots.isActive
            guard !Screenshots.opensMara || Screenshots.showsMentions else { return }   // CI: the page at rest
            DispatchQueue.main.async { [titleField] in
                if startInTitle { titleField.becomeFirstResponder(); return }
                tv.becomeFirstResponder()
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
        let title: String
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
        let key = open.map { "\($0.title) \($0.page)" }
        guard key != shownExtra else { return }
        shownExtra = key
        show(buttons + (open.map { [Self.button(for: $0)] } ?? []))
    }

    private static func button(for open: OpenButton) -> UIButton {
        button(title: open.title, label: open.title, action: open.action)
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

/// The page's text view. Lays out the title above the writing whenever its
/// width changes (rotation, fold), in a readable column of ~36em.
final class PageTextView: PlainPasteTextView {
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        keyboardLayoutGuide.followsUndockedKeyboard = true
        // HIG text fields: a Clear button at the trailing end. SwiftUI has no
        // modifier for it, so the page's fields take UIKit's own.
        UITextField.appearance(whenContainedInInstancesOf: [PageTextView.self]).clearButtonMode = .whileEditing
    }
    required init?(coder: NSCoder) { fatalError() }

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
        let width = bounds.width
        let column = min(width - 44, 36 * PageEditor.font.pointSize)
        let side = max(22, (width - column) / 2)
        let titleHeight = ceil(title.font?.lineHeight ?? 34) + 8
        title.frame = CGRect(x: side, y: 8, width: max(0, width - 2 * side), height: titleHeight)
        var top = title.frame.maxY
        if let fields = fieldsController?.view {
            fields.frame = CGRect(x: side, y: top + 6, width: title.frame.width, height: fieldsHeight)
            top = fields.frame.maxY
        }

        let inset = UIEdgeInsets(top: top + 14, left: side, bottom: 40, right: side)
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
