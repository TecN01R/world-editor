#!/usr/bin/env python3
"""Checks every rendered screen's accessibility tree against the rules of
docs/design-review.md that can be measured rather than judged by eye.

    ci/check_ui.py <trees>        <trees>/<pose>/<scene>.json, as ci/screenshots.sh saves them

Prints one line per finding: "<pose>/<scene>: rule <n>: what, where". Exits 1 if there are
any. The rule numbers are docs/design-review.md's:

     3  text starts at the side margin and nothing is drawn off the screen
     9  every control is at least 44 pt in both directions
    10  every control has a VoiceOver label

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


def main(root):
    total = scenes = 0
    for path in sorted(pathlib.Path(root).glob("*/*.json")):
        scenes += 1
        try:
            found = check(json.loads(path.read_text()))
        except (ValueError, KeyError, TypeError) as error:
            found = [f"tree unreadable: {error}"]
        for line in found:
            print(f"{path.parent.name}/{path.stem}: {line}")
        total += len(found)
    print(f"{total} findings in {scenes} screens")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "shots"))
