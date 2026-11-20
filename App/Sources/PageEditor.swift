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

        init(library: Library) { self.library = library }

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
                s.append(RichText.attributed(p.text, runs: p.runs, attributes: attrs))
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
            guard !isRendering else { return }
            let (i, offset) = library.document.locate(tv.selectedRange.location)
            library.cursor = (i, offset)
            updateFormatBar()
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
            let kind = doc.paragraphs[doc.locate(range.lowerBound).index].kind
            formatBar.update(bold: active(.bold), italic: active(.italic), kind: kind)
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

/// Bold, italic, bulleted and numbered list, above the keyboard where Notes
/// keeps its bar, matching it: one Liquid Glass capsule across the writing
/// width (clear of the Duo's side column), buttons spread evenly, a small gap
/// above the keyboard. Buttons show the state of the selection.
/// Bold, italic, bulleted and numbered list above the keyboard: the stock
/// system toolbar, laid out by iOS, with a small gap above the keyboard as in
/// Notes. Buttons show the state of the selection. (When more tools arrive,
/// this may become a scrolling bar like Notes'.)
final class FormatBar: UIView {
    enum Action { case style(InlineStyle), list(ParagraphKind) }

    private static let gap: CGFloat = 8
    private let toolbar = UIToolbar()
    private var buttons: [UIBarButtonItem] = []

    init(onAction: @escaping (Action) -> Void) {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 44 + Self.gap))
        autoresizingMask = .flexibleHeight
        func item(_ symbol: String, _ title: String, _ action: Action) -> UIBarButtonItem {
            let item = UIBarButtonItem(title: title, image: UIImage(systemName: symbol),
                                       primaryAction: UIAction(title: title) { _ in onAction(action) })
            item.accessibilityLabel = title
            return item
        }
        buttons = [item("bold", "Bold", .style(.bold)), item("italic", "Italic", .style(.italic)),
                   item("list.bullet", "Bulleted List", .list(.bullet)),
                   item("list.number", "Numbered List", .list(.numbered))]
        toolbar.items = buttons
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.gap),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 44 + Self.gap) }

    func update(bold: Bool, italic: Bool, kind: ParagraphKind) {
        for (item, on) in zip(buttons, [bold, italic, kind == .bullet, kind == .numbered]) { item.isSelected = on }
    }
}

/// The page's text view. Lays out the title above the writing whenever its
/// width changes (rotation, fold), in a readable column of ~36em.
final class PageTextView: UITextView {
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
        title.frame = CGRect(x: side, y: 28, width: max(0, width - 2 * side), height: titleHeight)
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
