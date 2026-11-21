import UIKit

/// A text view whose pastes arrive as plain text in the current style, so
/// another app's fonts and colours (black text, invisible in dark mode) never
/// get in, and with no underline, which pages don't store.
class PlainPasteTextView: UITextView {
    override func paste(_ sender: Any?) {
        guard let text = UIPasteboard.general.string else { return super.paste(sender) }
        insertText(text)   // takes the typing attributes, goes through the delegate
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        action == #selector(toggleUnderline(_:)) ? false : super.canPerformAction(action, withSender: sender)
    }

    override func toggleUnderline(_ sender: Any?) {}
}
