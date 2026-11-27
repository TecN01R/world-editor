/// One of the few ways text is set: a face, a weight, a size and line height, and the Dynamic
/// Type style it grows with. Numbers only, so the scale is tested on Linux; the app makes the
/// font from them, and no screen sets a size of its own.
public struct TextRole: Hashable, Sendable {
    /// Whose words they are decides the face. New York is set about 1.12 times the size of the
    /// San Francisco beside it, so the two look one size.
    public enum Face: Sendable {
        /// The author's words, wherever they show.
        case newYork
        /// The app's own words.
        case sanFrancisco
    }

    /// How heavily the face is set.
    public enum Weight: Sendable {
        /// Text to read.
        case regular
        /// A name or a heading.
        case semibold
        /// A page's title.
        case bold
    }

    /// The Dynamic Type text style a role grows and shrinks with, as iOS names them. Only the
    /// five in use: there is no caption.
    public enum TextStyle: Sendable {
        /// A page's title.
        case title1
        /// Names and headings.
        case headline
        /// Text to read.
        case body
        /// Labels, values and preview lines.
        case subheadline
        /// Notes.
        case footnote
    }

    /// Which family the app sets the role in.
    public let face: Face
    /// Which weight of it.
    public let weight: Weight
    /// The point size at iOS's default text size, before Dynamic Type scales it.
    public let size: Double
    /// Baseline to baseline in points at `size`, scaling with it. `nil` for the page's writing,
    /// whose line height follows its column (`Reading.lineHeight`).
    public let lineHeight: Double?
    /// The text style whose Dynamic Type scaling the role follows.
    public let scalesAs: TextStyle

    init(_ face: Face, _ weight: Weight, _ size: Double, line lineHeight: Double?, as scalesAs: TextStyle) {
        self.face = face
        self.weight = weight
        self.size = size
        self.lineHeight = lineHeight
        self.scalesAs = scalesAs
    }
}

extension TextRole {
    /// The author's words, as `TextRole.words.title`.
    public static let words = Words()

    /// The app's own words, as `TextRole.ui.label`.
    public static let ui = UI()

    /// The roles for what the author wrote, all New York.
    public struct Words: Sendable {
        /// A page's title, read or edited.
        public let title = TextRole(.newYork, .bold, 30, line: 36, as: .title1)
        /// A page's writing, and the author's messages. Its line height comes from the reading
        /// rules, by how long the lines are.
        public let body = TextRole(.newYork, .regular, 19, line: nil, as: .body)
        /// A page's name in a row or card.
        public let name = TextRole(.newYork, .semibold, 19, line: 24, as: .headline)
        /// A field's value, beside its name.
        public let value = TextRole(.newYork, .regular, 17, line: 22, as: .subheadline)
        /// A preview line or a quote under a name.
        public let line = TextRole(.newYork, .regular, 17, line: 22, as: .subheadline)
        /// A page's name in a note under a reply.
        public let chip = TextRole(.newYork, .regular, 15, line: 20, as: .footnote)
    }

    /// The roles for what the app says, all San Francisco, at iOS's own sizes.
    public struct UI: Sendable {
        /// The app's sentences.
        public let body = TextRole(.sanFrancisco, .regular, 17, line: 22, as: .body)
        /// The companion's replies: `body` with more room between lines, since they are read
        /// at length.
        public let reply = TextRole(.sanFrancisco, .regular, 17, line: 24, as: .body)
        /// A heading in scrolling content.
        public let heading = TextRole(.sanFrancisco, .semibold, 17, line: 22, as: .headline)
        /// A field's name, a page's kind, a date.
        public let label = TextRole(.sanFrancisco, .regular, 15, line: 20, as: .subheadline)
        /// Notes under replies: what was filed, looked up, thought.
        public let note = TextRole(.sanFrancisco, .regular, 13, line: 18, as: .footnote)
    }
}
