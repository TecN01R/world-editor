import SwiftUI
import UIKit
import WriterCore
import FocusLayout

/// Focus mode: one paragraph per page, set as large as the page allows.
/// The available area ends at `keyboardLayoutGuide`, the system's exact
/// keyboard position, so there is nothing to estimate and nothing scrolls.
struct FocusEditor: UIViewControllerRepresentable {
    @Environment(Library.self) private var library

    func makeUIViewController(context: Context) -> FocusViewController {
        FocusViewController(library: library)
    }
    func updateUIViewController(_ vc: FocusViewController, context: Context) {}
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
    private let measurer = TextKitMeasurer()

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
            area.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            area.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            area.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -40),
            area.bottomAnchor.constraint(lessThanOrEqualTo: safe.bottomAnchor, constant: -16),
            area.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -12),
        ])
        let fill = area.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12)
        fill.priority = .defaultHigh
        fill.isActive = true

        textView.delegate = self
        textView.isScrollEnabled = false            // never scrolls: the text is sized to fit instead
        textView.clipsToBounds = false              // descenders/overhangs may draw past the box
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.tintColor = .systemOrange
        textView.autocapitalizationType = .sentences
        textView.inlinePredictionType = .no         // ghost text would be content we didn't measure
        textView.onBackspaceAtStart = { [weak self] in self?.mergeWithPrevious() }
        view.addSubview(textView)

        rail.translatesAutoresizingMaskIntoConstraints = false
        rail.onSelect = { [weak self] i in self?.show(i, caret: .end, direction: 0) }
        view.addSubview(rail)
        NSLayoutConstraint.activate([
            rail.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -4),
            rail.centerYAnchor.constraint(equalTo: area.centerYAnchor),
            rail.widthAnchor.constraint(equalToConstant: 32),
            rail.heightAnchor.constraint(lessThanOrEqualTo: area.heightAnchor, multiplier: 0.7),
        ])

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

    enum Caret { case start, end, offset(Int) }

    private func show(_ i: Int, caret: Caret, direction: Int) {
        let paragraphs = library.document.paragraphs
        index = max(0, min(i, paragraphs.count - 1))
        heldSize = 0
        textView.text = paragraphs[index].text
        layoutText(animated: false, allowGrow: true)
        let len = (textView.text as NSString).length
        let loc: Int
        switch caret {
        case .start: loc = 0
        case .end: loc = len
        case .offset(let o): loc = max(0, min(o, len))
        }
        textView.selectedRange = NSRange(location: loc, length: 0)
        rail.update(count: paragraphs.count, current: index, empty: paragraphs.map { $0.text.isEmpty })
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

    @objc private func swiped(_ g: UISwipeGestureRecognizer) {
        let next = index + (g.direction == .up ? 1 : -1)
        guard library.document.paragraphs.indices.contains(next) else { return }
        show(next, caret: .end, direction: g.direction == .up ? 1 : -1)
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
        let current = (tv.text as NSString).replacingCharacters(in: range, with: text)
        let caret = range.location + (text as NSString).length
        let pieces = current.components(separatedBy: "\n")
        let before = (current as NSString).substring(to: caret)
        let target = index + before.components(separatedBy: "\n").count - 1
        let offset = (before.components(separatedBy: "\n").last ?? "").count
        library.update { doc in
            doc.setText(pieces[0], at: index)
            var at = index
            for piece in pieces.dropFirst() {
                at = doc.split(at: at, offset: doc.paragraphs[at].text.count)
                doc.setText(piece, at: at)
            }
        }
        show(target, caret: .offset(offset), direction: 1)
        return false
    }

    func textViewDidChange(_ tv: UITextView) {
        let grew = (tv.text as NSString).length < heldLength
        library.update { $0.setText(tv.text, at: index) }
        layoutText(animated: true, allowGrow: grew)
        let paragraphs = library.document.paragraphs
        rail.update(count: paragraphs.count, current: index, empty: paragraphs.map { $0.text.isEmpty })
    }

    func textViewDidChangeSelection(_ tv: UITextView) {
        library.cursor = (index, tv.selectedRange.location)
    }

    // MARK: Fitting

    private func layoutText(animated: Bool, allowGrow: Bool) {
        let frame = area.layoutFrame
        guard frame.width > 0, frame.height > 0 else { return }
        let text = textView.text ?? ""
        var fit = engine.fit(text, in: (Double(frame.width), Double(frame.height)),
                             measurer: measurer, held: heldSize, allowGrow: allowGrow || heldSize == 0)
        apply(fit, in: frame)

        // Ground truth: if the real layout is taller than the fit predicted,
        // step down until it truly fits. Nothing may hang under the keyboard.
        var k = FitEngine.steps.firstIndex(of: fit.fontSize) ?? 0
        while k > 0, textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)).height
                > frame.height + fit.topOverhang + 1 {
            k -= 1
            fit = engine.fit(text, in: (Double(frame.width), Double(frame.height)), measurer: measurer,
                             held: FitEngine.steps[k], allowGrow: false)
            apply(fit, in: frame)
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

    private func apply(_ fit: FitResult, in frame: CGRect) {
        let selection = textView.selectedRange
        let attrs = TextKitMeasurer.attributes(size: fit.fontSize)
        textView.typingAttributes = attrs
        textView.attributedText = NSAttributedString(string: textView.text ?? "", attributes: attrs)
        textView.selectedRange = selection

        let caretRoom = CGFloat(fit.fontSize * 0.06) + 2
        let width = min(frame.width, CGFloat(fit.blockSize.width) + caretRoom)
        let height = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let visible = CGFloat(fit.blockSize.height)
        let top = FitEngine.centredTop(blockHeight: Double(visible),
                                       areaTop: Double(frame.minY), areaBottom: Double(frame.maxY))
        textView.frame = CGRect(x: frame.minX, y: CGFloat(top) - CGFloat(fit.topOverhang),
                                width: width, height: height)
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
