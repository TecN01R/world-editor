import Foundation

/// The sizing rules of Focus mode, kept free of UIKit so they're tested on
/// Linux. The app supplies `fits`, which asks TextKit whether the paragraph
/// fits the page at a size.
public enum FocusFit {
    public static let minSize = 16.0, maxSize = 480.0

    /// The largest size (to half a point) at which the text fits, or `minSize`
    /// if even that doesn't.
    public static func largest(fits: (Double) -> Bool) -> Double {
        guard fits(minSize) else { return minSize }
        if fits(maxSize) { return maxSize }
        var lo = minSize, hi = maxSize
        while hi - lo > 0.5 {
            let mid = (lo + hi) / 2
            if fits(mid) { lo = mid } else { hi = mid }
        }
        return lo
    }

    /// While typing forward the text only grows for a clear win, so the page
    /// doesn't bounce as words wrap; otherwise it takes the best size.
    public static func settle(best: Double, current: Double, mayGrow: Bool) -> Double {
        if current == 0 || best < current || mayGrow || best >= current * 1.045 { return best }
        return current
    }
}
