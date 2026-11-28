import SwiftUI
import DesignTokens

// Where a page's kind and facts sit under its title, the same read (`EntryView`) and edited
// (`PageFields`), so nothing moves when Edit turns typing on (docs/design.md, Reading). The
// numbers are `PageMetrics`'s. What is tapped where the page is edited is a touch target tall
// through the layout itself, with no touch areas reaching over one another.

extension PageMetrics {
    /// Above the writing where the kind's line is the last thing over it: `aboveWriting` from
    /// the line itself, less the room the line keeps under it (`pageKindLine`).
    static let kindLineToWriting = aboveWriting - kindToFacts
}

extension View {
    /// The page's kind in its place under the title: `titleToKind` above its line and
    /// `kindToFacts` under it. With them the line is a touch target tall, so where the kind is a
    /// menu (the page edited) all of that takes the touch and nothing moves to make room.
    func pageKindLine() -> some View {
        padding(.top, PageMetrics.titleToKind)
            .padding(.bottom, PageMetrics.kindToFacts)
            .frame(minHeight: Sizing.minimumTarget, alignment: .topLeading)
    }

    /// One side of a fact's row (its name or its value), or a control in one: at least a row
    /// tall (`PageMetrics.factRowMinHeight`, growing with the text size) and a touch target wide,
    /// the content at `alignment` in it. All of it takes the touch where it's a control's label.
    func inFactRow(alignment: Alignment = .leading) -> some View {
        modifier(FactRowSide(alignment: alignment))
    }
}

private struct FactRowSide: ViewModifier {
    let alignment: Alignment
    /// A row's height at this text size.
    @ScaledMetric private var height = PageMetrics.factRowMinHeight

    func body(content: Content) -> some View {
        content
            // Smaller text never makes a row less than a touch target.
            .frame(minWidth: Sizing.minimumTarget, minHeight: max(height, PageMetrics.factRowMinHeight),
                   alignment: alignment)
            .contentShape(.rect)
    }
}
