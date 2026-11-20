#!/usr/bin/env python3
"""Print 'udid|name' for the simulators to screenshot: every foldable/Duo
device on the newest iOS runtime, plus the newest iPhone Pro and Pro Max."""
import json
import subprocess

data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
ios = {k: v for k, v in data["devices"].items() if ".iOS-" in k and v}
if not ios:
    raise SystemExit("no iOS simulator runtimes available")


def version(key):
    return tuple(int(p) for p in key.rsplit(".iOS-", 1)[1].split("-") if p.isdigit())


devices = ios[max(ios, key=version)]
iphones = [d for d in devices if d["name"].startswith("iPhone")]

picked = [d for d in iphones if any(w in d["name"] for w in ("Duo", "Fold", "Flip"))]
for suffix in ("Pro Max", "Pro"):
    candidates = [d for d in iphones if d["name"].endswith(suffix) and d not in picked]
    if candidates:
        picked.append(sorted(candidates, key=lambda d: d["name"])[-1])

for d in picked or iphones[:1]:
    print(f'{d["udid"]}|{d["name"]}')
