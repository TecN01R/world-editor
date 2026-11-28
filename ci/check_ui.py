#!/usr/bin/env python3
"""Checks every rendered screen's accessibility tree against the rules of
docs/design-review.md that can be measured rather than judged by eye.

    ci/check_ui.py <trees>        <trees>/<pose>/<scene>.json, as ci/screenshots.sh saves them,
                                  and <scene>.metrics.json beside them where the scene shows a page

Prints one line per finding: "<pose>/<scene>: rule <n>: what, where". Exits 1 if there are
any. The rule numbers are docs/design-review.md's:

     3  text starts at the side margin and nothing is drawn off the screen
     9  every control is at least 44 pt in both directions
    10  every control has a VoiceOver label
    13  the writing's line height is what its measure calls for (docs/design.md, Reading)
    14  no full line of the writing over 68 characters; at the default text size 36 to 40 in a
        folded column, 60 to 66 in the full 627 pt one
    17  read and edited, a page's title and kind sit within 1 pt, and its lines break alike

Rules 13, 14 and 17 read what the app measured of the page (App/Sources/Scenes/SceneMetrics.swift);
a scene without those measurements is left out of them.

What iOS draws itself is left out: its bars' buttons (38 pt in the Duo's side column), the
keyboard, scroll bars, and the size of a stock switch or date picker (their rows are held
to 44 pt instead). A link inside a sentence is as tall as its line. A control inside a
labelled control (a menu's own button) is that control.
"""
import json
import pathlib
import sys

TARGET = 44
MARGIN = 20
CONTROLS = {"Button", "PopUpButton", "CheckBox", "Switch", "Link", "MenuButton", "Slider", "Stepper"}
INPUTS = {"TextField", "TextArea", "SecureTextField", "SearchField"}
TEXT = {"StaticText", "Heading"}
# iOS's own: drawn and sized by the system, whatever the app does.
SYSTEM_LABELS = {"Hide Sidebar", "Show Sidebar", "Typing Predictions"}
SYSTEM_GROUPS = {"Toolbar", "Tab Bar", "Typing Predictions", "Typing Predict"}
KEYBOARD_KEYS = {"space", "return", "shift", "delete", "numbers", "Dictate", "Emoji"}
# Stock controls whose own size iOS fixes.
STOCK_SIZED = {"CheckBox", "Switch", "Link"}
STOCK_SIZED_LABELS = {"Date Picker"}


def flatten(node, ancestors=(), out=None):
    """Every element with the labelled groups it sits inside."""
    out = [] if out is None else out
    if isinstance(node, list):
        for child in node:
            flatten(child, ancestors, out)
        return out
    out.append((node, ancestors))
    inside = ancestors + ((node.get("type"), node.get("AXLabel") or node.get("AXUniqueId") or ""),)
    for child in node.get("children") or []:
        flatten(child, inside, out)
    return out


def frame(e):
    f = e.get("frame") or {}
    return f.get("x", 0), f.get("y", 0), f.get("width", 0), f.get("height", 0)


def where(e):
    x, y, w, h = frame(e)
    return f"at {x:.0f},{y:.0f} size {w:.0f}×{h:.0f}"


def short(text):
    """One line of at most 60 characters, for a finding."""
    text = " ".join(str(text).split())
    return text if len(text) <= 60 else text[:59] + "…"


def name(e):
    return short(e.get("AXLabel") or e.get("title") or e.get("AXValue") or e.get("AXUniqueId") or "(no label)")


