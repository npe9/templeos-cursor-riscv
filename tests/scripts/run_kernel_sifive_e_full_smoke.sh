#!/bin/bash
# FE310 / sifive_e fuller tiny-Kernel smoke: DTIM bootloader → XIP Kernel.
# Matrix keeps slim plat.elf. Expect boot banner (in_dtim) + fe310-full: PASS.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_SH="$SCRIPT_DIR/build_kernel_sifive_e_full.sh"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

command -v "$QEMU" >/dev/null 2>&1 || { echo "FAIL fe310-full smoke — missing $QEMU" >&2; exit 1; }

chmod +x "$BUILD_SH"
if ! out="$("$BUILD_SH" 2>&1)"; then
  printf '%s\n' "$out" >&2
  exit 1
fi
printf '%s\n' "$out"

ELF="$ROOT/build/kernels/sifive_e/kernel-fe310.elf"
[ -f "$ELF" ] || { echo "FAIL fe310-full smoke — missing $ELF" >&2; exit 1; }

out="$($TIMEOUT 20 "$QEMU" -M sifive_e -bios none -kernel "$ELF" -nographic </dev/null 2>&1 | tr -d '\r')"
ok=1
for needle in \
  "fe310-boot: in_dtim" \
  "fe310-full: uart_ok" \
  "fe310-full: clint_ok" \
  "fe310-full: sifive_api" \
  "fe310-full: sifive_plic_ok" \
  "fe310-full: plic_ok" \
  "RVMemMap (sifive_e)" \
  "fe310-full: memmap_drv_ok" \
  "fe310-full: PASS"
do
  if ! printf '%s\n' "$out" | grep -qF "$needle"; then
    echo "FAIL fe310-full smoke — missing: $needle" >&2
    ok=0
  fi
done
if [ "$ok" -eq 1 ]; then
  echo "FE310 full smoke: OK (DTIM bootloader → XIP Kernel)"
  exit 0
fi
printf '%s\n' "$out" | head -50 | sed 's/^/  got: /' >&2
exit 1
