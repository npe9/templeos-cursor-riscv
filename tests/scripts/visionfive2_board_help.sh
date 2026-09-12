#!/bin/bash
# Print VisionFive 2 (JH7110) board bring-up recipe + QEMU harness status.
# Milk-V Mars is a sibling JH7110 board — separate defconfig.
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ELF="$ROOT/build/kernels/visionfive2/plat.elf"
BIN="$ROOT/build/kernels/visionfive2/plat.bin"
QEMU_ELF="$ROOT/build/kernels/visionfive2/plat-qemu.elf"

echo "=== VisionFive 2 (StarFive JH7110) ==="
echo "Defconfig: templeos-riscv/configs/visionfive2_defconfig"
echo "Link:      tests/exec/harness/link_visionfive2.ld @ 0x40200000 (board)"
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
  echo "Board artifact: $ELF ($(wc -c <"$ELF") bytes elf)"
  if [ -f "$BIN" ]; then
    echo "                $BIN ($(wc -c <"$BIN") bytes flat)"
  fi
else
  echo "Board artifact: missing — run: make kernel-visionfive2"
fi
if [ -f "$QEMU_ELF" ]; then
  echo "QEMU harness:   $QEMU_ELF ($(wc -c <"$QEMU_ELF") bytes)"
else
  echo "QEMU harness:   missing — run: make kernel-visionfive2 (builds plat-qemu.elf)"
fi
echo ""
echo "Build / smoke:"
echo "  make kernel-visionfive2"
echo "  make kernel-plat-visionfive2-smoke   # -M virt + plat-qemu.elf"
echo "  make -C templeos-riscv qemu-args-visionfive2"
echo ""
echo "QEMU harness (no native -M; UART/CLINT/PLIC bases match virt):"
echo "  qemu-system-riscv64 -M virt -m 128M -bios none \\"
echo "    -kernel build/kernels/visionfive2/plat-qemu.elf -nographic"
echo "  # plat-qemu: REG_SHIFT=0 + DRAM@0x80000000; board plat keeps shift=2"
echo "  # Expect: plat-smoke: PASS"
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
echo "Sibling: Milk-V Mars → make kernel-milkv-mars-help (own defconfig/ld; do not edit this one)."
