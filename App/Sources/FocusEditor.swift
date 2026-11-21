import SwiftUI
import UIKit
import CoreText
import WriterCore
import FocusLayout

/// Focus mode: one paragraph per page, set as large as the page allows and
/// centred on it. The page ends at `keyboardLayoutGuide`, the system's exact
/// keyboard position, so there is nothing to estimate and nothing scrolls.
///
/// Everything but the writing hides (the paragraph dots dim) while you write:
/// tapping outside the text brings the controls back (`showsControls`),
/// typing hides them again.
struct FocusEditor: UIViewControllerRepresentable {
    @Environment(Library.self) private var library
    @Binding var showsControls: Bool

    func makeUIViewController(context: Context) -> FocusViewController {
        let vc = FocusViewController(library: library)
        vc.onControlsChange = { shown in showsControls = shown }
        return vc
    }
    func updateUIViewController(_ vc: FocusViewController, context: Context) {
        vc.setControls(visible: showsControls)
    }
}

/// Text view that reports Backspace at the very start (to merge paragraphs).
final class FocusTextView: PlainPasteTextView {
    var onBackspaceAtStart: (() -> Void)?
    override func deleteBackward() {
        if selectedRange == NSRange(location: 0, length: 0) { onBackspaceAtStart?(); return }
        super.deleteBackward()
    }
}

@MainActor
final class FocusViewController: UIViewController, UITextViewDelegate {
    private let library: Library
    private let textView = FocusTextView()
    private let rail = ParagraphRail()
    private static let railResting: CGFloat = 0.35
    private let area = UILayoutGuide()

    private var index = 0
    private var size = 0.0   // current font size; 0 until the page is first fitted
    private var alignment = NSTextAlignment.center

