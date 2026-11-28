#if DEBUG
import SwiftUI
import UIKit

/// What CI measures of the page on screen in a scene (ci/check_ui.py, design-review rules 13,
/// 14 and 17): `scene-metrics.json` in the app's Documents, written with the scene's marker
/// (`SceneStage`). The page's title, its kind's line and its writing say where they are as they're
/// laid out (`report`, `sceneMeasuresKind`); what they are is read off them when it's written.
///
///     {"scene": "page-read", "title": {"x", "y", "width", "height"}, "kind": {…},
///      "writing": {"x", "y", "width", "height", "font", "line", "column", "lines", "full",
///                  "chars", "longest", "breaks"}}
///
/// Frames are in the window's points. Of the writing: its font's size and its line height in
/// points, the column's width, how many lines it's laid out in, how many of those are full (not
/// a paragraph's last), the median and the most characters on a full line, and the character
/// offset each line starts at, from TextKit 2's line fragments. What the screen doesn't show is
/// left out.
@MainActor
enum SceneMetrics {
    enum Part { case title, writing }

    private static weak var title: UIView?
    private static weak var writing: UITextView?
    /// The kind's line, in the window (SwiftUI's global space), while it's shown.
    private static var kind: CGRect?

    nonisolated static var file: URL { URL.documentsDirectory.appendingPathComponent("scene-metrics.json") }

    /// `view`, the page's title or its writing, read or edited, was laid out: it's the one measured.
    static func report(_ view: UITextView, as part: Part) {
        guard LaunchScene.current != nil else { return }
        switch part {
        case .title: title = view
        case .writing: writing = view
        }
    }

    fileprivate static func report(kind frame: CGRect?) {
        guard LaunchScene.current != nil else { return }
        kind = frame
    }

    /// Writes what's on screen now.
    static func write(scene: String) {
        var metrics: [String: Any] = ["scene": scene]
        if let title, title.window != nil, !title.isHidden { metrics["title"] = box(title.convert(title.bounds, to: nil)) }
        if let kind { metrics["kind"] = box(kind) }
        if let writing, writing.window != nil, !writing.isHidden, let measured = measure(writing) {
            metrics["writing"] = measured
        }
        guard let data = try? JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: file)
    }

    private static func box(_ rect: CGRect) -> [String: Any] {
        ["x": round2(rect.minX), "y": round2(rect.minY), "width": round2(rect.width), "height": round2(rect.height)]
    }

    private static func round2(_ value: CGFloat) -> Double { (Double(value) * 100).rounded() / 100 }

    /// The writing's place, type and lines.
    private static func measure(_ tv: UITextView) -> [String: Any]? {
        guard let layout = tv.textLayoutManager, tv.textStorage.length > 0, let container = layout.textContainer else { return nil }
        layout.ensureLayout(for: layout.documentRange)
        let inset = tv.textContainerInset
        let used = layout.usageBoundsForTextContainer.offsetBy(dx: inset.left, dy: inset.top)
        let font = tv.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        let style = tv.textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle

        var breaks: [Int] = [], full: [Int] = []
        let start = layout.documentRange.location
        layout.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let paragraph = layout.offset(from: start, to: fragment.rangeInElement.location)
            let text = ((fragment.textElement as? NSTextParagraph)?.attributedString.string ?? "") as NSString
            let lines = fragment.textLineFragments
            for (i, line) in lines.enumerated() {
                breaks.append(paragraph + line.characterRange.location)
                guard i < lines.count - 1, NSMaxRange(line.characterRange) <= text.length else { continue }   // a paragraph's last
                let words = text.substring(with: line.characterRange).trimmingCharacters(in: .whitespacesAndNewlines)
                full.append(words.count)
            }
            return true
        }
        full.sort()
        return box(tv.convert(used, to: nil)).merging([
            "font": round2(font?.pointSize ?? 0),
            "line": round2(style?.maximumLineHeight ?? 0),
            "column": round2(container.size.width - 2 * container.lineFragmentPadding),
            "lines": breaks.count,
            "full": full.count,
            "chars": full.isEmpty ? 0 : full[full.count / 2],
            "longest": full.last ?? 0,
            "breaks": breaks,
        ]) { $1 }
    }
}

extension View {
    /// The page's kind's line, measured where it's shown (`SceneMetrics`), in a scene.
    func sceneMeasuresKind() -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { SceneMetrics.report(kind: $0) }
            .onDisappear { SceneMetrics.report(kind: nil) }
    }
}
#endif
