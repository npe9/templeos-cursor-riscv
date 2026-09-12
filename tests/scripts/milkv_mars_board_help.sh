#!/bin/bash
# Print Milk-V Mars (JH7110) board bring-up recipe + QEMU harness status.
# VisionFive 2 is the sibling — do not overwrite visionfive2_*.
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ELF="$ROOT/build/kernels/milkv_mars/plat.elf"
BIN="$ROOT/build/kernels/milkv_mars/plat.bin"
QEMU_ELF="$ROOT/build/kernels/milkv_mars/plat-qemu.elf"

echo "=== Milk-V Mars (StarFive JH7110) ==="
echo "Defconfig: templeos-riscv/configs/milkv_mars_defconfig"
echo "Link:      tests/exec/harness/link_milkv_mars.ld @ 0x40200000 (board)"
echo "OpenOCD:   tests/openocd/milkv_mars_load_plat.tcl"
echo ""
echo "MMIO (JH7110 class — same numbers as VisionFive 2):"
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
  echo "Board artifact: missing — run: make kernel-milkv-mars"
fi
if [ -f "$QEMU_ELF" ]; then
  echo "QEMU harness:   $QEMU_ELF ($(wc -c <"$QEMU_ELF") bytes)"
else
  echo "QEMU harness:   missing — run: make kernel-milkv-mars (builds plat-qemu.elf)"
fi
echo ""
echo "Build / smoke:"
echo "  make kernel-milkv-mars"
echo "  make kernel-plat-milkv-mars-smoke   # -M virt + plat-qemu.elf"
echo "  make -C templeos-riscv qemu-args-milkv_mars"
echo ""
echo "QEMU harness (no native -M; UART/CLINT/PLIC bases match virt):"
echo "  qemu-system-riscv64 -M virt -m 128M -bios none \\"
echo "    -kernel build/kernels/milkv_mars/plat-qemu.elf -nographic"
echo "  # plat-qemu: REG_SHIFT=0 + DRAM@0x80000000; board plat keeps shift=2"
echo "  # Expect: plat-smoke: PASS"
echo ""
echo "U-Boot / OpenOCD: same entry 0x40200000 as VisionFive 2"
echo "  tftp \$loadaddr plat.bin && go 0x40200000"
echo "  # source tests/openocd/milkv_mars_load_plat.tcl"
echo ""
echo "Sibling: VisionFive 2 → visionfive2_defconfig (do not overwrite from Mars)."