    init(library: Library) {
        self.library = library
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        view.addLayoutGuide(area)
        view.keyboardLayoutGuide.followsUndockedKeyboard = true
        // The page is laid out against the screen edges, not the safe area:
        // revealing the bars (on the Duo, the side column's button and
        // status) then draws them over the writing instead of reflowing it.
        // It ends just above the keyboard (or the bottom of the screen).
        let fill = area.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12)
        fill.priority = .defaultHigh
        NSLayoutConstraint.activate([
            area.topAnchor.constraint(equalTo: view.topAnchor, constant: 32),
            area.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            area.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            area.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24),
            area.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -12),
            fill,
        ])

        textView.delegate = self
        textView.isScrollEnabled = false            // never scrolls: the text is sized to fit instead
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.tintColor = .systemOrange
        textView.autocapitalizationType = .sentences
        textView.inlinePredictionType = .no         // ghost text would be content we didn't measure
        textView.allowsEditingTextAttributes = true // ⌘B, ⌘I and the Format menu
        textView.onBackspaceAtStart = { [weak self] in self?.mergeWithPrevious() }
        view.addSubview(textView)

        // The dots: centred on the page, always there, quiet while you write.
        rail.translatesAutoresizingMaskIntoConstraints = false
        rail.onSelect = { [weak self] i in self?.show(i, caret: .end, direction: 0) }
        rail.alpha = Self.railResting
        view.addSubview(rail)
        NSLayoutConstraint.activate([
            rail.centerXAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            rail.centerYAnchor.constraint(equalTo: area.centerYAnchor),
            rail.widthAnchor.constraint(equalToConstant: 32),
            rail.heightAnchor.constraint(lessThanOrEqualTo: area.heightAnchor, multiplier: 0.7),
        ])

        let reveal = UITapGestureRecognizer(target: self, action: #selector(tappedOutsideText(_:)))
        reveal.delegate = self
        view.addGestureRecognizer(reveal)

        for dir in [UISwipeGestureRecognizer.Direction.up, .down] {
            let s = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
            s.direction = dir
            s.delegate = self   // not on the writing: drags there move the caret
            view.addGestureRecognizer(s)
        }

        let c = library.cursor
        show(c.paragraph, caret: .offset(c.offset), direction: 0)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
        if size > 0 { apply(size) }   // becoming first responder resets an empty view's typing font
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        fit(mayGrow: true)   // keyboard, rotation, fold: take the best size
    }

    // MARK: Paging

    enum Caret { case end, offset(Int) }

    private func show(_ i: Int, caret: Caret, direction: Int) {
        let paragraphs = library.document.paragraphs
        index = max(0, min(i, paragraphs.count - 1))
        size = 0
        let p = paragraphs[index]
        textView.attributedText = RichText.attributed(p.text, runs: p.runs, attributes: Self.attributes(17))
        fit(mayGrow: true)
        let len = (textView.text as NSString).length
        let loc: Int
        switch caret {
        case .end: loc = len
        case .offset(let o): loc = max(0, min(o, len))
        }
        textView.selectedRange = NSRange(location: loc, length: 0)
        updateTypingAttributes()
        updateRail()
        library.cursor = (index, loc)
        if direction != 0 {
            textView.transform = CGAffineTransform(translationX: 0, y: CGFloat(direction) * 40)
            textView.alpha = 0
            UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut]) {
                self.textView.transform = .identity
                self.textView.alpha = 1
            }
        }
    }

    // MARK: Controls

    var onControlsChange: ((Bool) -> Void)?
    private var controlsVisible = false
    private var hideTimer: Timer?

    /// The dots brighten with the rest of the controls.
    func setControls(visible: Bool) {
        guard visible != controlsVisible else { return }
        controlsVisible = visible
        UIView.animate(withDuration: 0.25) { self.rail.alpha = visible ? 1 : Self.railResting }
        hideTimer?.invalidate()
        if visible {
            // Shown for a moment, like video controls, unless you use them.
            hideTimer = .scheduledTimer(withTimeInterval: Screenshots.isActive ? 30 : 4, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.onControlsChange?(false) }
            }
        }
    }

    @objc private func tappedOutsideText(_ g: UITapGestureRecognizer) {
        onControlsChange?(!controlsVisible)
    }

    @objc private func swiped(_ g: UISwipeGestureRecognizer) {
        let direction = g.direction == .up ? 1 : -1
        let next = index + direction
        guard library.document.paragraphs.indices.contains(next) else { return }
        show(next, caret: .end, direction: direction)
    }

    private func updateRail() {
        let paragraphs = library.document.paragraphs
        rail.update(count: paragraphs.count, current: index, empty: paragraphs.map { $0.text.isEmpty })
    }

    private func mergeWithPrevious() {
        guard index > 0 else { return }
        var joinAt = 0
        library.update { joinAt = $0.mergeWithPrevious(index) ?? 0 }
        show(index - 1, caret: .offset(joinAt), direction: -1)
    }

    // MARK: UITextViewDelegate

    func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard text.contains("\n") else { return true }
        // Return (or a multi-line paste) splits the paragraph into pages.
        var caret = (index: index, offset: 0)
        library.update { doc in
            doc.setText(tv.text, runs: RichText.runs(in: tv.attributedText), at: index)
            caret = doc.replace(range.location..<(range.location + range.length), in: index, with: text)
        }
        show(caret.index, caret: .offset(caret.offset), direction: 1)
        return false
    }

    func textViewDidChange(_ tv: UITextView) {
        if controlsVisible { onControlsChange?(false) }   // writing again: out of the way
        let before = library.document.paragraphs[index].length
        library.update { $0.setText(tv.text, runs: RichText.runs(in: tv.attributedText), at: index) }
        // Deleting may grow the size freely; typing forward only for a clear win.
        fit(mayGrow: (tv.text as NSString).length < before, animated: true)
        updateRail()
    }

    func textViewDidChangeSelection(_ tv: UITextView) {
        library.cursor = (index, tv.selectedRange.location)
    }

    // MARK: Fitting

    /// New York at `size`.
    static func font(_ size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size)
        return UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size)
    }

    /// Natural line spacing: TextKit's line boxes hold every glyph, so
    /// nothing clips and the measurement is the layout.
    static func attributes(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: font(size), .foregroundColor: UIColor.label]
    }

    private func styled(_ size: Double) -> NSAttributedString {
        let text = textView.text ?? ""
        return RichText.attributed(text.isEmpty ? "M" : text, runs: RichText.runs(in: textView.attributedText),
                                   attributes: Self.attributes(CGFloat(size)))
    }

    /// Whether the paragraph fits the page at `size`, and no word is wider
    /// than a line (words never break). What must fit is from the top of the
    /// tallest letter down to the bottom of the last line box: the caret spans
    /// the box, and must stay clear of the keyboard, but the empty space above
    /// lowercase letters (a lone "g") may run into the top margin.
    private func fits(_ size: Double, in page: CGSize) -> Bool {
        let s = styled(size)
        let longestWord = Self.words.matches(in: s.string, range: NSRange(location: 0, length: s.length))
            .map { s.attributedSubstring(from: $0.range).size().width }.max() ?? 0
        guard longestWord <= page.width else { return false }
        return box(of: s, width: page.width) - ink(of: s, width: page.width).minY <= page.height
    }

    private func box(of s: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(s.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    /// Where the letters are actually drawn (glyph outlines), top-left origin.
    /// UIKit's bounding rects only give line boxes, so this asks Core Text,
    /// which lays the text out the same way.
    private func ink(of s: NSAttributedString, width: CGFloat) -> CGRect {
        let setter = CTFramesetterCreateWithAttributedString(s)
        let height: CGFloat = 100_000
        let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: CGRect(x: 0, y: 0, width: width, height: height), transform: nil), nil)
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return .zero }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(), &origins)
        return zip(lines, origins).reduce(CGRect.null) { drawn, line in
            let b = CTLineGetBoundsWithOptions(line.0, .useGlyphPathBounds)
            return drawn.union(CGRect(x: line.1.x + b.minX, y: height - (line.1.y + b.maxY), width: b.width, height: b.height))
        }
    }

    private static let words = try! NSRegularExpression(pattern: "\\S+")

    /// Sets the paragraph as large as the page allows and centres it between
    /// the top of the screen and the keyboard.
    private func fit(mayGrow: Bool, animated: Bool = false) {
        let page = area.layoutFrame
        guard page.width > 0, page.height > 0 else { return }
        let best = FocusFit.largest { fits($0, in: page.size) }
        let newSize = FocusFit.settle(best: best, current: size, mayGrow: mayGrow)

        if newSize != size { apply(newSize) }
        // The text view has the final say: if its layout is ever taller than
        // the page allows, step down rather than let anything hang off it.
        var h = measuredHeight(width: page.width), drawn = inkOfText(width: page.width)
        while h - drawn.minY > page.height, size > FocusFit.minSize {
            apply(max(FocusFit.minSize, size * 0.97))
            h = measuredHeight(width: page.width); drawn = inkOfText(width: page.width)
        }
        // One line is centred across the page too; once it wraps it's left-aligned
        // (the switch comes with the size change that wrapping brings).
        alignment = h < Self.font(CGFloat(size)).lineHeight * 1.5 ? .center : .natural
        textView.textAlignment = alignment
        updateTypingAttributes()
        // Centre the letters, keeping the last line box above the keyboard
        // and the tallest letter below the top of the page.
        let y = max(min(page.midY - drawn.midY, page.maxY - h), page.minY - drawn.minY)
        let frame = CGRect(x: page.minX, y: y, width: page.width, height: h)
        guard frame != textView.frame else { return }
        if animated {
            UIView.animate(withDuration: 0.17, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                self.textView.frame = frame
            }
        } else {
            textView.frame = frame
        }
    }

    private func apply(_ newSize: Double) {
        size = newSize
        let selection = textView.selectedRange
        if textView.text.isEmpty {
            // An empty text view sizes its caret from `font`; assigning even
            // an empty attributed string would reset it.
            textView.font = Self.font(CGFloat(size))
        } else {
            // Resize in place: replacing the text would drop undo, autocorrect
            // and text still being composed (dictation, other keyboards).
            let storage = textView.textStorage
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                storage.addAttribute(.font, value: RichText.font(Self.font(CGFloat(size)), RichText.style(of: value as? UIFont)), range: range)
            }
            storage.endEditing()
            textView.selectedRange = selection
        }
        updateTypingAttributes()
    }

    private func inkOfText(width: CGFloat) -> CGRect {
        ink(of: styled(size), width: width)
    }

    private func measuredHeight(width: CGFloat) -> CGFloat {
        // Empty, the caret is one line of the current font tall.
        if textView.text.isEmpty { return ceil(Self.font(CGFloat(size)).lineHeight) }
        return textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    /// New text continues the style before the caret.
    private func updateTypingAttributes() {
        let p = Paragraph(text: textView.text ?? "", runs: RichText.runs(in: textView.attributedText))
        var typing = Self.attributes(CGFloat(max(size, 17)))
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        typing[.paragraphStyle] = style
        if let base = typing[.font] as? UIFont {
            typing[.font] = RichText.font(base, p.style(at: textView.selectedRange.location))
        }
        textView.typingAttributes = typing
    }
}

