import UIKit
import WriterCore

/// Converts between the document model (text + style runs + paragraph kind)
/// and the attributed strings the text views edit. Bold and italic live in
/// font traits, so UIKit's own ⌘B/⌘I and Format menu stay in sync for free.
enum RichText {
    static func font(_ base: UIFont, _ style: InlineStyle) -> UIFont {
        var traits = base.fontDescriptor.symbolicTraits
        if style.contains(.bold) { traits.insert(.traitBold) } else { traits.remove(.traitBold) }
        if style.contains(.italic) { traits.insert(.traitItalic) } else { traits.remove(.traitItalic) }
        guard let d = base.fontDescriptor.withSymbolicTraits(traits) else { return base }
        return UIFont(descriptor: d, size: base.pointSize)
    }

    static func style(of font: UIFont?) -> InlineStyle {
        guard let traits = font?.fontDescriptor.symbolicTraits else { return [] }
        var style: InlineStyle = []
        if traits.contains(.traitBold) { style.insert(.bold) }
        if traits.contains(.traitItalic) { style.insert(.italic) }
        return style
    }

    /// The style of text with `attributes`: its font's weight and slant, and its lines.
    static func style(of attributes: [NSAttributedString.Key: Any]) -> InlineStyle {
        var style = style(of: attributes[.font] as? UIFont)
        if (attributes[.underlineStyle] as? Int ?? 0) != 0 { style.insert(.underline) }
        if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { style.insert(.strikethrough) }
        return style
    }

