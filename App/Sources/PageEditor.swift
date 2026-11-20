import SwiftUI
import UIKit
import WriterCore

/// Traditional view: the whole document, one paragraph per line, with real
/// paragraph spacing. Typing is native UITextView (undo, autocorrect,
/// dictation, selection all behave as iOS users expect).
struct PageEditor: UIViewRepresentable {
    @Environment(Library.self) private var library

    func makeCoordinator() -> Coordinator { Coordinator(library: library) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView(usingTextLayoutManager: true)
        tv.delegate = context.coordinator
        tv.backgroundColor = .systemBackground
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.textContainerInset = UIEdgeInsets(top: 72, left: 0, bottom: 240, right: 0)
        tv.typingAttributes = Self.attributes
        tv.attributedText = NSAttributedString(string: library.document.plainText, attributes: Self.attributes)
        context.coordinator.restoreCaret(in: tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        // Readable measure: centre a column of ~36em on wide screens (unfolded).
        let width = tv.bounds.width
        let column = min(width - 44, 36 * 19)
        let side = max(22, (width - column) / 2)
        if tv.textContainerInset.left != side {
            tv.textContainerInset.left = side
            tv.textContainerInset.right = side
        }
    }

    static let font: UIFont = {
        let base = UIFont.preferredFont(forTextStyle: .body).withSize(19)
        return UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: 19)
    }()

    static var attributes: [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.35
        p.paragraphSpacing = 14
        return [.font: font, .foregroundColor: UIColor.label, .paragraphStyle: p]
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        let library: Library
        init(library: Library) { self.library = library }

        func textViewDidChange(_ tv: UITextView) {
            library.update { $0.setPlainText(tv.text) }
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            let ns = tv.text as NSString
            let loc = min(tv.selectedRange.location, ns.length)
            let before = ns.substring(to: loc)
            let lines = before.components(separatedBy: "\n")
            library.cursor = (lines.count - 1, (lines.last ?? "").count)
        }

        func restoreCaret(in tv: UITextView) {
            let paras = library.document.paragraphs
            let p = min(library.cursor.paragraph, paras.count - 1)
            var loc = paras.prefix(p).reduce(0) { $0 + ($1.text as NSString).length + 1 }
            loc += min(library.cursor.offset, (paras[p].text as NSString).length)
            tv.selectedRange = NSRange(location: loc, length: 0)
            DispatchQueue.main.async {
                tv.becomeFirstResponder()
                tv.scrollRangeToVisible(tv.selectedRange)
            }
        }
    }
}
