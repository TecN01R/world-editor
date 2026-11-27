/// A page from top to bottom, in points: one set whether the page is read or edited, so nothing
/// moves when Edit turns typing on. Each is a step of `Spacing`.
public enum PageMetrics {
    /// Above the title.
    public static let aboveTitle = 8.0
    /// From the title to the page's kind under it.
    public static let titleToKind = 8.0
    /// From the kind to the facts.
    public static let kindToFacts = 16.0
    /// Between one row of facts and the next.
    public static let factRowSpacing = 12.0
    /// Between the facts' columns.
    public static let factColumnSpacing = 16.0
    /// Above the writing, after what heads the page.
    public static let aboveWriting = 24.0
    /// Before a heading in the writing, to part it from the section above.
    public static let beforeHeading = 32.0
    /// After a heading in the writing, to keep it with its own section.
    public static let afterHeading = 12.0
    /// Under the last line, at the bottom of the page.
    public static let bottom = 32.0
}
