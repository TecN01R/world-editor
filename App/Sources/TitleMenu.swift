import SwiftUI

/// A large title that opens a menu: what iOS's title menu does, at
/// large-title size. iOS attaches its own title menu only to the small,
/// inline title, so this draws the title at the large-title size (Dynamic
/// Type) with an arrow that shows it can be tapped, and opens a stock menu.
/// New York, like a page's title, so going into a page the title doesn't change.
struct TitleMenu<Items: View>: View {
    let title: String
    /// What the menu does, read by VoiceOver.
    let hint: String
    @ViewBuilder let items: () -> Items
    /// Read so a text-size change redraws the title at the new size.
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        Menu(content: items) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .foregroundStyle(Color(uiColor: PageEditor.ink))   // the writing's colour, as a page's title
                    .font(Font(PageEditor.titleFont))   // the very font a page's title uses, so they match exactly
                    .id(textSize)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .tint(.primary)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isHeader)
    }
}
