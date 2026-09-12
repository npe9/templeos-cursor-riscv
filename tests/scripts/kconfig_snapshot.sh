# shellcheck shell=bash
# Snapshot / restore the files templeos-riscv/scripts/kconfig.py generates.
#
# Several builds and smokes apply a foreign board's defconfig and then put the
# previous one back. kconfig.py is write-if-different, so a plain re-sync is now a
# true no-op — but an A→B→A round trip still rewrites the files twice, leaving
# byte-identical content with a moved mtime. Kernel/RVAutoConf.HH and the
# Kernel/Drv/RV*Selected.HH selects sit in generated AOT include graphs
# (build/aot/win/kernel.d), so that alone invalidated the win kernel unit and cost
# a ~20s recompile with nothing semantically changed.
#
# Source this, call kconfig_snapshot_begin before applying the foreign defconfig
# and kconfig_snapshot_end after restoring, so the tree is left exactly as found.
# Only files whose bytes match the snapshot get their mtime back, so a genuine
# config change still invalidates dependents.

KCONFIG_SNAPSHOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KCONFIG_SNAPSHOT_DIR=""

kconfig_snapshot_files() {
  local tos="$KCONFIG_SNAPSHOT_ROOT/templeos-riscv" f
  echo "$tos/.config"
  echo "$tos/include/generated/autoconf.h"
  echo "$tos/include/generated/kconfig.mk"
  echo "$KCONFIG_SNAPSHOT_ROOT/Kernel/RVAutoConf.HH"
  echo "$KCONFIG_SNAPSHOT_ROOT/bootstrap/seed/MemMapSelected.hc"
  echo "$KCONFIG_SNAPSHOT_ROOT/bootstrap/seed/RVEditorSelected.hc"
  for f in "$KCONFIG_SNAPSHOT_ROOT"/Kernel/Drv/RV*Selected.HH; do
    [ -f "$f" ] && echo "$f"
  done
  return 0
}

kconfig_snapshot_begin() {
  KCONFIG_SNAPSHOT_DIR="$(mktemp -d)"
  kconfig_snapshot_files | while IFS= read -r f; do
    [ -f "$f" ] && cp -p "$f" "$KCONFIG_SNAPSHOT_DIR/$(basename "$f")"
  done
  return 0
}

kconfig_snapshot_end() {
  [ -n "$KCONFIG_SNAPSHOT_DIR" ] && [ -d "$KCONFIG_SNAPSHOT_DIR" ] || return 0
  local s
  kconfig_snapshot_files | while IFS= read -r f; do
    s="$KCONFIG_SNAPSHOT_DIR/$(basename "$f")"
    if [ -f "$s" ] && [ -f "$f" ] && cmp -s "$s" "$f"; then
      touch -r "$s" "$f"
    fi
  done
  rm -rf "$KCONFIG_SNAPSHOT_DIR"
  KCONFIG_SNAPSHOT_DIR=""
  return 0
}
