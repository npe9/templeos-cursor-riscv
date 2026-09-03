#!/bin/bash
# HolyC platform smoke: Kernel/Drv UART+CLINT via Kconfig (RVAutoConf.HH).
# Usage: run_kernel_plat_smoke.sh [virt|sifive_u|spike|…]
#
# Builds (or refreshes) build/kernels/<machine>/plat.elf via build_kernel_plat.sh,
# then loads it with matching QEMU -M / load mode.
#
# Policy: skips are not allowed. Missing QEMU / build failure / missing PASS → fail.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_SH="$SCRIPT_DIR/build_kernel_plat.sh"
MACHINE="${1:-virt}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

# Map friendly arg → defconfig + QEMU -M + load mode.
# load: kernel (-bios none -kernel ELF) | bios (-bios ELF) | loader (-device loader…)
#        | ot_kernel (opentitan: -kernel only, no -bios none)
DEFCONFIG=""
QEMU_M=""
LOAD="kernel"
# Space-separated extra argv (avoid empty-array + set -u on Bash 3.2 / macOS).
QEMU_EXTRA_STR="-bios none"
case "$MACHINE" in
  virt)
    DEFCONFIG=virt; QEMU_M=virt ;;
  sifive_u)
    DEFCONFIG=sifive_u; QEMU_M=sifive_u ;;
  spike)
    DEFCONFIG=spike; QEMU_M=spike ;;
  shakti_c)
    DEFCONFIG=shakti_c; QEMU_M=shakti_c; LOAD=bios; QEMU_EXTRA_STR="" ;;
  sifive_e)
    DEFCONFIG=sifive_e; QEMU_M=sifive_e ;;
  microchip_icicle|microchip-icicle-kit)
    DEFCONFIG=microchip_icicle; QEMU_M=microchip-icicle-kit; QEMU_EXTRA_STR="-bios none" ;;
  xiangshan|xiangshan-kunminghu)
    DEFCONFIG=xiangshan; QEMU_M=xiangshan-kunminghu; LOAD=bios; QEMU_EXTRA_STR="-smp 1" ;;
  amd_microblaze_v|amd-microblaze-v-generic)
    DEFCONFIG=amd_microblaze_v; QEMU_M=amd-microblaze-v-generic; LOAD=loader; QEMU_EXTRA_STR="" ;;
  opentitan)
    DEFCONFIG=opentitan; QEMU_M=opentitan; LOAD=ot_kernel; QEMU_EXTRA_STR=""
    QEMU="${QEMU_SYSTEM:-qemu-system-riscv32}" ;;
  visionfive2|visionfive-2|jh7110)
    echo "FAIL plat smoke (visionfive2) — board-only (no QEMU -M); use make kernel-visionfive2 + U-Boot/OpenOCD" >&2
    exit 1 ;;
  milkv_mars|milkv-mars|mars)
    echo "FAIL plat smoke (milkv_mars) — board-only (no QEMU -M); use make kernel-milkv-mars + U-Boot/OpenOCD" >&2
    exit 1 ;;
  none|host)
    echo "FAIL plat smoke ($MACHINE) — not a TempleOS/RV board target (excluded from matrix)" >&2
    exit 1 ;;
  *)
    echo "usage: $0 [virt|sifive_u|spike|shakti_c|sifive_e|microchip_icicle|xiangshan|amd_microblaze_v|opentitan]" >&2
    exit 2 ;;
esac

command -v "$QEMU" >/dev/null 2>&1 || { echo "FAIL plat smoke — missing $QEMU" >&2; exit 1; }

chmod +x "$BUILD_SH"
if ! out="$("$BUILD_SH" "$DEFCONFIG" 2>&1)"; then
  printf '%s\n' "$out" >&2
  exit 1
fi
# Build must never SKIP — treat leftover SKIP lines as failure.
if printf '%s\n' "$out" | grep -q '^SKIP '; then
  echo "FAIL plat smoke ($DEFCONFIG) — build printed SKIP (skips not allowed)" >&2
  printf '%s\n' "$out" >&2
  exit 1
fi
printf '%s\n' "$out"

ELF="$ROOT/build/kernels/$DEFCONFIG/plat.elf"
[ -f "$ELF" ] || { echo "FAIL plat smoke — missing $ELF" >&2; exit 1; }

# shellcheck disable=SC2086
case "$LOAD" in
  bios)
    out="$($TIMEOUT 20 "$QEMU" -M "$QEMU_M" $QEMU_EXTRA_STR -bios "$ELF" -nographic </dev/null 2>&1 | tr -d '\r')" ;;
  loader)
    out="$($TIMEOUT 20 "$QEMU" -M "$QEMU_M" $QEMU_EXTRA_STR -device "loader,file=$ELF,cpu-num=0" -nographic </dev/null 2>&1 | tr -d '\r')" ;;
  ot_kernel)
    # OpenTitan rejects -bios none as a filename; -kernel loads flash @ ENTRY.
    out="$($TIMEOUT 20 "$QEMU" -M "$QEMU_M" $QEMU_EXTRA_STR -kernel "$ELF" -nographic </dev/null 2>&1 | tr -d '\r')" ;;
  *)
    out="$($TIMEOUT 20 "$QEMU" -M "$QEMU_M" $QEMU_EXTRA_STR -kernel "$ELF" -nographic </dev/null 2>&1 | tr -d '\r')" ;;
esac
if printf '%s\n' "$out" | grep -qF "plat-smoke: PASS"; then
  echo "Plat smoke ($DEFCONFIG): OK"
  exit 0
fi
echo "FAIL plat smoke ($DEFCONFIG) — expected plat-smoke: PASS" >&2
printf '%s\n' "$out" | grep -v 'import unresolved' | head -25 | sed 's/^/  got: /' >&2
exit 1
