import Foundation
import PDFKit
import UniformTypeIdentifiers
import WriterCore

/// A file the author attaches to a message for the companion to read (`Documents`): its text,
/// read on the phone, a PDF's by iOS's own PDFKit, a text file's as it is.
enum AttachedFile {
    /// What can be attached: PDFs, plain text and Markdown.
    static let types: [UTType] = [.pdf, .plainText, .text] + [UTType(filenameExtension: "md")].compactMap { $0 }

    /// Why a file couldn't be attached, in words for the author.
    struct Unreadable: Error, LocalizedError {
        var name: String
        var errorDescription: String? {
            "\u{201C}\(name)\u{201D} has no text the companion can read. A scanned PDF has only pictures of its pages."
        }
    }

    /// The file at `url` (from the file picker, so outside the app's own folder), as text.
    static func read(_ url: URL) throws -> Conversation.Attached {
        let reachable = url.startAccessingSecurityScopedResource()
        defer { if reachable { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        let text: String
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
            text = PDFDocument(url: url)?.string ?? ""
        } else {
            text = try String(contentsOf: url, encoding: .utf8)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Unreadable(name: name) }
        return Conversation.Attached(name: name, text: trimmed)
    }
}
