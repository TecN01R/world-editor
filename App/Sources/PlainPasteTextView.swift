import UIKit
import WriterCore

/// A text view whose pastes arrive as plain text in the current style, so
/// another app's fonts and colours (black text, invisible in dark mode) never
/// get in, and with no underline, which pages don't store. `@` links survive
/// copy and paste within the app: they travel beside the text on the
/// pasteboard, so other apps still get ordinary text.
class PlainPasteTextView: UITextView {
    private static let linksType = "app.world-editor.links"

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
        guard let text = board.string else { return super.paste(sender) }
        insertText(text)   // takes the typing attributes, goes through the delegate
        guard let data = board.data(forPasteboardType: Self.linksType),
              let links = try? JSONDecoder().decode([PageLink].self, from: data), !links.isEmpty else { return }
        let start = selectedRange.location - text.utf16.count
        for link in links where link.location + link.length <= text.utf16.count {
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

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        action == #selector(toggleUnderline(_:)) ? false : super.canPerformAction(action, withSender: sender)
    }

    override func toggleUnderline(_ sender: Any?) {}
}