/// Vertical dots, one per paragraph. Tap or drag to move between pages.
final class ParagraphRail: UIView {
    var onSelect: ((Int) -> Void)?
    private var count = 0, current = 0
    private var empty: [Bool] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(scrub(_:))))
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(scrub(_:))))
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(count: Int, current: Int, empty: [Bool]) {
        self.count = count; self.current = current; self.empty = empty
        isHidden = count < 2
        accessibilityLabel = "Paragraph \(current + 1) of \(count)"
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    override var intrinsicContentSize: CGSize { CGSize(width: 32, height: CGFloat(count) * 22) }

    private var pitch: CGFloat { count == 0 ? 0 : bounds.height / CGFloat(count) }

    override func draw(_ rect: CGRect) {
        guard count > 0 else { return }
        let d = min(7, pitch * 0.55)
        for i in 0..<count {
            let cy = pitch * (CGFloat(i) + 0.5)
            let h = i == current ? min(20, pitch * 0.85) : d
            let r = CGRect(x: bounds.midX - d / 2, y: cy - h / 2, width: d, height: h)
            let path = UIBezierPath(roundedRect: r, cornerRadius: d / 2)
            if i == current { UIColor.systemOrange.setFill(); path.fill() }
            else if i < empty.count && empty[i] { UIColor.tertiaryLabel.setStroke(); path.lineWidth = 1.5; path.stroke() }
            else { UIColor.tertiaryLabel.setFill(); path.fill() }
        }
    }

    @objc private func scrub(_ g: UIGestureRecognizer) {
        guard count > 1, pitch > 0 else { return }
        let i = max(0, min(count - 1, Int(g.location(in: self).y / pitch)))
        if i != current {
            UISelectionFeedbackGenerator().selectionChanged()
            onSelect?(i)
        }
    }

    override func accessibilityIncrement() { if current + 1 < count { onSelect?(current + 1) } }
    override func accessibilityDecrement() { if current > 0 { onSelect?(current - 1) } }
}

extension FocusViewController: UIGestureRecognizerDelegate {
    /// Taps and swipes on the writing edit it as usual; only those around it
    /// reveal the controls or change pages.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let p = touch.location(in: view)
        return !textView.frame.insetBy(dx: -8, dy: -8).contains(p) && !rail.frame.contains(p)
    }
}
