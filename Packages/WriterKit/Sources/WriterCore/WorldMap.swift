import Foundation

/// The author's world as a web of connections that grows around them (Kevin, 2026-11-27: "I don't
/// want to feel like I'm using Bear or Obsidian or a Wiki I want to feel like my world is growing
/// itself and I'm uncovering it"), as Outer Wilds' ship log maps discoveries "by how they point to
/// each other": a card for each page, a line between pages that point to each other (a field
/// holding the other, an `@` link, or the other's name in its writing), and how much is known of
/// each, so a page that's only been named shows faint, like a rumour, until it's talked about.
/// Cards keep their places as the world grows (`placed`): a new one goes beside what it's linked
/// to, in the nearest free place. The app calls it Connections.
public struct WorldMap: Equatable, Sendable {
    /// A card's place on a grid, in whole steps (the view sets how far apart they are).
    public struct Place: Codable, Hashable, Sendable {
        public var x: Int
        public var y: Int
        public init(x: Int, y: Int) { self.x = x; self.y = y }
    }

    public struct Card: Identifiable, Equatable, Sendable {
        public var id: UUID
        public var title: String
        /// Its type's name (Character, Place…), if it has one.
        public var kind: String?
        /// How much is known of it: its paragraphs of writing and filled fields. None: a rumour,
        /// a name only.
        public var known: Int
        public var place: Place
        public var isRumour: Bool { known == 0 }
    }

    public var cards: [Card]
    /// Each pair of linked cards, once.
    public var lines: [Set<UUID>]

    /// The world of `pages` (Recently Deleted and blank pages left out), its types from `schema`,
    /// with the cards shown before kept where they were (`placed`).
    public init(pages: [Document], schema: Schema, placed: [UUID: Place] = [:]) {
        let live = pages.filter { $0.deleted == nil && !($0.heading.isEmpty && $0.isEmpty) }
        let ids = Set(live.map(\.id))

        var lines = Set<Set<UUID>>()
        for page in live {
            var targets = Set<UUID>()
            for case .page(let id) in schema.fields(of: schema.type(page.type)).compactMap({ page.values[$0.id] }) {
                targets.insert(id)
            }
            for paragraph in page.paragraphs { targets.formUnion(paragraph.links.map(\.page)) }
            let writing = page.paragraphs.map(\.text).joined(separator: "\n")
            for other in live where other.id != page.id && Self.names(other.heading, in: writing) {
                targets.insert(other.id)
            }
            for target in targets where target != page.id && ids.contains(target) { lines.insert([page.id, target]) }
        }
        // In a fixed order, so the same world always gives the same lines.
        func order(_ line: Set<UUID>) -> String { line.map(\.uuidString).sorted().joined() }
        self.lines = lines.sorted { order($0) < order($1) }

        // Places: the ones kept, then each new card, oldest first (pages are newest first), beside
        // the cards it's linked to that already have a place, or beside the last one placed.
        func mean(_ values: [Int]) -> Int { Int((Double(values.reduce(0, +)) / Double(values.count)).rounded()) }
        var places = placed.filter { ids.contains($0.key) }
        var taken = Set(places.values)
        // The rightmost card kept (then lowest), so an unlinked card goes in the same place each time.
        var last = places.values.max { ($0.x, $0.y) < ($1.x, $1.y) }
        for page in live.reversed() where places[page.id] == nil {
            let near = self.lines.filter { $0.contains(page.id) }.flatMap { $0.subtracting([page.id]) }
                .compactMap { places[$0] }
            let target: Place
            if near.isEmpty {
                target = last.map { Place(x: $0.x + 1, y: $0.y) } ?? Place(x: 0, y: 0)
            } else {
                target = Place(x: mean(near.map(\.x)), y: mean(near.map(\.y)))
            }
            let place = Self.free(near: target, taken: taken)
            places[page.id] = place
            taken.insert(place)
            last = place
        }

        cards = live.map { page in
            let type = schema.type(page.type)
            let filled = schema.fields(of: type).filter { page.values[$0.id] != nil }.count
            let written = page.paragraphs.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.count
            return Card(id: page.id, title: page.heading, kind: type?.name,
                        known: written + filled, place: places[page.id]!)
        }
    }

    /// Every card's place, to keep for next time.
    public var places: [UUID: Place] {
        Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0.place) })
    }

    /// The free place nearest `target`, looking in widening rings around it.
    static func free(near target: Place, taken: Set<Place>) -> Place {
        if !taken.contains(target) { return target }
        func distance(_ p: Place) -> Int {
            let dx = p.x - target.x, dy = p.y - target.y
            return dx * dx + dy * dy
        }
        for ring in 1... {
            var around: [Place] = []
            for dx in -ring...ring {
                for dy in -ring...ring where max(abs(dx), abs(dy)) == ring {
                    around.append(Place(x: target.x + dx, y: target.y + dy))
                }
            }
            around.sort { distance($0) < distance($1) }
            if let place = around.first(where: { !taken.contains($0) }) { return place }
        }
        return target
    }

    /// Whether `writing` names `title` as a wiki entry links it (`WikiEntry.ranges(naming:in:)`):
    /// as whole words, ignoring case and accents, and never a name under three letters.
    static func names(_ title: String, in writing: String) -> Bool {
        !WikiEntry.ranges(naming: title, in: writing).isEmpty
    }
}
