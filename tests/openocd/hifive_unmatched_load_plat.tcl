# SiFive HiFive Unmatched (FU740) — OpenOCD load fragment (DDR already initialized).
#
# Prerequisites:
#   - Board powered and stopped at the U-Boot prompt (SPL+OpenSBI have trained DDR).
#     Loading before DDR is up writes into nothing and the first fetch traps.
#   - JTAG attached on J18; the chain scans as a RISC-V TAP (see hifive_unmatched.cfg).
#   - Built: make kernel-hifive-unmatched -> build/kernels/hifive_unmatched/plat.elf
#
# Usage:
#   openocd -f tests/openocd/hifive_unmatched.cfg \
#           -f tests/openocd/hifive_unmatched_load_plat.tcl
# Or from a telnet/gdb monitor session:
#   source tests/openocd/hifive_unmatched_load_plat.tcl
#
# Watch UART0 on the CP2105 console at 115200 8N1 (the FIRST of the two ports the
# bridge presents) — expect "plat-smoke: PASS".

set UNMATCHED_ENTRY 0x80200000
if {![info exists UNMATCHED_PLAT_ELF]} {
  set UNMATCHED_PLAT_ELF [file normalize [file join [file dirname [info script]] \
    ../.. build/kernels/hifive_unmatched/plat.elf]]
}

echo "HiFive Unmatched: load $UNMATCHED_PLAT_ELF @ $UNMATCHED_ENTRY"
halt
load_image $UNMATCHED_PLAT_ELF $UNMATCHED_ENTRY elf
reg pc $UNMATCHED_ENTRY
echo "HiFive Unmatched: pc=$UNMATCHED_ENTRY — resume; expect UART0 115200 plat-smoke: PASS"
# resume
