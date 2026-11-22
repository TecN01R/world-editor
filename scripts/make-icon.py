#!/usr/bin/env python3
# Draws the app icon (App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-{dark,light,tinted}.png):
# a New York W as large as fits, and an iOS-style caret after it. Needs Pillow and Apple's New York font
# (developer.apple.com/fonts; NewYorkExtraLarge-Bold.otf in ~/.cache/apple-fonts).
# Usage: scripts/make-icon.py <out.png> [dark|light|tinted]   (dark is the default)
import os, sys
from PIL import Image, ImageDraw, ImageFont
out = sys.argv[1]
mode = sys.argv[2] if len(sys.argv) > 2 else "dark"
S, margin, edge = 1024, 96, 64                 # canvas, side margin, caret clearance top and bottom
# Dark: paper-white W on near black. Light: near-black W on paper. Tinted: greyscale on
# transparent, for iOS to colour (the caret a shade darker so it still reads).
bg, ink, caret = {
    "dark": ((16, 16, 18, 255), (245, 242, 235, 255), (255, 159, 10, 255)),
    "light": ((245, 242, 235, 255), (20, 20, 22, 255), (255, 149, 0, 255)),
    "tinted": ((0, 0, 0, 0), (255, 255, 255, 255), (170, 170, 170, 255)),
}[mode]
path = os.path.expanduser("~/.cache/apple-fonts/NewYorkExtraLarge-Bold.otf")

def measure(size):
    f = ImageFont.truetype(path, size)
    l, t, r, b = f.getbbox("W")                # ink, relative to the text origin (top of ascent)
    advance = f.getlength("W")                  # where the caret goes after it, as in a text view
    return f, l, t, r, b, advance

bar_ratio = 0.028                               # caret width per point size: thin, like iOS's
gap_ratio = 0.04                                # clear of the W's serif (New York's W overhangs its advance)
# As large as fits: the W's ink plus the caret just past its advance spans the width between margins.
f, l, t, r, b, adv = measure(100)
span = max(adv, r + 100 * gap_ratio) + 100 * bar_ratio - l
size = int(100 * (S - 2 * margin) / span)
f, l, t, r, b, adv = measure(size)
bar = size * bar_ratio
ascent, descent = f.getmetrics()

img = Image.new("RGBA", (S, S), bg)
d = ImageDraw.Draw(img)
x = margin - l                                   # ink starts at the margin
y = (S - (b - t)) / 2 - t                        # the letter's ink centred, as Focus mode centres it
d.text((x, y), "W", font=f, fill=ink)
cx = x + max(adv, r + size * gap_ratio)          # the caret just after the W, full line height
top, bottom = max(edge, y), min(S - edge, y + ascent + descent)
d.rounded_rectangle([cx, top, cx + bar, bottom], radius=bar / 2, fill=caret)
img = img if mode == "tinted" else img.convert("RGB")
img.save(out)
print("size", size, "bar", round(bar, 1), "caret", round(top), round(bottom))
