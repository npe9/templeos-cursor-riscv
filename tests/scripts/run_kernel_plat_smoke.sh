#!/bin/bash
# HolyC platform smoke: Kernel/Drv UART+CLINT via Kconfig (RVAutoConf.HH).
# Usage: run_kernel_plat_smoke.sh [virt|sifive_u|spike|…]
#
# Builds (or refreshes) build/kernels/<machine>/plat.elf via build_kernel_plat.sh,
# then loads it with matching QEMU -M. Machines that cannot bare-boot print SKIP.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_SH="$SCRIPT_DIR/build_kernel_plat.sh"
MACHINE="${1:-virt}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

command -v "$QEMU" >/dev/null 2>&1 || { echo "SKIP plat smoke — missing $QEMU" >&2; exit 0; }

# Map friendly arg → defconfig stem + QEMU -M (+ SKIP reason for run).
DEFCONFIG=""
QEMU_M=""
QEMU_EXTRA=(-bios none)
case "$MACHINE" in
  virt)
    DEFCONFIG=virt; QEMU_M=virt ;;
  sifive_u)
    DEFCONFIG=sifive_u; QEMU_M=sifive_u ;;
  spike)
    DEFCONFIG=spike; QEMU_M=spike ;;
  shakti_c)
    echo "SKIP plat smoke (shakti_c) — Shakti UART @ 0x11300 has no HolyC driver (UART stub)" >&2
    exit 0 ;;
  sifive_e)
    echo "SKIP plat smoke (sifive_e) — DTIM ~16 KiB; TempleOS/RV image does not fit" >&2
    exit 0 ;;
  microchip_icicle|microchip-icicle-kit)
    echo "SKIP plat smoke (microchip-icicle-kit) — needs HSS firmware (hss.bin); bare -bios none fails" >&2
    exit 0 ;;
  xiangshan|xiangshan-kunminghu)
    echo "SKIP plat smoke (xiangshan-kunminghu) — tentative ACLINT/APLIC; 16550 regshift=2 RX unproven" >&2
    exit 0 ;;
  amd_microblaze_v|amd-microblaze-v-generic)
    echo "SKIP plat smoke (amd-microblaze-v-generic) — no CLINT; UARTLite primary / 16550 secondary only" >&2
    exit 0 ;;
  opentitan)
    echo "SKIP plat smoke (opentitan) — riscv32 + 128 KiB DRAM; Ibex UART stub; see RV32.md" >&2
    exit 0 ;;
  none)
    echo "SKIP plat smoke (none) — QEMU empty machine; no CPU/RAM/devices" >&2
    exit 0 ;;
  host)
    echo "SKIP plat smoke (host) — legacy stub; not in QEMU -M help" >&2
    exit 0 ;;
  *)
    echo "usage: $0 [virt|sifive_u|spike|shakti_c|sifive_e|microchip_icicle|xiangshan|amd_microblaze_v|opentitan|none|host]" >&2
    exit 2 ;;
esac

chmod +x "$BUILD_SH"
if ! out="$("$BUILD_SH" "$DEFCONFIG" 2>&1)"; then
  printf '%s\n' "$out" >&2
  exit 1
fi
# build script may SKIP (exit 0) for opentitan/none/host — treat as smoke SKIP
if printf '%s\n' "$out" | grep -q '^SKIP '; then
  printf '%s\n' "$out"
  exit 0
fi
printf '%s\n' "$out"

ELF="$ROOT/build/kernels/$DEFCONFIG/plat.elf"
[ -f "$ELF" ] || { echo "FAIL plat smoke — missing $ELF" >&2; exit 1; }

out="$($TIMEOUT 20 "$QEMU" -M "$QEMU_M" "${QEMU_EXTRA[@]}" -kernel "$ELF" -nographic </dev/null 2>&1 | tr -d '\r')"
if printf '%s\n' "$out" | grep -qF "plat-smoke: PASS"; then
  echo "Plat smoke ($DEFCONFIG): OK"
  exit 0
fi
echo "FAIL plat smoke ($DEFCONFIG) — expected plat-smoke: PASS" >&2
printf '%s\n' "$out" | grep -v 'import unresolved' | head -25 | sed 's/^/  got: /' >&2
exit 1
