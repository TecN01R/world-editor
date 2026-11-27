import Foundation

/// The steps of space between and around things, in points. Every screen takes its gaps from
/// these seven, each named for where it goes, so the same kind of gap is the same everywhere.
public enum Spacing {
    /// Between parts of one thing: a symbol and its word.
    public static let tight = 4.0
    /// Between things that go together: a title and the line under it.
    public static let gap = 8.0
    /// Between one row and the next.
    public static let row = 12.0
    /// Inside a raised surface, from its edge to what it holds.
    public static let inset = 16.0
    /// At the sides of every screen: the one margin.
    public static let margin = 20.0
    /// Between blocks of a screen: a page's facts and its writing.
    public static let block = 24.0
    /// Between sections, and at the foot of a page.
    public static let section = 32.0
}

/// How round a shape's corners are, in points. A shape inside another follows its curve.
public enum Radius {
    /// A chip: a page's name where it can be tapped.
    public static let chip = 12.0
    /// A card: a page in Connections.
    public static let card = 16.0
    /// A bubble: the author's message.
    public static let bubble = 20.0
}

/// The few fixed sizes shared parts are built to, in points.
public enum Sizing {
    /// The least a control measures each way, so a finger finds it: iOS's 44 pt.
    public static let minimumTarget = 44.0
    /// Across the dot on what's new.
    public static let dot = 8.0
    /// How thick a rule or border is drawn.
    public static let stroke = 1.0
}

/// How long things take to move, in seconds. With Reduce Motion on, the app fades instead.
public enum Motion {
    /// A small change: a control changing state.
    public static let quick: TimeInterval = 0.20
    /// A larger change: something opening, closing or moving.
    public static let standard: TimeInterval = 0.30
    /// Something arriving, such as the author's sentence landing in a page: slow enough to see.
    public static let arrival: TimeInterval = 0.60
    /// How long an arrival waits before it starts, so the screen has settled first.
    public static let arrivalDelay: TimeInterval = 0.30
}
