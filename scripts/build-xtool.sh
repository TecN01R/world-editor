#!/usr/bin/env bash
# Builds World Editor's own xtool: upstream xtool plus scripts/xtool-world-editor.patch, which
# makes a free team ask Apple for the capabilities the companion needs and stock xtool drops:
# the increased memory limit (the WolkaraForever project's patch, used with thanks) and
# Background GPU Access (a reply runs on when the author leaves the app). Output:
# ~/.local/bin/xtool-world-editor, which scripts/run-on-phone.sh signs with when it's there.
#
#   scripts/build-xtool.sh     takes several GB of memory and disk; XTOOL_BUILD_JOBS (4) limits it
#
# Needs a Swift toolchain and the libimobiledevice, libplist and libusbmuxd development headers
# (pkg-config finds them, or XTOOL_DEVROOT points at -devel RPMs unpacked without root).
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
work=${XDG_CACHE_HOME:-$HOME/.cache}/world-editor-xtool
src=$work/src
base=9f7663744778d9b9449ab3fcee9170b0d1e55eaf   # the xtool commit the patch was made against

[ -d "$src/.git" ] || git clone -q https://github.com/xtool-org/xtool "$src"
git -C "$src" fetch -q origin "$base" 2>/dev/null || true
if ! git -C "$src" apply --reverse --check "$repo/scripts/xtool-world-editor.patch" 2>/dev/null; then
    git -C "$src" checkout -q -f "$base"
    git -C "$src" apply "$repo/scripts/xtool-world-editor.patch"
fi

devroot=${XTOOL_DEVROOT:-$HOME/Games/WolkaraForever/tools/devroot}
if ! pkg-config --exists libimobiledevice-1.0 libplist-2.0 libusbmuxd-2.0 2>/dev/null; then
    export PKG_CONFIG_PATH=$devroot/usr/lib64/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
fi

( cd "$src" && swift build -c release --product xtool -j "${XTOOL_BUILD_JOBS:-4}" )
mkdir -p "$HOME/.local/bin"
cp "$src/.build/release/xtool" "$HOME/.local/bin/xtool-world-editor"
echo "build-xtool: $HOME/.local/bin/xtool-world-editor"
