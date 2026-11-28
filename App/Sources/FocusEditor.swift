import SwiftUI
import UIKit
import WriterCore
import FocusLayout

/// Focus mode: one paragraph per page, set as large as the page allows and
/// centred on it. The page ends at `keyboardLayoutGuide`, the system's exact
/// keyboard position, so there is nothing to estimate and nothing scrolls.
///
/// Everything but the writing hides (the paragraph dots dim) while you write:
/// tapping anywhere brings the controls back (`showsControls`); typing, or a
/// few seconds, hides them again.
struct FocusEditor: UIViewControllerRepresentable {
    @Environment(Library.self) private var library
    @Binding var showsControls: Bool

    func makeUIViewController(context: Context) -> FocusViewController {
        let vc = FocusViewController(library: library)
        // Animated here so only the bars fade with the controls, not the whole page's layout.
        vc.onControlsChange = { shown in withAnimation(.easeInOut(duration: 0.25)) { showsControls = shown } }
        return vc
    }
    func updateUIViewController(_ vc: FocusViewController, context: Context) {
        vc.setControls(visible: showsControls)
        vc.showChanges()
    }
}

/// Text view that reports Backspace at the very start (to merge paragraphs),
/// and cuts the caret off at the bottom of the page (`caretBottom`).
final class FocusTextView: PlainPasteTextView {
    var onBackspaceAtStart: (() -> Void)?
    var caretBottom = CGFloat.greatestFiniteMagnitude

    override func deleteBackward() {
        if selectedRange == NSRange(location: 0, length: 0) { onBackspaceAtStart?(); return }
        super.deleteBackward()
    }

    override func caretRect(for position: UITextPosition) -> CGRect {
        var r = super.caretRect(for: position)
        r.size.height = max(0, min(r.maxY, caretBottom) - r.minY)
        return r
    }
}

@MainActor
final class FocusViewController: UIViewController, UITextViewDelegate {
    private let library: Library
    private let textView = FocusTextView(usingTextLayoutManager: false)   // TextKit 1: see FocusHyphenation
    private let hyphenation = FocusHyphenation()
    private let lines = FocusLines()
    private let rail = ParagraphRail()
    private static let railResting: CGFloat = 0.35
    private let area = UILayoutGuide()

    private var index = 0
    private var size = 0.0   // current font size; 0 until the page is first fitted
    /// The page's paragraphs as last shown or typed: the page differing from them was
    /// changed by something else.
    private var shown: [Paragraph] = []

