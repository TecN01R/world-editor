import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers
import Vision
import WriterCore

/// A file the author attaches to a message for the companion to read (`Documents`): its text,
/// read on the phone: a PDF's by iOS's own PDFKit, a text file's as it is, a rich-text or web
/// page's through iOS's own reading of them, and pictures of pages (a scanned PDF, a photo or
/// screenshot of a page, pages scanned with the camera) by iOS's own document reading (Vision)
/// (Kevin, 2026-11-26: "do pictures and document upload next").
enum AttachedFile {
    /// What can be attached: PDFs, text (plain, Markdown, rich text, web pages) and pictures of pages.
    static let types: [UTType] = [.pdf, .plainText, .text, .rtf, .html, .image]
        + [UTType(filenameExtension: "md")].compactMap { $0 }

    /// Why a file couldn't be attached, in words for the author.
    struct Unreadable: Error, LocalizedError {
        var name: String
        var errorDescription: String? {
            "\u{201C}\(name)\u{201D} has no text the companion can read."
        }
    }

    /// The file at `url` (from the file picker, so outside the app's own folder), as text.
    @MainActor static func read(_ url: URL) async throws -> Conversation.Attached {
        let reachable = url.startAccessingSecurityScopedResource()
        defer { if reachable { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        let text: String
        if type.conforms(to: .pdf) {
            text = try await pdf(url)
        } else if type.conforms(to: .image) {
            text = try await recognized(url)
        } else if type.conforms(to: .rtf) || type.conforms(to: .html) {
            // iOS's own reading of them (a web page's on the main thread, as WebKit's).
            let kind: NSAttributedString.DocumentType = type.conforms(to: .rtf) ? .rtf : .html
            text = try NSAttributedString(url: url, options: [.documentType: kind], documentAttributes: nil).string
        } else {
            text = try String(contentsOf: url, encoding: .utf8)
        }
        return try attached(name, text)
    }

    /// Pages scanned with the camera (`DocumentScanner`), as one attachment.
    static func scanned(_ pages: [CGImage], name: String) async throws -> Conversation.Attached {
        var texts: [String] = []
        for page in pages { texts.append(try await recognized(page)) }
        return try attached(name, texts.joined(separator: "\n\n"))
    }

    private static func attached(_ name: String, _ text: String) throws -> Conversation.Attached {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Unreadable(name: name) }
        return Conversation.Attached(name: name, text: trimmed)
    }

    /// A PDF's text; a scanned one's, which has only pictures of its pages, read from them.
    private static func pdf(_ url: URL) async throws -> String {
        guard let document = PDFDocument(url: url) else { return "" }
        let text = document.string ?? ""
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        var texts: [String] = []
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            // Drawn about as sharp as a phone's camera scan: 2,000 points on the longer side.
            let bounds = page.bounds(for: .mediaBox)
            let scale = 2000 / max(bounds.width, bounds.height, 1)
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            guard let image = page.thumbnail(of: size, for: .mediaBox).cgImage else { continue }
            texts.append(try await recognized(image))
        }
        return texts.joined(separator: "\n\n")
    }

    /// A picture of a page, read as a document: its paragraphs, in reading order.
    private static func recognized(_ url: URL) async throws -> String {
        transcript(try await RecognizeDocumentsRequest().perform(on: url, orientation: nil))
    }

    private static func recognized(_ image: CGImage) async throws -> String {
        transcript(try await RecognizeDocumentsRequest().perform(on: image, orientation: nil))
    }

    /// Each document found, as its paragraphs, or as its whole text when it has none.
    private static func transcript(_ observations: [DocumentObservation]) -> String {
        observations.map { observation in
            let paragraphs = observation.document.paragraphs.map(\.transcript)
            return paragraphs.isEmpty ? observation.document.text.transcript : paragraphs.joined(separator: "\n\n")
        }.joined(separator: "\n\n")
    }
}
