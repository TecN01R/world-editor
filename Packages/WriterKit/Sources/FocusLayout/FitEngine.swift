import Foundation

/// Measures how a paragraph wraps at a given size. The app implements this
/// with TextKit using the exact font and text container the editor uses, so
/// the measurement and the editor can never disagree (the bug the web
/// prototype kept hitting).
public protocol TextMeasurer {
    /// Size of the laid-out text when wrapped to `width` at `fontSize`.
    /// `fitsWithoutBreakingWords` is false if a single word is wider than `width`.
    func measure(_ text: String, fontSize: Double, width: Double) -> Measurement
    /// Ink extents of the glyphs actually present, per point of font size.
    func ink(_ text: String) -> InkMetrics
}

public struct Measurement: Sendable, Equatable {
    public var width: Double
    public var height: Double        // sum of line boxes
    public var lineCount: Int
    public var fitsWithoutBreakingWords: Bool
    public init(width: Double, height: Double, lineCount: Int, fitsWithoutBreakingWords: Bool) {
        self.width = width; self.height = height
        self.lineCount = lineCount; self.fitsWithoutBreakingWords = fitsWithoutBreakingWords
    }
}

/// Per-point-size metrics. `ascent/descent` are the font's line metrics;
/// `inkAscent/inkDescent` are the tallest/deepest glyphs in this text.
public struct InkMetrics: Sendable, Equatable {
    public var ascent: Double, descent: Double
    public var inkAscent: Double, inkDescent: Double
    public init(ascent: Double, descent: Double, inkAscent: Double, inkDescent: Double) {
        self.ascent = ascent; self.descent = descent
        self.inkAscent = inkAscent; self.inkDescent = inkDescent
    }
}

/// Result of fitting one paragraph into one page.
public struct FitResult: Sendable, Equatable {
    public var fontSize: Double
    public var lineHeightMultiple: Double
    public var tracking: Double            // em
    public var blockSize: (width: Double, height: Double)
    /// How far the first line box extends above the visible ink (pulled in so
    /// the letters, not the line box, touch the top of the page).
    public var topOverhang: Double
    /// True when the paragraph doesn't fit even at the minimum size.
    public var overflows: Bool

    public static func == (a: FitResult, b: FitResult) -> Bool {
        a.fontSize == b.fontSize && a.lineHeightMultiple == b.lineHeightMultiple && a.tracking == b.tracking
            && a.blockSize.width == b.blockSize.width && a.blockSize.height == b.blockSize.height
            && a.topOverhang == b.topOverhang && a.overflows == b.overflows
    }
}

/// Focus mode's sizing rules, settled in the web prototype (see docs/focus-mode.md):
/// - discrete size steps (~2.2%) so changes read as deliberate, not jitter
/// - fit the ink, not the line boxes, at the top; the last line box stays
///   inside the page so the caret never reaches the keyboard
/// - never break words unless a single word can't fit at the minimum size
/// - while typing forward, only grow for a clear win (≥ ~4.5%)
public struct FitEngine: Sendable {
    public static let minSize = 16.0
    public static let ratio = 1.022
    public static let steps: [Double] = {
        var s = minSize, out: [Double] = []
        while s < 3000 { out.append((s * 10).rounded() / 10); s *= ratio }
        return out
    }()

    public var growThreshold = 1.045
    public var safeTop = 0.03, safeBottom = 0.05   // em; ink estimates are approximate

    public init() {}

    public static func lineHeight(for size: Double) -> Double { 1.36 - t(size) * 0.31 }
    public static func tracking(for size: Double) -> Double { -0.004 - t(size) * 0.022 }
    private static func t(_ s: Double) -> Double {
        min(1, max(0, (log(s) - log(22)) / (log(180) - log(22))))
    }

    /// - Parameters:
    ///   - held: the size currently on screen (0 if none)
    ///   - allowGrow: true after deletions, page changes or resizes
    public func fit(_ text: String, in area: (width: Double, height: Double),
                    measurer: TextMeasurer, held: Double = 0, allowGrow: Bool = true) -> FitResult {
        let sample = text.isEmpty ? "M" : text
        let ink = measurer.ink(sample)

        func geometry(_ s: Double) -> (top: Double, bottom: Double, m: Measurement) {
            let lh = Self.lineHeight(for: s) * s
            let half = (lh - (ink.ascent + ink.descent) * s) / 2
            let m = measurer.measure(sample, fontSize: s, width: area.width)
            let top = half + (ink.ascent - ink.inkAscent - safeTop) * s            // pull in
            let bottom = min(0, half + (ink.descent - ink.inkDescent - safeBottom) * s) // only overhanging ink
            return (top, bottom, m)
        }
        func fits(_ s: Double) -> Bool {
            if (ink.inkAscent + ink.inkDescent + safeTop + safeBottom) * s > area.height { return false }
            let g = geometry(s)
            return g.m.fitsWithoutBreakingWords && g.m.width <= area.width + 0.5
                && g.m.height - g.top - g.bottom <= area.height + 0.5
        }

        var lo = 0, hi = Self.steps.count - 1, best = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if fits(Self.steps[mid]) { best = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        let overflows = best < 0
        var k = max(0, best)
        if !allowGrow, held > 0, Self.steps[k] < held * growThreshold {
            while k > 0 && Self.steps[k] > held { k -= 1 }
        }
        let s = Self.steps[k]
        let g = geometry(s)
        return FitResult(fontSize: s,
                         lineHeightMultiple: Self.lineHeight(for: s),
                         tracking: Self.tracking(for: s),
                         blockSize: (g.m.width, g.m.height - max(0, g.top) - g.bottom),
                         topOverhang: max(0, g.top),
                         overflows: overflows)
    }

    /// Vertical offset that centres a block of `blockHeight` between `areaTop`
    /// and `areaBottom` (the keyboard), never closer than `margin` to either.
    public static func centredTop(blockHeight: Double, areaTop: Double, areaBottom: Double, margin: Double = 8) -> Double {
        let centred = (areaTop + areaBottom - blockHeight) / 2
        return min(max(centred, areaTop + margin), areaBottom - margin - blockHeight)
    }
}
