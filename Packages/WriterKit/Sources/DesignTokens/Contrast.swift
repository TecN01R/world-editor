import Foundation

/// How well text stands out from what is behind it, measured so the look's legibility is a
/// test and not a judgement by eye. The token tests use it, and so should any new tone before
/// it ships.
public enum Contrast {
    /// APCA's lightness contrast (Lc) of `text` on a solid `background`: the measure the text
    /// tones' floors are set in. It is signed, negative for light text on dark as this look's
    /// always is, so compare its size. A see-through text tone is measured as drawn on that
    /// background.
    public static func lc(text: Tone, on background: Tone) -> Double {
        let textY = screenLuminance(text.over(background)), backgroundY = screenLuminance(background)
        guard abs(backgroundY - textY) >= APCA.deltaYmin else { return 0 }
        if backgroundY > textY {   // dark text on light
            let contrast = (pow(backgroundY, APCA.normBG) - pow(textY, APCA.normTXT)) * APCA.scale
            return contrast < APCA.loClip ? 0 : (contrast - APCA.loOffset) * 100
        } else {                   // light text on dark
            let contrast = (pow(backgroundY, APCA.revBG) - pow(textY, APCA.revTXT)) * APCA.scale
            return contrast > -APCA.loClip ? 0 : (contrast + APCA.loOffset) * 100
        }
    }

    /// WCAG 2's contrast ratio of `text` on a solid `background`, from 1 (none) to 21: for
    /// reference beside `lc`, since guidelines and audits still quote it. It is the same
    /// whichever of the two is lighter.
    public static func wcagRatio(text: Tone, on background: Tone) -> Double {
        let textL = relativeLuminance(text.over(background)), backgroundL = relativeLuminance(background)
        return (max(textL, backgroundL) + 0.05) / (min(textL, backgroundL) + 0.05)
    }

    /// The constants of APCA-W3 0.0.98G-4g, named as its reference implementation names them
    /// (which keeps a scale and an offset for each polarity; the two are equal).
    private enum APCA {
        static let mainTRC = 2.4
        static let sRco = 0.2126729, sGco = 0.7151522, sBco = 0.0721750
        static let normBG = 0.56, normTXT = 0.57, revTXT = 0.62, revBG = 0.65
        static let blkThrs = 0.022, blkClmp = 1.414
        static let scale = 1.14, loOffset = 0.027, loClip = 0.1, deltaYmin = 0.0005
    }

    /// APCA's luminance (Y) of a solid tone as a screen shows it, soft-clamped near black.
    private static func screenLuminance(_ tone: Tone) -> Double {
        func linear(_ part: UInt8) -> Double { pow(Double(part) / 255, APCA.mainTRC) }
        let y = APCA.sRco * linear(tone.red) + APCA.sGco * linear(tone.green) + APCA.sBco * linear(tone.blue)
        return y > APCA.blkThrs ? y : y + pow(APCA.blkThrs - y, APCA.blkClmp)
    }

    /// WCAG 2's relative luminance of a solid tone.
    private static func relativeLuminance(_ tone: Tone) -> Double {
        func linear(_ part: UInt8) -> Double {
            let value = Double(part) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(tone.red) + 0.7152 * linear(tone.green) + 0.0722 * linear(tone.blue)
    }
}