    init(library: Library) {
        self.library = library
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Look.background

        view.addLayoutGuide(area)
        view.keyboardLayoutGuide.followsUndockedKeyboard = true
        // The page is laid out against the screen edges, not the safe area:
        // revealing the bars (on the Duo, the side column's button and
        // status) then draws them over the writing instead of reflowing it.
        // It ends just above the keyboard (or the bottom of the screen), with
        // the same margin above the letters as below them and at the side.
        let margin: CGFloat = 16
        let fill = area.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -margin)
        fill.priority = .defaultHigh
        NSLayoutConstraint.activate([
            area.topAnchor.constraint(equalTo: view.topAnchor, constant: margin),
            area.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            area.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),   // just clear of the dots
            area.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24),
            area.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -margin),
            fill,
        ])

        textView.delegate = self
        textView.layoutManager.delegate = hyphenation
        textView.isScrollEnabled = false            // never scrolls: the text is sized to fit instead
        textView.contentInsetAdjustmentBehavior = .never   // placed by hand; revealed bars mustn't push it down
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.tintColor = Look.emphasis   // white, as every control is
        textView.autocapitalizationType = .sentences
        textView.inlinePredictionType = .no         // ghost text would be content we didn't measure
        textView.allowsEditingTextAttributes = true // ⌘B, ⌘I and the Format menu
        textView.textFormattingConfiguration = RichText.formatting
        textView.onBackspaceAtStart = { [weak self] in self?.mergeWithPrevious() }
        view.addSubview(textView)

        // The dots: centred on the page, always there, quiet while you write.
        rail.translatesAutoresizingMaskIntoConstraints = false
        rail.onSelect = { [weak self] page in
            guard let self, pageStarts.indices.contains(page) else { return }
            show(pageStarts[page], caret: .end, direction: 0)
        }
        rail.alpha = Self.railResting
        view.addSubview(rail)
        NSLayoutConstraint.activate([
            rail.centerXAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            rail.centerYAnchor.constraint(equalTo: area.centerYAnchor),
            rail.widthAnchor.constraint(equalToConstant: 32),
            rail.heightAnchor.constraint(lessThanOrEqualTo: area.heightAnchor, multiplier: 0.7),
        ])

        let reveal = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        reveal.delegate = self
        reveal.cancelsTouchesInView = false   // taps on the writing still place the caret
        view.addGestureRecognizer(reveal)

        for dir in [UISwipeGestureRecognizer.Direction.up, .down] {
            let s = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
            s.direction = dir
            s.delegate = self   // not on the caret or selection handles
            view.addGestureRecognizer(s)
        }

        let c = library.cursor
        show(c.paragraph, caret: .offset(c.offset), direction: 0)
    }

    // As soon as it's on screen, not once the switch from Edit has finished
    // animating: the page's text view still has the keyboard then and hands it
    // over, so the keyboard stays up through the switch (Kevin, 2026-11-23).
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        textView.becomeFirstResponder()
        if size > 0 { apply(size) }   // becoming first responder resets an empty view's typing font
    }

    private var fittedPage = CGRect.null

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Keyboard, rotation, fold: refit. Only when the page changed; typing
        // refits on its own (and mustn't be undone mid-zoom).
        guard area.layoutFrame != fittedPage else { return }
        fittedPage = area.layoutFrame
        fit()
    }

    // MARK: Paging

    enum Caret { case end, offset(Int) }

    private func show(_ i: Int, caret: Caret, direction: Int) {
        let paragraphs = library.document.paragraphs
        index = max(0, min(i, paragraphs.count - 1))
        size = 0
        let p = paragraphs[index]
        textView.attributedText = RichText.attributed(p, attributes: Self.attributes(17))
        textView.undoManager?.removeAllActions()   // its steps were for the paragraph shown before
        shown = paragraphs
        fit()
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

    /// The writing changed underneath (filing, its Undo, a linked page renamed): shown as it
    /// is now, caret kept, or the next keystroke would write the old text back. Not mid-word.
    func showChanges() {
        guard !shown.isEmpty, textView.markedTextRange == nil, library.document.paragraphs != shown else { return }
        show(index, caret: .offset(textView.selectedRange.location), direction: 0)
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
        if visible { scheduleHide() } else { hideTimer?.invalidate() }
    }

    /// How long the controls stay: 4 s; 30 in a scene (Scenes/), so its picture catches them.
    private static var controlsShown: TimeInterval {
        #if DEBUG
        if LaunchScene.current != nil { return 30 }
        #endif
        return 4
    }

    /// Shown for a moment, like video controls, unless you use them.
    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = .scheduledTimer(withTimeInterval: Self.controlsShown, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.onControlsChange?(false) }
        }
    }

    /// Any tap shows the controls (a double tap must not show then hide
    /// them); another tap keeps them up a little longer.
    @objc private func tapped(_ g: UITapGestureRecognizer) {
        if controlsVisible { scheduleHide() } else { onControlsChange?(true) }
    }

    @objc private func swiped(_ g: UISwipeGestureRecognizer) {
        let direction = g.direction == .up ? 1 : -1
        let starts = pageStarts
        let next = FocusPages.page(of: index, starts: starts) + direction
        guard starts.indices.contains(next) else { return }
        show(starts[next], caret: .end, direction: direction)
    }

    /// The paragraph each page starts at: blank lines in a row are one page.
    private var pageStarts: [Int] { FocusPages.starts(empty: library.document.paragraphs.map { $0.text.isEmpty }) }

    private func updateRail() {
        let paragraphs = library.document.paragraphs, starts = pageStarts
        rail.update(count: starts.count, current: FocusPages.page(of: index, starts: starts),
                    empty: starts.map { paragraphs[$0].text.isEmpty })
    }

    private func mergeWithPrevious() {
        guard index > 0 else { return }
        var joinAt = 0
        library.update { joinAt = $0.mergeWithPrevious(index) ?? 0 }
        show(index - 1, caret: .offset(joinAt), direction: -1)
    }

    // MARK: UITextViewDelegate

    /// Holding or selecting text: iOS's edit menu, its Format only Bold and Italic.
    func textView(_ tv: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        RichText.editMenu(suggestedActions)
    }

    /// Focus is for the words: links show, but tapping one just places the caret.
    func textView(_ tv: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? { nil }

    func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if RichText.unlinkIfEditing(tv, range: range, replacement: text) { return false }
        guard text.contains(where: \.isNewline) else { return true }
        // Return (or a multi-line paste) splits the paragraph into pages.
        var caret = (index: index, offset: 0)
        library.update { doc in
            doc.setText(tv.text, runs: RichText.runs(in: tv.attributedText), links: RichText.links(in: tv.attributedText),
                        placed: RichText.placed(in: tv.attributedText), at: index)
            caret = doc.replace(range.location..<(range.location + range.length), in: index, with: text)
        }
        show(caret.index, caret: .offset(caret.offset), direction: 1)
        return false
    }

    func textViewDidChange(_ tv: UITextView) {
        if controlsVisible { onControlsChange?(false) }   // writing again: out of the way
        library.update { $0.setText(tv.text, runs: RichText.runs(in: tv.attributedText), links: RichText.links(in: tv.attributedText),
                                    placed: RichText.placed(in: tv.attributedText), at: index) }
        shown = library.document.paragraphs
        fit(animated: true)
        updateRail()
    }

    func textViewDidChangeSelection(_ tv: UITextView) {
        RichText.typeAsTheAuthor(tv)
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
        [.font: font(size), .foregroundColor: Look.ink]   // as in Edit mode
    }

    /// The paragraph at `size`, styled as the text view shows it.
    private func styled(_ size: Double) -> NSAttributedString {
        let text = textView.text ?? ""
        var attributes = Self.attributes(CGFloat(size))
        attributes[.paragraphStyle] = paragraphStyle
        return RichText.attributed(text.isEmpty ? "M" : text, runs: RichText.runs(in: textView.attributedText),
                                   attributes: attributes)
    }

    /// Whether the paragraph fits the page at `size` with no word cut but at
    /// a hyphen. What must fit is the letters as drawn, from the top of the
    /// tallest to the bottom of the lowest: the empty space a line box keeps
    /// above and below them (for accents and for tails like "g") may run off
    /// the page, and the caret is cut off at its bottom. Across, the letters
    /// as drawn must stay on the page too: lines wrap by each letter's
    /// typographic width, but a big serif W's or an italic f's ink reaches
    /// past it. Text with no ink (only spaces) fits its line box instead.
    private func fits(_ size: Double, in page: CGSize) -> Bool {
        let l = lines.layout(styled(size), width: page.width)
        guard !l.splitsWord else { return false }
        if l.ink.isEmpty { return l.height <= page.height }
        return l.ink.height <= page.height && l.ink.width <= page.width   // placed by its ink, see `fit`
    }

    /// Sets the paragraph as large as the page allows and centres it between
    /// the top of the screen and the keyboard.
    private func fit(animated: Bool = false) {
        let page = area.layoutFrame
        guard page.width > 0, page.height > 0 else { return }
        let newSize = FocusFit.largest { fits($0, in: page.size) }
        let old = (frame: textFrame, size: size, start: textStart)

        if newSize != size { apply(newSize) }
        applyParagraphStyle()
        let h = measuredHeight(width: page.width)
        // One line is centred across the page too; once it wraps it's left-aligned
        // (the switch comes with the size change that wrapping brings).
        let centred = h < Self.font(CGFloat(size)).lineHeight * 1.5
        updateTypingAttributes()
        let measured = lines.layout(styled(size), width: page.width), drawn = measured.ink
        // Centre the letters, keeping the lowest above the keyboard and the
        // tallest below the top of the page. (Text with no ink, only spaces,
        // goes by its line box and caret.)
        let bottom = drawn.isEmpty ? h : drawn.maxY
        let y = max(min(page.midY - drawn.midY, page.maxY - bottom), page.minY - drawn.minY)
        // One line is centred here rather than by TextKit, which leaves out
        // spaces typed at its end, so a space wouldn't show. It's centred on
        // the screen rather than the page (which leaves room for the dots on
        // the right) when there's room to spare. Wrapped text keeps to the
        // left margin.
        let x: CGFloat
        if !centred {
            x = page.minX - drawn.minX   // its letters start at the margin, even ones that overhang (a serif W)
        } else if textView.text.isEmpty {
            x = view.bounds.midX - 1   // the caret
        } else {
            let left = drawn.minX, right = max(drawn.maxX, measured.end)   // no ink: .zero
            x = max(min(view.bounds.midX - (left + right) / 2, page.maxX - right), page.minX - left)
        }
        let frame = CGRect(x: x, y: y, width: page.width, height: h)
        textView.caretBottom = page.maxY - y
        let changed = frame != old.frame || size != old.size
        if changed { textFrame = frame }
        textStart = firstLetterX()
        guard changed, animated, old.size > 0 else { return }
        // Zoom, rather than snap to the new size and then slide: draw the new
        // layout over the letters as they are on screen right now (mid-zoom,
        // if typing fast), then ease it into place. The first letter is the
        // fixed point: it keeps its place while the rest scales around it,
        // even when a centred line re-centres around a new letter.
        let scale = old.size / size
        let from = CGPoint(x: old.frame.minX + old.start, y: old.frame.minY)
        let to = CGPoint(x: frame.minX + textStart, y: frame.minY)
        let centre = CGPoint(x: frame.midX, y: frame.midY), oldCentre = CGPoint(x: old.frame.midX, y: old.frame.midY)
        let shown = textView.layer.presentation()?.affineTransform() ?? textView.transform
        // Where the new layout's centre lands: on the old layout, then as shown.
        let onOld = CGPoint(x: from.x + scale * (centre.x - to.x), y: from.y + scale * (centre.y - to.y))
        let onScreen = CGPoint(x: oldCentre.x + shown.a * (onOld.x - oldCentre.x) + shown.tx,
                               y: oldCentre.y + shown.d * (onOld.y - oldCentre.y) + shown.ty)
        textView.layer.removeAllAnimations()
        textView.transform = CGAffineTransform(a: shown.a * scale, b: 0, c: 0, d: shown.d * scale,
                                               tx: onScreen.x - centre.x, ty: onScreen.y - centre.y)
        UIView.animate(withDuration: 0.17, delay: 0, options: [.curveEaseOut]) { self.textView.transform = .identity }
    }

    /// Where the first letter starts, across the text view, as last laid out.
    private var textStart: CGFloat = 0

    /// Where the first letter starts across the text view, at the current size.
    private func firstLetterX() -> CGFloat {
        textView.layoutIfNeeded()
        return textView.caretRect(for: textView.beginningOfDocument).midX
    }

    /// The text view's untransformed frame. Set through its bounds and centre,
    /// which a zoom (transform) doesn't affect, unlike `frame`.
    private var textFrame: CGRect {
        get { CGRect(x: textView.center.x - textView.bounds.width / 2, y: textView.center.y - textView.bounds.height / 2,
                     width: textView.bounds.width, height: textView.bounds.height) }
        set {
            textView.bounds.size = newValue.size
            textView.center = CGPoint(x: newValue.midX, y: newValue.midY)
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

    /// Hyphenation wherever it saves space (the most iOS allows), to make the
    /// paragraph as large as it can be. Always left-aligned: `fit` centres a
    /// single line itself.
    private var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.hyphenationFactor = 1
        return style
    }

    /// Puts `paragraphStyle` on the whole paragraph, unless it's there already
    /// (an edit mid-composition would disturb the keyboard).
    private func applyParagraphStyle() {
        let style = paragraphStyle, storage = textView.textStorage
        let all = NSRange(location: 0, length: storage.length)
        var same = true
        storage.enumerateAttribute(.paragraphStyle, in: all) { value, _, stop in
            if (value as? NSParagraphStyle) != style { same = false; stop.pointee = true }
        }
        guard !same else { return }
        let selection = textView.selectedRange
        storage.addAttribute(.paragraphStyle, value: style, range: all)
        textView.selectedRange = selection
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
        typing[.paragraphStyle] = paragraphStyle
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
    /// Taps anywhere reveal the controls; swipes change pages from anywhere
    /// but the caret and selection handles, where a drag moves them. The rail
    /// handles its own.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let p = touch.location(in: view)
        return !rail.frame.contains(p) && !(g is UISwipeGestureRecognizer && nearSelectionEnds(p))
    }

    /// The reveal tap goes alongside the text view's own (placing the caret).
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        g is UITapGestureRecognizer
    }

    private func nearSelectionEnds(_ p: CGPoint) -> Bool {
        guard let range = textView.selectedTextRange else { return false }
        return [range.start, range.end].contains { end in
            view.convert(textView.caretRect(for: end), from: textView).insetBy(dx: -22, dy: -22).contains(p)
        }
    }
}
