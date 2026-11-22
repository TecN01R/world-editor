/// Focus mode's pages: one per paragraph, except that a run of empty
/// paragraphs (blank lines, kept for Edit mode's spacing) is one page.
public enum FocusPages {
    /// The paragraph each page starts at, given which paragraphs are empty.
    public static func starts(empty: [Bool]) -> [Int] {
        empty.indices.filter { $0 == 0 || !empty[$0] || !empty[$0 - 1] }
    }

    /// The page that paragraph `i` is on.
    public static func page(of i: Int, starts: [Int]) -> Int {
        starts.lastIndex { $0 <= i } ?? 0
    }
}
