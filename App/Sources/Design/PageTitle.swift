import SwiftUI
import UIKit

/// A page's title (docs/design.md, `words.title`), wrapping onto as many lines as it needs: one
/// view for the page read and edited, so it sits and breaks its lines the same in both, and
/// nothing moves when Edit turns typing on. A stock text view that doesn't scroll. Edited, it
/// stays one line of words however it wraps: Return goes on to the writing, and the line breaks
/// in a paste become spaces.
final class PageTitleView: UITextView, UITextViewDelegate {
    /// The author changed the title.
    var onChange: (String) -> Void = { _ in }
    /// Return: on to the writing.
    var onReturn: () -> Void = {}

    /// "Title", while there's none: a text view has no placeholder of its own.
    private let placeholder = UILabel()
    /// The title's attributes at the current text size (`Role.title`).
    private var attributes: [NSAttributedString.Key: Any] = [:]
    /// One line of it.
    private var lineHeight: CGFloat = 0

    init(editable: Bool) {
        super.init(frame: .zero, textContainer: nil)
        isEditable = editable
        isSelectable = editable
        isUserInteractionEnabled = editable   // read, it's text on the page: touches go to the page
        isScrollEnabled = false
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0   // on the column's edge, as the writing
        returnKeyType = .next
        autocapitalizationType = .words
        writingToolsBehavior = .limited   // as the one-line field it took over from had
        if editable { accessibilityLabel = "Title" }
        delegate = self
        placeholder.isAccessibilityElement = false
        addSubview(placeholder)
        restyle()
        // A new text size, Bold Text or screen sets it again.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitLegibilityWeight.self,
                                 UITraitDisplayScale.self]) { (title: PageTitleView, _: UITraitCollection) in
            title.restyle()
        }
        guard editable else { return }
        // Undo and Redo change the title too. UIKit posts these on the main thread.
        for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(undid), name: name, object: nil)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Read, it heads the page.
    override var accessibilityTraits: UIAccessibilityTraits {
        get { isEditable ? super.accessibilityTraits : [.header, .staticText] }
        set { super.accessibilityTraits = newValue }
    }

    /// Shows `title`: the page's as it opens, or as renamed from elsewhere.
    func show(_ title: String) {
        guard title != text else { return }
        attributedText = NSAttributedString(string: title, attributes: attributes)
        undoManager?.removeAllActions()   // its steps were for the old title
        contentChanged()
    }

    /// How tall the title is in a column `width` wide: its lines, or one while it's empty.
    func height(in width: CGFloat) -> CGFloat {
        guard width > 0, !text.isEmpty else { return lineHeight }
        return ceil(sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        #if DEBUG
        SceneMetrics.report(self, as: .title)   // measured in a scene (Scenes/)
        #endif
        placeholder.frame = CGRect(x: 0, y: 0, width: bounds.width, height: lineHeight)   // where its first line goes
    }

    /// Sets the title in its role at the text size it now has, in place: the same words, so its
    /// Undo and caret stay.
    private func restyle() {
        let displayScale = traitCollection.displayScale
        attributes = Role.title.attributes(displayScale: displayScale)
        lineHeight = Role.title.lineHeight(displayScale: displayScale) ?? 0
        // What an empty title's caret takes.
        font = Role.title.font
        textColor = Role.title.color
        let selection = selectedRange
        textStorage.setAttributes(attributes, range: NSRange(location: 0, length: textStorage.length))
        selectedRange = selection
        typingAttributes = attributes
        placeholder.attributedText = NSAttributedString(string: "Title",
                                                        attributes: attributes.merging([.foregroundColor: Ink.faint]) { $1 })
        contentChanged()
    }

    /// The words or their size changed: "Title" shows only while there are none, and whoever
    /// lays the title out measures it again.
    private func contentChanged() {
        placeholder.isHidden = !isEditable || !text.isEmpty
        invalidateIntrinsicContentSize()   // SwiftUI, where the page is read
        superview?.setNeedsLayout()        // the page's text view, where it's edited
    }

    @objc private func undid(_ note: Notification) {
        guard note.object as? UndoManager === undoManager else { return }
        textViewDidChange(self)
    }

    // MARK: UITextViewDelegate

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard text.contains(where: \.isNewline) else { return true }
        if text.allSatisfy(\.isNewline) {
            onReturn()
        } else {
            // A paste of several lines: one line, typed like any text (which comes back here
            // without its line breaks).
            selectedRange = range
            insertText(Self.oneLine(text))
        }
        return false
    }

    func textViewDidChange(_ textView: UITextView) {
        contentChanged()
        onChange(Self.oneLine(text))   // whatever put a line break in (a drop, dictation), the title has none
    }

    /// `text` with a space where each of its line breaks was.
    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    /// What's typed next is the title's too, an empty title's first letter included (taking the
    /// keyboard, an empty text view goes back to its plain font).
    func textViewDidBeginEditing(_ textView: UITextView) {
        typingAttributes = attributes
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        typingAttributes = attributes
    }
}

/// A page's title where the page is read: `PageTitleView` with typing off, as tall as its lines.
struct PageTitle: UIViewRepresentable {
    let title: String

    func makeUIView(context: Context) -> PageTitleView {
        let view = PageTitleView(editable: false)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)   // as wide as its column: it wraps
        return view
    }

    func updateUIView(_ view: PageTitleView, context: Context) {
        view.show(title)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: PageTitleView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        return CGSize(width: width, height: view.height(in: width))
    }
}