def check(tree):
    elements = flatten(tree)
    if not elements:
        return ["no elements"]
    # The root reports the screen in its natural pose; unfolded, the content is turned.
    _, _, width, height = frame(elements[0][0])
    reach = max((frame(e)[0] + frame(e)[2] for e, _ in elements[1:]), default=width)
    if reach > width * 1.2 and reach <= height + 1:
        width, height = height, width

    # The keyboard, when it's up: everything from its prediction bar down is iOS's.
    labels = {e.get("AXLabel") for e, _ in elements if e.get("type") == "Button"}
    keyboard_top = None
    if {"space", "return"} <= labels:
        keys = [frame(e)[1] for e, _ in elements if e.get("type") == "Button"
                and (e.get("AXLabel") in KEYBOARD_KEYS or len(e.get("AXLabel") or "") == 1) and frame(e)[3] > 0]
        keyboard_top = min(keys) - 60   # its row of predictions sits above the first row of keys

    def system(e, ancestors):
        if any(label in SYSTEM_GROUPS for _, label in ancestors) or e.get("AXLabel") in SYSTEM_LABELS:
            return True
        if (e.get("AXLabel") or "").lower().find("scroll bar") >= 0:
            return True
        return keyboard_top is not None and frame(e)[1] >= keyboard_top

    found = []
    labelled_frames = {tuple(round(v) for v in frame(e)) for e, _ in elements
                       if (e.get("AXLabel") or e.get("title")) and e.get("type") != "Group"}
    seen_targets = set()
    for e, ancestors in elements[1:]:
        kind = e.get("type")
        x, y, w, h = frame(e)
        if kind == "Group" or w <= 0 or h <= 0 or system(e, ancestors):
            continue
        if kind in CONTROLS and any(a in CONTROLS and label for a, label in ancestors):
            continue   # part of the labelled control it sits in
        rounded = tuple(round(v) for v in (x, y, w, h))
        labelled = bool(e.get("AXLabel") or e.get("title"))

        # Rule 3: on the screen, and text from the margin.
        if x < -1 or y < -1 or x + w > width + 1 or y + h > height + 1:
            found.append(f"rule 3: {kind} “{name(e)}” runs off the screen, {where(e)} (screen {width:.0f}×{height:.0f})")
        elif kind in TEXT and x < MARGIN - 0.5:
            found.append(f"rule 3: {kind} “{name(e)}” starts {x:.0f} pt from the edge, inside the {MARGIN} pt margin")

        # Rule 10: a label, on the control or on something drawn exactly over it.
        if kind in CONTROLS | INPUTS and not labelled and rounded not in labelled_frames:
            found.append(f"rule 10: {kind} without a label, {where(e)}" + (f" (value “{short(e.get('AXValue'))}”)" if e.get("AXValue") else ""))

        # Rule 9: big enough to touch. A control inside another of the same frame counts once.
        stock = kind in STOCK_SIZED or e.get("AXLabel") in STOCK_SIZED_LABELS
        if kind in CONTROLS and not stock and e.get("enabled", True) and rounded not in seen_targets:
            seen_targets.add(rounded)
            if w < TARGET - 0.5 or h < TARGET - 0.5:
                found.append(f"rule 9: {kind} “{name(e)}” is {w:.0f}×{h:.0f}, under {TARGET} pt, {where(e)}")
    return found


# docs/design.md, Reading: line height over type size, by the measure in em, a straight line between.
LEADING = [(12, 1.30), (16, 1.40), (24, 1.40), (28, 1.47)]
LEADING_TOLERANCE = 0.02
MOST_CHARS = 68
FOLDED_CHARS, FOLDED_COLUMN = (36, 40), 400   # columns narrower than this are the folded one
FULL_CHARS, FULL_COLUMN = (60, 66), 627
# Read and edited: the same page, compared for rule 17.
PAIRS = {"page-read": "page-edit", "page-read-chapter": "page-edit-chapter",
         "page-read-long-title": "page-edit-long-title"}
VARIANTS = ("-large", "-contrast")
WITHIN = 1


def leading(em):
    """The line height docs/design.md sets for a measure of `em`, over the type size."""
    if em <= LEADING[0][0]:
        return LEADING[0][1]
    for (a, low), (b, high) in zip(LEADING, LEADING[1:]):
        if em <= b:
            return low + (high - low) * (em - a) / (b - a)
    return LEADING[-1][1]


def variant(stem):
    """A shot's scene and variant: "page-read-large" is page-read, large."""
    for v in VARIANTS:
        if stem.endswith(v):
            return stem[:-len(v)], v
    return stem, ""


