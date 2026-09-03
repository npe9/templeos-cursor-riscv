# Milk-V Mars (JH7110) — OpenOCD load fragment (DDR already initialized).
#
# Prerequisites:
#   - SPL/U-Boot or vendor OpenOCD board cfg has brought up DDR
#   - JTAG attached; OpenOCD gdb_port / target already configured
#   - Built: make kernel-milkv-mars → build/kernels/milkv_mars/plat.elf
#
# Usage (after your interface/board cfg):
#   openocd -f interface/... -f target/... -f tests/openocd/milkv_mars_load_plat.tcl
# Or from an OpenOCD telnet/gdb monitor session:
#   source tests/openocd/milkv_mars_load_plat.tcl
#
# VisionFive 2 is the same JH7110 SoC class — use visionfive2_load_plat.tcl
# for that board; do not retarget this file.

set MARS_ENTRY 0x40200000
if {![info exists MARS_PLAT_ELF]} {
  set MARS_PLAT_ELF [file normalize [file join [file dirname [info script]] \
    ../.. build/kernels/milkv_mars/plat.elf]]
}

echo "MilkV-Mars: load $MARS_PLAT_ELF @ $MARS_ENTRY"
halt
load_image $MARS_PLAT_ELF $MARS_ENTRY elf
reg pc $MARS_ENTRY
echo "MilkV-Mars: pc=$MARS_ENTRY — resume; expect UART0 115200 plat-smoke: PASS"
# resume
