#!/bin/bash
# Print VisionFive 2 (JH7110) board bring-up recipe + build status.
# No QEMU -M. Milk-V Mars is a sibling JH7110 board — separate defconfig.
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ELF="$ROOT/build/kernels/visionfive2/plat.elf"
BIN="$ROOT/build/kernels/visionfive2/plat.bin"

echo "=== VisionFive 2 (StarFive JH7110) — board-only ==="
echo "Defconfig: templeos-riscv/configs/visionfive2_defconfig"
echo "Link:      tests/exec/harness/link_visionfive2.ld @ 0x40200000"
echo "OpenOCD:   tests/openocd/visionfive2_load_plat.tcl"
echo ""
echo "MMIO (shared JH7110 class — Mars sibling may reuse these numbers):"
echo "  UART0  0x10000000  DW8250 reg-shift=2  IRQ 32  115200 8N1"
echo "  CLINT  0x02000000  timebase 4 MHz"
echo "  PLIC   0x0C000000"
echo "  DDR    0x40000000+ (OpenSBI/U-Boot often reserve ..0x40200000)"
echo "  ENTRY  0x40200000"
echo "  FB     FB_PRESENT_SIMPLEFB; SIMPLEFB_BASE=0 until firmware XR24"
echo ""
if [ -f "$ELF" ]; then
  echo "Artifact: $ELF ($(wc -c <"$ELF") bytes elf)"
  if [ -f "$BIN" ]; then
    echo "          $BIN ($(wc -c <"$BIN") bytes flat)"
  fi
else
  echo "Artifact: missing — run: make kernel-visionfive2"
fi
echo ""
echo "Build:"
echo "  make kernel-visionfive2"
echo "  make -C templeos-riscv qemu-args-visionfive2   # BOARD-ONLY note"
echo ""
echo "U-Boot (UART0 already live):"
echo "  # Prefer ELF via tftp + bootelf, or flat bin + go:"
echo "  tftp \$loadaddr plat.bin"
echo "  go 0x40200000"
echo "  # Expect: plat-smoke: PASS"
echo ""
echo "OpenOCD / gdb (DDR already up):"
echo "  # source tests/openocd/visionfive2_load_plat.tcl"
echo "  # or: load_image $ELF 0x40200000 elf ; reg pc 0x40200000 ; resume"
echo ""
echo "Matrix: kept OUT until a green board/emulator smoke exists (not skip=OK)."
echo "Sibling: Milk-V Mars → make kernel-milkv-mars-help (own defconfig/ld; do not edit this one)."
