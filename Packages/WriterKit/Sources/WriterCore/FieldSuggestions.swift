import Foundation

/// A value the author's own writing gives an empty field, for them to accept
/// or ignore. Only from what they wrote: an `@` link to a page the field
/// takes, or one of the field's choices, named as a word. Never a guess: a
/// field with two candidate values, or a link two fields could take, gets
/// nothing.
public struct FieldSuggestion: Hashable, Sendable {
    public var field: UUID
    public var value: FieldValue
    /// The paragraph that says so, to show beside the suggestion.
    public var paragraph: UUID
}

extension Document {
    /// Suggestions for this page's empty fields, in the type's field order.
    /// `pageType` gives a linked page's type.
    public func fieldSuggestions(_ schema: Schema, pageType: (UUID) -> UUID?) -> [FieldSuggestion] {
        let empty = schema.fields(of: schema.type(type)).filter { values[$0.id] == nil }
        let pageFields = empty.filter { $0.kind == .page }
        var found: [UUID: [FieldSuggestion]] = [:]
        func add(_ field: FieldDefinition, _ value: FieldValue, _ paragraph: Paragraph) {
            found[field.id, default: []].append(FieldSuggestion(field: field.id, value: value, paragraph: paragraph.id))
        }
        for paragraph in paragraphs {
            for link in paragraph.links where link.page != id {
                let target = pageType(link.page)
                let takers = pageFields.filter { $0.pageType == nil || $0.pageType == target }
                if takers.count == 1 { add(takers[0], .page(link.page), paragraph) }
            }
            for field in empty where field.kind == .choice {
                for option in field.options where Self.names(option, in: paragraph.text) {
                    add(field, .text(option), paragraph)
                }
            }
        }
        return empty.compactMap { field in
            guard let candidates = found[field.id], Set(candidates.map(\.value)).count == 1 else { return nil }
            return candidates[0]
        }
    }

    /// Whether `text` has `word` as a whole word ("selkie", not "selkies"),
    /// ignoring case and accents.
    static func names(_ word: String, in text: String) -> Bool {
        guard !word.isEmpty else { return false }
        func joins(_ c: Character) -> Bool { c.isLetter || c.isNumber }
        var from = text.startIndex
        while let r = text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive], range: from..<text.endIndex) {
            let before = r.lowerBound == text.startIndex || !joins(text[text.index(before: r.lowerBound)])
            let after = r.upperBound == text.endIndex || !joins(text[r.upperBound])
            if before && after { return true }
            from = r.upperBound
        }
        return false
    }
}
