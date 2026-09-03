# StarFive VisionFive 2 — OpenOCD load fragment (DDR already initialized).
#
# Prerequisites:
#   - SPL/U-Boot or vendor OpenOCD board cfg has brought up DDR
#   - JTAG attached; OpenOCD gdb_port / target already configured
#   - Built: make kernel-visionfive2 → build/kernels/visionfive2/plat.elf
#
# Usage (after your interface/board cfg):
#   openocd -f interface/... -f target/... -f tests/openocd/visionfive2_load_plat.tcl
# Or from an OpenOCD telnet/gdb monitor session:
#   source tests/openocd/visionfive2_load_plat.tcl
#
# Milk-V Mars is the same JH7110 SoC class — use a separate mars OpenOCD
# fragment when that board port lands; do not retarget this file.

set VF2_ENTRY 0x40200000
if {![info exists VF2_PLAT_ELF]} {
  set VF2_PLAT_ELF [file normalize [file join [file dirname [info script]] \
    ../.. build/kernels/visionfive2/plat.elf]]
}

echo "VisionFive2: load $VF2_PLAT_ELF @ $VF2_ENTRY"
halt
load_image $VF2_PLAT_ELF $VF2_ENTRY elf
reg pc $VF2_ENTRY
echo "VisionFive2: pc=$VF2_ENTRY — resume; expect UART0 115200 plat-smoke: PASS"
# resume