def check_writing(stem, metrics):
    """Rules 13 and 14, of the page's writing."""
    writing = metrics.get("writing")
    if not writing:
        return []
    found = []
    font, line, column = writing.get("font", 0), writing.get("line", 0), writing.get("column", 0)
    if font > 0 and column > 0:
        em, ratio = column / font, line / font
        want = leading(em)
        if abs(ratio - want) > LEADING_TOLERANCE:
            found.append(f"rule 13: the writing's lines are {line:g} pt, {ratio:.2f} times its {font:g} pt type, "
                         f"not {want:.2f} for its {em:.1f} em measure")
    longest, chars, full = writing.get("longest", 0), writing.get("chars", 0), writing.get("full", 0)
    if longest > MOST_CHARS:
        found.append(f"rule 14: a full line of the writing has {longest} characters, over {MOST_CHARS}")
    # The ranges hold at the default text size, on a page with lines enough to tell.
    if variant(stem)[1] != "-large" and full >= 3:
        if column < FOLDED_COLUMN:
            wanted = FOLDED_CHARS
        elif abs(column - FULL_COLUMN) <= WITHIN:
            wanted = FULL_CHARS
        else:
            wanted = None   # a column the ranges don't cover
        if wanted and not wanted[0] <= chars <= wanted[1]:
            found.append(f"rule 14: the writing's full lines have {chars} characters (median), not {wanted[0]} to "
                         f"{wanted[1]}, in its {column:g} pt column")
    return found


def check_pairs(measured):
    """Rule 17: each page read and edited, in one pose and variant. The writing's place down the
    page isn't compared: the editor has its Add Field or Add Type row, which reading hasn't."""
    found = []
    for stem, read in sorted(measured.items()):
        scene, v = variant(stem)
        if scene not in PAIRS:
            continue
        other = PAIRS[scene] + v
        edited = measured.get(other)
        if edited is None:
            continue
        a, b = read.get("title"), edited.get("title")
        if a and b and any(abs(a[k] - b[k]) > WITHIN for k in ("x", "y", "width", "height")):
            found.append((other, f"rule 17: the title is at {a['x']:g},{a['y']:g} size {a['width']:g}×{a['height']:g} "
                                 f"read ({stem}) and {b['x']:g},{b['y']:g} size {b['width']:g}×{b['height']:g} edited"))
        a, b = read.get("kind"), edited.get("kind")
        if a and b and abs(a["y"] - b["y"]) > WITHIN:
            found.append((other, f"rule 17: the kind's line starts at {a['y']:g} read ({stem}) and {b['y']:g} edited"))
        a, b = (read.get("writing") or {}).get("breaks"), (edited.get("writing") or {}).get("breaks")
        if a is not None and b is not None and a != b:
            at = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
            found.append((other, f"rule 17: the writing's lines break differently read ({stem}, {len(a)} lines) and "
                                 f"edited ({len(b)} lines), from line {at + 1}"))
    return found


def main(root):
    total = scenes = 0
    for path in sorted(p for p in pathlib.Path(root).glob("*/*.json") if not p.name.endswith(".metrics.json")):
        scenes += 1
        try:
            found = check(json.loads(path.read_text()))
        except (ValueError, KeyError, TypeError) as error:
            found = [f"tree unreadable: {error}"]
        for line in found:
            print(f"{path.parent.name}/{path.stem}: {line}")
        total += len(found)
    for pose in sorted(p for p in pathlib.Path(root).iterdir() if p.is_dir()):
        measured = {}
        for path in sorted(pose.glob("*.metrics.json")):
            stem = path.name[:-len(".metrics.json")]
            try:
                measured[stem] = json.loads(path.read_text())
                found = check_writing(stem, measured[stem])
            except (ValueError, KeyError, TypeError) as error:
                found = [f"measurements unreadable: {error}"]
            for line in found:
                print(f"{pose.name}/{stem}: {line}")
            total += len(found)
        try:
            pairs = check_pairs(measured)
        except (KeyError, TypeError) as error:
            pairs = [("(pairs)", f"measurements unreadable: {error}")]
        for stem, line in pairs:
            print(f"{pose.name}/{stem}: {line}")
        total += len(pairs)
    print(f"{total} findings in {scenes} screens")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "shots"))
