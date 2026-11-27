import SwiftUI

/// The world's name heading the drawer, opening a menu: what iOS's title menu does for an inline
/// title, which iOS gives no larger title. A heading, not a poster (Kevin, 2026-11-27, of it at a
/// page title's size, flush with the screen's edge: "The title bar and location feel off"): title
/// size, in New York (the world's name is the author's), on the rows' own left edge, with an arrow
/// that shows it can be tapped.
struct TitleMenu<Items: View>: View {
    let title: String
    /// What the menu does, read by VoiceOver.
    let hint: String
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu(content: items) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.authored(.title2).bold())
                    .foregroundStyle(Color(Look.ink))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tint(.primary)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isHeader)
    }
}
