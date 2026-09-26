# unmatched_takeover.gdb — take a running HiFive Unmatched away from its own firmware
# and hand it to TempleOS/RISC-V, over gdb.
#
# ONE takeover, two targets:
#   emulated : qemu-system-riscv64 -M sifive_u -smp 2 -s   (gdbstub :1234)
#              default -bios IS opensbi-riscv64-generic-fw_dynamic.bin, so OpenSBI
#              really runs first and really leaves its state behind. -bios none — the
#              shortcut every other smoke in this tree takes — is exactly what this
#              exercise exists to avoid.
#   board    : openocd -f tests/openocd/hifive_unmatched.cfg  (gdb server :3333)
#
# WHAT IS SHARED AND WHAT IS NOT. Everything that changes machine state is in this
# file and is byte-identical on both legs: open the image, load it, raise the
# privilege level, drop the firmware's interrupt enables, set pc. What differs is only
# how each server is DRIVEN — how you halt, how you pick a hart, how you resume — and
# those three are `tos_halt`, the hart selection, and `tos_resume`, each defined in its
# own wrapper so the difference is visible instead of buried:
#   tests/gdb/unmatched_takeover_qemu.gdb      (verified, gated)
#   tests/gdb/unmatched_takeover_openocd.gdb   (written out, NOT verified — no board)
#
# WHY IT IS NOT JUST "load; set $pc; continue". Three things, each measured under QEMU
# with OpenSBI v1.5.1 actually in the chain:
#
# 1. PRIVILEGE. TempleOS/RV is M-mode from crt0 onward: it writes mtvec, sets
#    mstatus.MIE, reads mcause/mepc/mtval, and its debugger panes display machine CSRs.
#    A hart halted after firmware is in S-MODE (measured: priv=1, mstatus=0x...6080).
#    `set $pc` does not change privilege, so the first `csrw mtvec` would be an illegal
#    instruction handed to OpenSBI's trap handler. Both servers expose the debug-mode
#    privilege as the pseudo-register `priv` (QEMU prints "prv:3 [Machine]"; OpenOCD
#    writes dcsr.prv), so one identical line covers both.
#
# 2. PMP. OpenSBI fences itself off. Measured on the boot hart:
#      pmpcfg0=0x1f1b181818
#      pmpaddr0=0x801fff    -> 0x02000000 +64K  CLINT,        S/U: none
#      pmpaddr1=0x20013fff  -> 0x80040000 +128K firmware RW,  S/U: none
#      pmpaddr2=0x20007fff  -> 0x80000000 +256K firmware R+X, S/U: none
#      pmpaddr3=0x37fffff   -> 0x0C000000 +64M  PLIC,         S/U: R+W
#      pmpaddr4=0xffff..ff  -> whole space,                   S/U: R+W+X
#    No cfg byte has the L (lock) bit 0x80 set, so none of it applies to M-mode: after
#    the privilege raise we inherit a machine we can fully drive, and nothing has to be
#    undone. This is also why S-mode entry is not the cheaper option it sounds like —
#    PMP entry 0 denies S/U access to the CLINT, and RVClintMtime() at 0x02000000 is
#    the second thing the kernel touches after the UART. In S-mode it faults at once.
#
# 3. LEFTOVER INTERRUPT STATE. Measured: mtvec=0x800003c8 (OpenSBI's own handler),
#    mie=0x8 (MSIE, for its IPIs), mstatus MIE=0. crt0 installs its own mtvec first
#    thing, so mtvec is self-healing — and when it is not, you see it: the wrong-pc
#    negative control lands in OpenSBI's `sbi_trap_error` dump, which is OpenSBI's
#    mtvec still being in charge. A machine software interrupt left enabled would fire
#    the moment the kernel sets mstatus.MIE, into a handler that knows nothing about
#    OpenSBI's IPI protocol, so mie/mip are cleared here rather than left to luck.
#
# TWO MODES, AND ON REAL HARDWARE ONLY ONE OF THEM IS VIABLE.
#
#   $tos_skip_load = 0 (default)  gdb `load`s the image itself.
#   $tos_skip_load = 1            the image is ALREADY in DDR; gdb only halts, raises the
#                                 privilege level, sets pc and resumes.
#
# The second is the one the Unmatched will actually use, and the reason is measured. This
# board's on-board FT2232H debug path carries a 1-5% per-DMI-scan corruption floor that no
# OpenOCD setting removes (schematics rev 3: FT2232HL ADBUS0-3 -> U4 TXB0104 auto-direction
# 3.3<->1.8 V shifter -> 33R series -> the TS3A5018 mux -> SoC; that level-shifter chain is
# the plausible origin and it is not addressable from software). A gdb `load` of a
# multi-megabyte image is hundreds of thousands of DMI operations, and OpenOCD treats a
# single bad DMI status as fatal with no retry. That is not a thing that completes.
#
# So on hardware: let U-Boot put the image in DDR (tftp, or from SD), and let JTAG do only
# the dozen operations it alone can do -- halt, force M-mode, set pc, resume. That dozen can
# be retried by hand; a `load` cannot. `$tos_skip_load = 1` is exactly that dozen, and it is
# what the emulated gate exercises, with QEMU's `-device loader` standing in for U-Boot's
# tftp. (The other hardware option avoids JTAG entirely: package the M-mode kernel as the
# SPL's next stage, so nothing has to be taken over at all.)
#
# WHAT THIS DELIBERATELY DOES NOT DO: `monitor reset halt`. On a cold board that halts
# the FU740 before its DDR controller has been trained, and `load` then writes into a
# memory system that is not there. The premise is the opposite: let the board's own
# firmware bring up clocks and DDR, and only then attach. Under QEMU DDR is always
# live, so the two legs agree by construction.

