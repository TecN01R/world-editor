import SwiftUI
import UIKit
import WriterCore
import FocusLayout

/// Focus mode: one paragraph per page, set as large as the page allows.
/// The available area ends at `keyboardLayoutGuide`, the system's exact
/// keyboard position, so there is nothing to estimate and nothing scrolls.
///
/// Everything but the writing hides while you write: tapping outside the
/// text brings the controls back (`showsControls`), typing hides them again.
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
final class FocusTextView: UITextView {
    var onBackspaceAtStart: (() -> Void)?
    override func deleteBackward() {
        if selectedRange == NSRange(location: 0, length: 0) { onBackspaceAtStart?(); return }
        super.deleteBackward()
    }
}

@MainActor
final class FocusViewController: UIViewController, UITextViewDelegate {
    private let library: Library
    private let textView = FocusTextView(usingTextLayoutManager: false) // TextKit 1, same as the measurer
    private let rail = ParagraphRail()
    private let area = UILayoutGuide()
    private let engine = FitEngine()
    private var measurer = TextKitMeasurer()

    private var index = 0
    private var heldSize = 0.0
    private var heldLength = 0

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
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            // Keep a margin at the top even when the bars are hidden (safe area ≈ 0).
            area.topAnchor.constraint(greaterThanOrEqualTo: safe.topAnchor, constant: 12),
            area.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: 32),
            area.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            // Full width: the Duo's side column isn't reserved in Focus mode.
            area.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            area.bottomAnchor.constraint(lessThanOrEqualTo: safe.bottomAnchor, constant: -16),
            area.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -12),
        ])
        let fill = area.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12)
        fill.priority = .defaultHigh
        fill.isActive = true
        let pullUp = area.topAnchor.constraint(equalTo: view.topAnchor)   // as high as the minimums allow
        pullUp.priority = .defaultLow
        pullUp.isActive = true

        textView.delegate = self
        textView.isScrollEnabled = false            // never scrolls: the text is sized to fit instead
        textView.clipsToBounds = false              // descenders/overhangs may draw past the box
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.tintColor = .systemOrange
        textView.autocapitalizationType = .sentences
        textView.inlinePredictionType = .no         // ghost text would be content we didn't measure
        textView.allowsEditingTextAttributes = true // ⌘B, ⌘I and the Format menu
        textView.onBackspaceAtStart = { [weak self] in self?.mergeWithPrevious() }
        view.addSubview(textView)

        rail.translatesAutoresizingMaskIntoConstraints = false
        rail.onSelect = { [weak self] i in self?.show(i, caret: .end, direction: 0) }
        view.addSubview(rail)
        rail.alpha = 0   // hidden with the other controls until revealed
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
            view.addGestureRecognizer(s)
        }

        let c = library.cursor
        show(c.paragraph, caret: .offset(c.offset), direction: 0)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutText(animated: false, allowGrow: true)
    }

    // MARK: Paging

    enum Caret { case end, offset(Int) }

    private func show(_ i: Int, caret: Caret, direction: Int) {
        let paragraphs = library.document.paragraphs
        index = max(0, min(i, paragraphs.count - 1))
        heldSize = 0
        let p = paragraphs[index]
        textView.attributedText = RichText.attributed(p.text, runs: p.runs, attributes: TextKitMeasurer.attributes(size: 17))  // resized by layoutText
        layoutText(animated: false, allowGrow: true)
        let len = (textView.text as NSString).length
        let loc: Int
        switch caret {
        case .end: loc = len
        case .offset(let o): loc = max(0, min(o, len))
        }
        textView.selectedRange = NSRange(location: loc, length: 0)
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

    /// The paragraph dots come and go with the rest of the controls.
    func setControls(visible: Bool) {
        guard visible != controlsVisible else { return }
        controlsVisible = visible
        UIView.animate(withDuration: 0.25) { self.rail.alpha = visible ? 1 : 0 }
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
        // Deleting may grow the size freely; typing forward only grows for a clear win.
        let shrank = (tv.text as NSString).length < heldLength
        library.update { $0.setText(tv.text, runs: RichText.runs(in: tv.attributedText), at: index) }
        layoutText(animated: true, allowGrow: shrank)
        updateRail()
    }

    func textViewDidChangeSelection(_ tv: UITextView) {
        library.cursor = (index, tv.selectedRange.location)
    }

    // MARK: Fitting

    private func layoutText(animated: Bool, allowGrow: Bool) {
        let frame = area.layoutFrame
        guard frame.width > 0, frame.height > 0 else { return }
        let text = textView.text ?? ""
        measurer.runs = RichText.runs(in: textView.attributedText)
        let page = (width: Double(frame.width), height: Double(frame.height))
        var fit = engine.fit(text, in: page, measurer: measurer,
                             held: heldSize, allowGrow: allowGrow || heldSize == 0)
        var extent = apply(fit, in: frame)

        // Ground truth: position and verify using where TextKit actually drew
        // the glyphs, not the prediction. If the real block is taller than the
        // page, step down until it truly fits. Nothing may hang off the top or
        // under the keyboard.
        var k = FitEngine.steps.firstIndex(of: fit.fontSize) ?? 0
        while k > 0, extent.height > frame.height + 0.5 {
            k -= 1
            fit = engine.fit(text, in: page, measurer: measurer, held: FitEngine.steps[k], allowGrow: false)
            extent = apply(fit, in: frame)
        }

        let changed = fit.fontSize != heldSize
        heldSize = fit.fontSize
        heldLength = (text as NSString).length
        if animated && changed {
            UIView.animate(withDuration: 0.17, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                self.view.layoutIfNeeded()
            }
        }
    }

    /// Applies the size, then positions the text view so the visible block
    /// (top of the tallest letter to the bottom of the last line, or of a
    /// deeper descender) is centred in `frame`. Returns that block, in the
    /// text view's own coordinates, as measured from the real layout.
    private func apply(_ fit: FitResult, in frame: CGRect) -> (top: CGFloat, height: CGFloat) {
        let selection = textView.selectedRange
        let attrs = TextKitMeasurer.attributes(size: fit.fontSize)
        let styled = Paragraph(text: textView.text ?? "", runs: measurer.runs)
        textView.attributedText = RichText.attributed(styled.text, runs: styled.runs, attributes: attrs)
        textView.selectedRange = selection
        var typing = attrs
        typing[.font] = RichText.font(TextKitMeasurer.font(CGFloat(fit.fontSize)), styled.style(at: selection.location))
        textView.typingAttributes = typing

        let caretRoom = CGFloat(fit.fontSize * 0.06) + 2
        let width = min(frame.width, CGFloat(fit.blockSize.width) + caretRoom)
        let height = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        textView.frame = CGRect(x: frame.minX, y: frame.minY, width: width, height: height)

        let block = visibleBlock(fontSize: fit.fontSize)
        let top = FitEngine.centredTop(blockHeight: Double(block.height),
                                       areaTop: Double(frame.minY), areaBottom: Double(frame.maxY), margin: 0)
        textView.frame.origin.y = CGFloat(top) - block.top
        return block
    }

    /// Measures the drawn block from TextKit: first baseline minus the tallest
    /// glyph's ascent, down to the larger of the last line box and the deepest
    /// descender below the last baseline.
    private func visibleBlock(fontSize: Double) -> (top: CGFloat, height: CGFloat) {
        let lm = textView.layoutManager
        let container = textView.textContainer
        lm.ensureLayout(for: container)
        let ink = measurer.ink(textView.text ?? "")
        let s = CGFloat(fontSize)
        let glyphs = lm.numberOfGlyphs

        func baseline(ofGlyph g: Int) -> (CGFloat, CGRect) {
            let frag = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
            return (frag.minY + lm.location(forGlyphAt: g).y, frag)
        }

        let firstBaseline: CGFloat, lastBaseline: CGFloat, lastLineBottom: CGFloat
        if glyphs == 0 {
            // Empty paragraph: TextKit lays out an "extra" line for the caret.
            let frag = lm.extraLineFragmentRect
            let f = TextKitMeasurer.font(s)
            firstBaseline = frag.maxY + f.descender
            lastBaseline = firstBaseline
            lastLineBottom = frag.maxY
        } else {
            let (b0, _) = baseline(ofGlyph: 0)
            let (b1, lastFrag) = baseline(ofGlyph: glyphs - 1)
            firstBaseline = b0
            lastBaseline = b1
            lastLineBottom = lm.extraLineFragmentTextContainer == nil ? lastFrag.maxY
                : max(lastFrag.maxY, lm.extraLineFragmentRect.maxY)
        }
        let inset = textView.textContainerInset.top
        let top = inset + firstBaseline - CGFloat(ink.inkAscent) * s - 0.03 * s
        let bottom = inset + max(lastLineBottom, lastBaseline + CGFloat(ink.inkDescent) * s + 0.03 * s)
        return (top, bottom - top)
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

    override func accessibilityIncrement() { if current > 0 { onSelect?(current - 1) } }
    override func accessibilityDecrement() { if current + 1 < count { onSelect?(current + 1) } }
}

extension FocusViewController: UIGestureRecognizerDelegate {
    /// Taps on the writing place the caret as usual; only taps around it reveal the controls.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let p = touch.location(in: view)
        return !textView.frame.insetBy(dx: -8, dy: -8).contains(p) && !(rail.alpha > 0 && rail.frame.contains(p))
    }
}
