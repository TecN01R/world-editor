import UIKit
import WriterCore

/// A text view whose pastes and drops arrive as plain text in the current style, so
/// another app's fonts and colours (black text, invisible in dark mode) never
/// get in, nor images. `@` links survive copy and paste within the app: they
/// travel beside the text on the pasteboard, so other apps still get ordinary text.
class PlainPasteTextView: UITextView, UITextPasteDelegate {
    private static let linksType = "app.world-editor.links"

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        pasteDelegate = self   // drops (and any paste iOS makes itself) come in by `performPasteOf`
    }

    required init?(coder: NSCoder) { fatalError() }

    override func copy(_ sender: Any?) {
        let links = RichText.links(in: attributedText, range: selectedRange)
        super.copy(sender)
        attach(links)
    }

    override func cut(_ sender: Any?) {
        let links = RichText.links(in: attributedText, range: selectedRange)
        super.cut(sender)
        attach(links)
    }

    override func paste(_ sender: Any?) {
        let board = UIPasteboard.general
        guard let pasted = board.string else { return }   // only words: pages hold no images
        let text = WriterCore.Document.plainLineBreaks(pasted)
        insertText(text)   // takes the typing attributes, goes through the delegate
        guard let data = board.data(forPasteboardType: Self.linksType),
              let links = try? JSONDecoder().decode([PageLink].self, from: data), !links.isEmpty else { return }
        // Only if the pasted text ends at the caret: the delegate may have put it elsewhere
        // (Focus mode makes pages of a paste's lines, its links left behind).
        let length = text.utf16.count
        let start = selectedRange.location - length
        guard start >= 0,
              (attributedText.string as NSString).substring(with: NSRange(location: start, length: length)) == text else { return }
        for link in links where link.location + link.length <= length {
            textStorage.addAttribute(.link, value: RichText.url(link.page),
                                     range: NSRange(location: start + link.location, length: link.length))
        }
        delegate?.textViewDidChange?(self)   // save the links with the text
    }

    /// Adds `links` to the item just copied, beside the system's own representations.
    private func attach(_ links: [PageLink]) {
        let board = UIPasteboard.general
        guard !links.isEmpty, let data = try? JSONEncoder().encode(links), var items = board.items.first else { return }
        items[Self.linksType] = data
        board.items = [items]
    }

    /// Dropped text, as a paste: plain, in the current style, through the delegate.
    func textPasteConfigurationSupporting(_ supporting: any UITextPasteConfigurationSupporting,
                                          performPasteOf attributedString: NSAttributedString,
                                          to textRange: UITextRange) -> UITextRange {
        let text = WriterCore.Document.plainLineBreaks(attributedString.string.replacingOccurrences(of: "\u{FFFC}", with: ""))
        guard !text.isEmpty else { return textRange }   // an image: nothing to put on the page
        selectedTextRange = textRange
        insertText(text)
        return selectedTextRange ?? textRange
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        action == #selector(paste(_:)) ? UIPasteboard.general.hasStrings : super.canPerformAction(action, withSender: sender)
    }
}
