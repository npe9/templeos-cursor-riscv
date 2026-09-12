#!/usr/bin/env bash
# Pack build/compiler_rv.blob.bin → build/Compiler.BIN with CmpCtrl*/Wire exports.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAP="${1:-$ROOT/build/compiler_rv.map}"
BLOB="${2:-$ROOT/build/compiler_rv.blob.bin}"
OUT="${3:-$ROOT/build/Compiler.BIN}"
if [ ! -f "$BLOB" ] || [ ! -f "$MAP" ]; then
  echo "pack_compiler_bin: missing blob or map" >&2
  exit 1
fi
ARGS=()
while IFS= read -r line; do
  [ -n "$line" ] && ARGS+=("$line")
done < <("$ROOT/tools/compiler_bin_pack_exports.sh" "$MAP")
if [ "${#ARGS[@]}" -eq 0 ]; then
  exec "$ROOT/tools/pack_tosb" -v "$BLOB" "$OUT"
fi
exec "$ROOT/tools/pack_tosb" -v "${ARGS[@]}" "$BLOB" "$OUT"
