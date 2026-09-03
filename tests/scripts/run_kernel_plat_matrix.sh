#!/bin/bash
# Plat matrix: every TempleOS/RV QEMU -M board must smoke green.
# Policy: skips are not allowed — any SKIP line or non-zero smoke → matrix fail.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SMOKE="$SCRIPT_DIR/run_kernel_plat_smoke.sh"
failed=0
ran=0

# Real QEMU -M boards we ship defconfigs for. none/host are not matrix targets.
MACHINES=(
  virt
  sifive_u
  spike
  shakti_c
  sifive_e
  microchip_icicle
  xiangshan
  amd_microblaze_v
  opentitan
)

echo "=== kernel plat machine matrix ==="
for m in "${MACHINES[@]}"; do
  echo "--- $m ---"
  if out="$("$SMOKE" "$m" 2>&1)"; then
    if printf '%s\n' "$out" | grep -qE '^SKIP( |$)'; then
      printf '%s\n' "$out"
      echo "FAIL matrix ($m) — SKIP is not an allowed outcome" >&2
      failed=$((failed + 1))
    else
      printf '%s\n' "$out"
      ran=$((ran + 1))
    fi
  else
    printf '%s\n' "$out"
    failed=$((failed + 1))
  fi
done

echo "=== summary: ok=$ran fail=$failed ==="
# Restore virt for subsequent targets
make -C "$ROOT/templeos-riscv" defconfig-virt >/dev/null
[ "$failed" -eq 0 ]
