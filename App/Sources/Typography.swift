import SwiftUI
import UIKit

// What the user writes is New York, wherever it's shown: their writing, page
// titles, the world's name, field values. The rest of the UI is San Francisco,
// type and field names included (CLAUDE.md, Conventions). Both scale with Dynamic Type.

extension Font {
    /// The user's own words (writing, titles, values) at a text style, in New York.
    static func authored(_ style: Font.TextStyle) -> Font {
        .system(style, design: .serif)
    }
}

extension UIFont {
    /// The user's own words at a text style, in New York.
    static func authored(_ style: UIFont.TextStyle) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        return UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: 0)
    }
}
