#!/bin/bash
# Fetch NASA's cFS sources for the translation work. Pinned by commit so a transcript recorded
# today can be reproduced: the differential oracle compares against THESE bytes, and an upstream
# move would change the reference without changing anything in this tree.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
V="$ROOT/vendor"
CFE_SHA="546a002515be5a1e3b66f9ae2c14f948d9cec76f"
PSP_SHA="53df1d54c3d29fd23832c59df1104de07a043af2"
OSAL_SHA="dad0ee99c121f2ecc11f8c0798c1e836e41d8ab1"
# The first cFS APP. Pinned on the dev branch for the same reason cFE is: cFE here is
# 7.0.1+dev, a day later than this commit, and MD's v7.0.1 tag predates both.
MD_SHA="65eb7b3b0aa8acd05076128a623cd696582b6d7c"
# The second cFS APP, and the OTHER memory app: MM pokes and dumps arbitrary memory where MD
# only reads it, so it needs the WRITE half of the simulated window MD established.
MM_SHA="0a767de5bbb6da05d7b5705e75221495aca444f9"
mkdir -p "$V"
fetch() {
  name="$1"; url="$2"; sha="$3"
  if [ -d "$V/$name/.git" ]; then
    have="$(cd "$V/$name" && git rev-parse HEAD)"
    [ "$have" = "$sha" ] && { echo "$name: already at $sha"; return; }
    echo "$name: at $have, want $sha — fetching"
  else
    git clone -q "$url" "$V/$name"
  fi
  ( cd "$V/$name" && git fetch -q origin "$sha" 2>/dev/null || git fetch -q origin; git checkout -q "$sha" )
  echo "$name: $sha"
}
fetch cFE  https://github.com/nasa/cFE.git  "$CFE_SHA"
fetch osal https://github.com/nasa/osal.git "$OSAL_SHA"
fetch PSP  https://github.com/nasa/PSP.git  "$PSP_SHA"
fetch MD   https://github.com/nasa/MD.git   "$MD_SHA"
fetch MM   https://github.com/nasa/MM.git   "$MM_SHA"
echo "vendor/shim is committed in this repo: it stands in for the headers CMake would generate."
