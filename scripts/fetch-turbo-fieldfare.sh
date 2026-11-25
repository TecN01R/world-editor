#!/usr/bin/env bash
# Puts TurboFieldfare (Apache-2.0, github.com/drumih/turbo-fieldfare), the engine
# that runs Gemma 4 26B (on trial in debug builds, TurboModel), in
# Vendor/turbo-fieldfare at a pinned commit, for Package.swift. Two changes, below:
# one line is added to its manifest, as its installer (the TurboFieldfareRepackCore
# target, which downloads the model and repacks it on the phone) is a target there
# but not a library product, and a package can use only another's products; and its
# installer's free-space check counts what iOS can clear. Nothing else is changed.
set -euo pipefail
commit=f24e598528b19331eca79d79e7c5150832362bb7   # release 0.10.1
dir=Vendor/turbo-fieldfare
cd "$(dirname "$0")/.."
if [ ! -d "$dir/.git" ] || [ "$(git -C "$dir" rev-parse HEAD)" != "$commit" ]; then
    rm -rf "$dir"
    git init --quiet "$dir"
    git -C "$dir" fetch --quiet --depth 1 https://github.com/drumih/turbo-fieldfare "$commit"
    git -C "$dir" checkout --quiet --detach FETCH_HEAD
fi
has_installer() { grep -q '"TurboFieldfareRepackCore", targets' "$dir/Package.swift"; }
has_installer ||
    perl -pi -e 's/^(\s*)(\.library\(name: "TurboFieldfare", targets: \["TurboFieldfare"\]\),)$/$1$2\n$1.library(name: "TurboFieldfareRepackCore", targets: ["TurboFieldfareRepackCore"]),/' "$dir/Package.swift"
has_installer || { echo "Couldn't add the installer's product to $dir/Package.swift" >&2; exit 1; }
# And its installer's free-space check counts space iOS can clear for something the author
# asked for, as Apple advises for a download (volumeAvailableCapacityForImportantUsage, which
# TurboFieldfare's own app shows and the companion checks first), not only what's empty now
# (statfs): Kevin's phone, with 70 GB free in Settings, had 6.8 GB empty (2026-11-25).
checker="$dir/Sources/TurboFieldfareRepack/Core/System/DiskSpaceChecker.swift"
counts_clearable() { grep -q 'volumeAvailableCapacityForImportantUsage' "$checker"; }
counts_clearable ||
    perl -pi -e 's/^(\s*)let available = UInt64\(st\.f_bavail\) \* UInt64\(st\.f_bsize\)$/$1let available = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])\n$1    .volumeAvailableCapacityForImportantUsage).map { UInt64(max(\$0, 0)) } ?? UInt64(st.f_bavail) * UInt64(st.f_bsize)/' "$checker"
counts_clearable || { echo "Couldn't change the installer's free-space check in $checker" >&2; exit 1; }
