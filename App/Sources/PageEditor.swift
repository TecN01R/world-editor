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
final class FormatBar: UIView {
    enum Action { case style(InlineStyle), list(ParagraphKind) }

    private static let capsuleHeight: CGFloat = 48, gap: CGFloat = 8
    private let onAction: (Action) -> Void
    private var bold: UIButton!, italic: UIButton!, bullets: UIButton!, numbers: UIButton!

    init(onAction: @escaping (Action) -> Void) {
        self.onAction = onAction
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: Self.capsuleHeight + Self.gap * 2))
        autoresizingMask = .flexibleHeight
        bold = button("bold", "Bold", .style(.bold))
        italic = button("italic", "Italic", .style(.italic))
        bullets = button("list.bullet", "Bulleted List", .list(.bullet))
        numbers = button("list.number", "Numbered List", .list(.numbered))

        let capsule = UIVisualEffectView(effect: UIGlassEffect())
        capsule.layer.cornerRadius = Self.capsuleHeight / 2
        capsule.layer.cornerCurve = .continuous
        capsule.clipsToBounds = true
        let row = UIStackView(arrangedSubviews: [bold, italic, bullets, numbers])
        row.distribution = .fillEqually
        row.alignment = .center
        capsule.contentView.addSubview(row)
        addSubview(capsule)
        for v in [capsule, row] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            capsule.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            capsule.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            capsule.topAnchor.constraint(equalTo: topAnchor, constant: Self.gap),
            capsule.heightAnchor.constraint(equalToConstant: Self.capsuleHeight),
            row.leadingAnchor.constraint(equalTo: capsule.contentView.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: capsule.contentView.trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: capsule.contentView.topAnchor),
            row.bottomAnchor.constraint(equalTo: capsule.contentView.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.capsuleHeight + Self.gap * 2)
    }

    private func button(_ symbol: String, _ title: String, _ action: Action) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(textStyle: .title3))
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        let b = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.onAction(action) })
        b.tintColor = .label
        b.accessibilityLabel = title
        b.showsLargeContentViewer = true          // long-press shows the name at large text sizes
        b.largeContentTitle = title
        b.addInteraction(UILargeContentViewerInteraction())
        // Selected: a filled accent circle, as in the system's own format bars.
        b.configurationUpdateHandler = { b in
            var c = b.configuration
            c?.background.backgroundColor = b.isSelected ? .tintColor : .clear
            c?.baseForegroundColor = b.isSelected ? .white : .label
            b.configuration = c
        }
        return b
    }

    func update(bold: Bool, italic: Bool, kind: ParagraphKind) {
        self.bold.isSelected = bold
        self.italic.isSelected = italic
        bullets.isSelected = kind == .bullet
        numbers.isSelected = kind == .numbered
        for b in [self.bold, self.italic, bullets, numbers] {
            b?.accessibilityTraits = b?.isSelected == true ? [.button, .selected] : .button
        }
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