    /// The attributes that show `style` over the page's `base` font.
    static func attributes(_ style: InlineStyle, base: UIFont) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.font: font(base, style)]
        if style.contains(.underline) { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if style.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return attributes
    }

    /// `text` with `attributes`, each run styled and its `@` links marked.
    static func attributed(_ text: String, runs: [StyleRun], links: [PageLink] = [],
                           attributes: [NSAttributedString.Key: Any]) -> NSMutableAttributedString {
        let s = NSMutableAttributedString(string: text, attributes: attributes)
        if let base = attributes[.font] as? UIFont {
            for run in runs where run.location + run.length <= s.length {
                s.addAttributes(Self.attributes(run.style, base: base), range: NSRange(location: run.location, length: run.length))
            }
        }
        for link in links where link.location + link.length <= s.length {
            s.addAttribute(.link, value: url(link.page), range: NSRange(location: link.location, length: link.length))
        }
        return s
    }

    /// The paragraph as the text views show it.
    static func attributed(_ p: Paragraph, attributes: [NSAttributedString.Key: Any]) -> NSMutableAttributedString {
        attributed(p.text, runs: p.runs, links: p.links, attributes: attributes)
    }

    // MARK: @ links

    static func url(_ page: UUID) -> URL { URL(string: "world-editor://page/\(page.uuidString)")! }

    static func page(_ url: URL) -> UUID? {
        url.scheme == "world-editor" && url.host == "page" ? UUID(uuidString: url.lastPathComponent) : nil
    }

    /// Editing inside an `@` link, rather than typing beside it, turns the
    /// link back into plain `@text` so `@` can suggest again. Then makes the
    /// edit itself (undoably, through the text view) and returns true; returns
    /// false when no link was touched and the edit should go ahead as usual.
    static func unlinkIfEditing(_ tv: UITextView, range: NSRange, replacement text: String) -> Bool {
        let s = tv.textStorage
        guard s.length > 0 else { return false }
        let probe = min(max(0, range.location - (range.length == 0 ? 1 : 0)), s.length - 1)
        var link = NSRange()
        guard s.attribute(.link, at: probe, longestEffectiveRange: &link,
                          in: NSRange(location: 0, length: s.length)) != nil else { return false }
        let touches = range.length == 0
            ? range.location > link.location && range.location < NSMaxRange(link)             // typing inside
            : NSIntersectionRange(range, link).length > 0                                     // deleting part of it
                && !(range.location <= link.location && NSMaxRange(range) >= NSMaxRange(link))
        guard touches else { return false }
        var plain = s.attributes(at: link.location, effectiveRange: nil)
        plain[.link] = nil
        // The link's words, plain, with their "@" back: typed like any text, so Undo takes
        // it back too. (Replacing the whole link isn't an edit inside one, so this returns.)
        let words = (s.string as NSString).substring(with: link)
        tv.typingAttributes = plain
        guard let start = tv.position(from: tv.beginningOfDocument, offset: link.location),
              let end = tv.position(from: start, offset: link.length),
              let whole = tv.textRange(from: start, to: end) else { return false }
        tv.replace(whole, withText: "@" + words)
        // Then the edit itself, one character on where it's past the "@".
        tv.selectedRange = range.location >= link.location
            ? NSRange(location: range.location + 1, length: range.length)
            : NSRange(location: range.location, length: range.length + 1)   // began before the link: takes the "@" too
        tv.typingAttributes = plain
        if text.isEmpty { tv.deleteBackward() } else { tv.insertText(text) }
        return true
    }

    /// `@` links in `range`, relative to its start.
    static func links(in s: NSAttributedString, range: NSRange? = nil) -> [PageLink] {
        let range = range ?? NSRange(location: 0, length: s.length)
        var links: [PageLink] = []
        s.enumerateAttribute(.link, in: range) { value, r, _ in
            if let url = value as? URL, let page = page(url) {
                links.append(PageLink(location: r.location - range.location, length: r.length, page: page))
            }
        }
        return links
    }

    /// Style runs of `range`, relative to its start.
    static func runs(in s: NSAttributedString, range: NSRange? = nil) -> [StyleRun] {
        let range = range ?? NSRange(location: 0, length: s.length)
        var runs: [StyleRun] = []
        s.enumerateAttributes(in: range) { attributes, r, _ in
            let style = Self.style(of: attributes)
            guard !style.isEmpty else { return }
            let location = r.location - range.location
            // One run for a style however many other attributes (a link) split it.
            if let last = runs.last, last.style == style, last.location + last.length == location {
                runs[runs.count - 1].length += r.length
            } else {
                runs.append(StyleRun(location: location, length: r.length, style: style))
            }
        }
        return runs
    }

    // MARK: Lists

    // One shared list per kind: TextKit numbers consecutive paragraphs that
    // carry the same list, so separate runs restart at 1.
    static let bulletList = NSTextList(markerFormat: .disc, options: 0)
    static let numberedList = NSTextList(markerFormat: .decimal, options: 0)

    static func list(for kind: ParagraphKind) -> NSTextList? {
        switch kind {
        case .body: nil
        case .bullet: bulletList
        case .numbered: numberedList
        }
    }

    static func kind(of style: NSParagraphStyle?) -> ParagraphKind {
        guard let list = style?.textLists.last else { return .body }
        return list.markerFormat == .decimal ? .numbered : .bullet
    }

    /// The whole text view's content as paragraphs. The final line has no
    /// character to carry its paragraph style when empty, so `trailingKind`
    /// (the typing attributes' list) stands in for it.
    static func paragraphs(from s: NSAttributedString, trailingKind: ParagraphKind) -> [Paragraph] {
        let ns = s.string as NSString
        var result: [Paragraph] = []
        var location = 0
        while true {
            let end = ns.range(of: "\n", range: NSRange(location: location, length: ns.length - location)).location
            let lineEnd = end == NSNotFound ? ns.length : end
            let range = NSRange(location: location, length: lineEnd - location)
            let kind: ParagraphKind
            if location < ns.length {
                kind = Self.kind(of: s.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)
            } else {
                kind = trailingKind   // empty final line
            }
            result.append(Paragraph(text: ns.substring(with: range), kind: kind,
                                    runs: runs(in: s, range: range), links: links(in: s, range: range)))
            guard end != NSNotFound else { return result }
            location = end + 1
        }
    }
}
