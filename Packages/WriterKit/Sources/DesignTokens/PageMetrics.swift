/// A page from top to bottom, in points: one set whether the page is read or edited, so nothing
/// moves when Edit turns typing on. Each gap is a step of `Spacing`.
public enum PageMetrics {
    /// Above the title.
    public static let aboveTitle = 8.0
    /// From the title to the page's kind under it.
    public static let titleToKind = 8.0
    /// From the kind to the facts.
    public static let kindToFacts = 16.0
    /// The least a row of facts is tall, its name and its value centred on it: a touch target,
    /// since where the page is edited each of the two is tapped.
    public static let factRowMinHeight = Sizing.minimumTarget
    /// Between one row of facts and the next: nothing. Their own height parts them.
    public static let factRowSpacing = 0.0
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