set pagination off
set confirm off
set architecture riscv:rv64

# --- the wrapper provides -----------------------------------------------------------
#   $tos_elf      : path to the image, as a string
#   tos_halt      : leave the machine halted (idempotent)
#   tos_pick_hart : select the hart to take over -- called AFTER tos_halt, on purpose.
#                   A halt does not preserve your thread selection: on the QEMU leg the
#                   halt is a breakpoint, and gdb switches to whichever hart hit it. So
#                   a hart picked before the halt is silently discarded, and you take
#                   over whatever firmware happened to be running on. Found by a
#                   negative control that refused to fail.
#   tos_resume    : hand the machine back and stop debugging
#
# ORDERING, which cost a run to find: the ELF is opened AFTER connecting and AFTER
# selecting the hart, never on the gdb command line. Both servers describe the hart you
# first land on, and on both that hart is the FPU-less management core (E51/S7). gdb
# compares its flen against the ELF's and refuses outright:
#   "bfd requires flen 8, but target has flen 0"
# so `gdb <elf> -x script` cannot work here at all.

define tos_show_inherited
  printf "[takeover] mhartid=%d priv=%d pc=0x%lx\n", $mhartid, $priv, $pc
  printf "[takeover] misa=0x%lx mstatus=0x%lx\n", $misa, $mstatus
  printf "[takeover] inherited mtvec=0x%lx mie=0x%lx (firmware's)\n", $mtvec, $mie
  printf "[takeover] inherited pmpcfg0=0x%lx pmpaddr0=0x%lx (no L bit => M-mode unrestricted)\n", $pmpcfg0, $pmpaddr0
  # misa.D is not a nicety. The image is -march=rv64imafdc -mabi=lp64d, and on the FU740
  # hart 0 is the S7 with no D at all. This is the difference between running and an
  # illegal instruction on the first double.
  if ($misa & 8) == 0
    echo [takeover] *** WRONG HART: misa.D is clear, so this is the S7/E51 management\n
    echo [takeover] *** core. TempleOS/RV needs a U74 (mhartid 1..4). Expect nothing.\n
  end
end

# tos_takeover <entry-symbol-or-address>
define tos_takeover
  tos_halt
  tos_pick_hart
  tos_show_inherited
  # Only now is it safe to open the image: we are on a hart whose flen matches it.
  # `file` reads symbols on the host and touches the target not at all, so it is safe in
  # both modes -- it is what makes `_start` a name rather than an address you look up.
  eval "file %s", $tos_elf
  if $_isvoid($tos_skip_load) || !$tos_skip_load
    echo [takeover] load (gdb writes the image -- see the DMI-floor note above)\n
    load
  else
    echo [takeover] load SKIPPED: image already in DDR (U-Boot tftp / SD).\n
    echo [takeover] Only the dozen ops JTAG alone can do follow.\n
  end
  set $priv = 3
  set $mie = 0
  set $mip = 0
  set $pc = $arg0
  printf "[takeover] entering at 0x%lx with priv=%d mie=0x%lx\n", $pc, $priv, $mie
  tos_resume
end
