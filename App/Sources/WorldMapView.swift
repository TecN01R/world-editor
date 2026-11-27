import SwiftUI
import WriterCore

/// Connections: the author's world as a web that grows around them (`WorldMap`; Kevin,
/// 2026-11-27: "I want to feel like my world is growing itself and I'm uncovering it"): a card for
/// each page, faint and dashed while it's only been named, like a rumour; lines between pages that
/// point to each other; what the companion has added that the author hasn't opened yet glowing,
/// and growing in as Connections opens. It opens on what's newest. Tapping a card opens its page.
/// Called Connections, not a map: it isn't geography (Kevin, 2026-11-27, of a map: "I'd have to
/// know the geology and geography of the world and I don't yet").
struct WorldMapView: View {
    @Environment(Library.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Opens a page.
    let open: (UUID) -> Void
    @State private var map: WorldMap?
    /// New cards whose arrival has been shown since Connections opened.
    @State private var arrived: Set<UUID> = []
    @ScaledMetric(relativeTo: .headline) private var cardWidth: CGFloat = 156
    @ScaledMetric(relativeTo: .headline) private var cardHeight: CGFloat = 84
    @ScaledMetric(relativeTo: .headline) private var gap: CGFloat = 28
    private let margin: CGFloat = 120

    var body: some View {
        Group {
            if let map, !map.cards.isEmpty {
                canvas(map)
            } else {
                ContentUnavailableView("Connections", systemImage: "point.3.connected.trianglepath.dotted",
                                       description: Text("Talk about your world in the conversation. What you mention appears here, joined to what it's linked to."))
            }
        }
        .lookBackground()
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: library.pages) {
            let new = WorldMap(pages: library.pages, schema: library.schema, placed: library.mapPlaces)
            map = new
            library.mapPlaces = new.places   // so cards keep their places next time
        }
    }

    private func canvas(_ map: WorldMap) -> some View {
        let xs = map.cards.map(\.place.x), ys = map.cards.map(\.place.y)
        let (minX, minY) = (xs.min() ?? 0, ys.min() ?? 0)
        let step = CGSize(width: cardWidth + gap, height: cardHeight + gap)
        let size = CGSize(width: CGFloat((xs.max() ?? 0) - minX) * step.width + cardWidth + margin * 2,
                          height: CGFloat((ys.max() ?? 0) - minY) * step.height + cardHeight + margin * 2)
        let centres = Dictionary(uniqueKeysWithValues: map.cards.map { card in
            (card.id, CGPoint(x: margin + cardWidth / 2 + CGFloat(card.place.x - minX) * step.width,
                              y: margin + cardHeight / 2 + CGFloat(card.place.y - minY) * step.height))
        })
        let focus = newest(in: map).flatMap { centres[$0] }
        return ZoomingScroll(size: size, focus: focus) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for line in map.lines {
                        let ends = line.compactMap { centres[$0] }
                        guard ends.count == 2 else { continue }
                        var path = Path()
                        path.move(to: ends[0])
                        path.addLine(to: ends[1])
                        context.stroke(path, with: .color(Color(Look.ink).opacity(0.18)), lineWidth: 1.5)
                    }
                }
                .accessibilityHidden(true)   // the cards say what they're linked to by being there
                ForEach(map.cards) { card in
                    cardView(card).position(centres[card.id] ?? .zero)
                }
            }
            .frame(width: size.width, height: size.height)
            .environment(library)
        }
    }

    /// What Connections opens on: the newest thing the companion added, else the page last changed.
    private func newest(in map: WorldMap) -> UUID? {
        let onMap = Set(map.cards.map(\.id))
        let recent = library.pages.filter { onMap.contains($0.id) }.sorted { $0.modified > $1.modified }
        return recent.first { library.unseen.contains($0.id) }?.id ?? recent.first?.id
    }

    private func cardView(_ card: WorldMap.Card) -> some View {
        let title = card.title.isEmpty ? "Untitled" : card.title
        let new = library.unseen.contains(card.id)
        let shown = !new || reduceMotion || arrived.contains(card.id)
        let shape = RoundedRectangle(cornerRadius: 16)
        return Button { open(card.id) } label: {
            VStack(alignment: .leading, spacing: 3) {
                if let kind = card.kind {
                    Text(kind).font(.caption).foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.authored(card.isRumour ? .subheadline : .headline))
                    .foregroundStyle(Color(Look.ink).opacity(card.isRumour ? 0.65 : 1))
                    .lineLimit(2)
            }
            .padding(12)
            .frame(width: cardWidth, height: cardHeight, alignment: .leading)
            .background(card.isRumour ? Color.clear : Color(Look.raised), in: shape)
            .overlay {
                shape.strokeBorder(new ? Color(Look.emphasis) : Color(Look.ink).opacity(card.isRumour ? 0.35 : 0.08),
                                   style: StrokeStyle(lineWidth: new ? 1.5 : 1, dash: card.isRumour ? [4, 4] : []))
            }
            .shadow(color: new ? Color(Look.emphasis).opacity(0.25) : .clear, radius: 12)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        // A new card arrives once: it grows in and settles, a moment after Connections opens.
        .scaleEffect(shown ? 1 : 0.85)
        .opacity(shown ? 1 : 0)
        .onAppear {
            guard !shown else { return }
            withAnimation(.smooth(duration: 0.6).delay(0.3)) { _ = arrived.insert(card.id) }
        }
        .accessibilityLabel([title, card.kind,
                             card.isRumour ? "only mentioned so far" : nil, new ? "new" : nil]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Opens it")
    }
}
