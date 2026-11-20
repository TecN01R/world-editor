#!/usr/bin/env python3
"""Rebuild screenshots printed into a CI log: gh run view RUN --log | ci/extract_screenshots.py OUTDIR"""
import base64, os, re, sys

out = sys.argv[1] if len(sys.argv) > 1 else "screenshots"
os.makedirs(out, exist_ok=True)
name, buf = None, []
for line in sys.stdin:
    text = re.sub(r"^.*?\d{4}-\d\d-\d\dT[\d:.]+Z ", "", line.rstrip("\n"))
    if text.startswith("=====BEGIN-SCREENSHOT "):
        name, buf = text.split(" ", 1)[1].strip(), []
    elif text.startswith("=====END-SCREENSHOT") and name:
        with open(os.path.join(out, name), "wb") as f:
            f.write(base64.b64decode("".join(buf)))
        print(os.path.join(out, name))
        name = None
    elif name:
        buf.append(text.strip())
