# Emulated leg of the FU740 takeover. VERIFIED — gated by
# tests/scripts/run_unmatched_takeover_smoke.sh, which also runs it broken on purpose.
#
# QEMU must already be running, with firmware in the chain and the gdbstub open:
#   qemu-system-riscv64 -M sifive_u -smp 2 -s -S -kernel <S-mode stub> -nographic
# No -bios flag: this machine's default -bios IS opensbi-riscv64-generic-fw_dynamic.bin.
#
# Caller sets $tos_elf (the image) and may override $tos_port / $tos_fw_done.
#   riscv64-elf-gdb -q -batch -ex 'set $tos_elf = "…/plat.elf"' \
#       -x tests/gdb/unmatched_takeover_qemu.gdb

set $tos_port = 1234

# -- hart selection ------------------------------------------------------------------
# -M sifive_u puts the harts in two CPU CLUSTERS and QEMU's gdbstub presents a cluster
# as a separate gdb INFERIOR. Inferior 1 is the lone E51 (mhartid 0) and is where you
# land by default; inferior 2 is the U54 array (mhartid 1..N). Measured:
#   inferior 1 thread 1.1 -> mhartid 0, misa=0x8000000000101105  (D clear)
#   inferior 2 thread 2.1 -> mhartid 1, misa=0x800000000014112d  (D set)
# Taking over the default inferior puts the kernel on the core that cannot execute it —
# the same mistake crt0's old `bnez mhartid, halt` gate made.
#
# schedule-multiple is required, not cosmetic: without it the `continue` in tos_halt
# resumes only inferior 2, OpenSBI's boot hart never gets to run, and the breakpoint
# below is never reached.
set schedule-multiple on
eval "target extended-remote :%d", $tos_port
add-inferior
inferior 2
attach 2

# Re-selected AFTER the halt, because the halt is a breakpoint and gdb switches to the
# hart that hit it -- so picking a hart before halting is discarded. Without this the
# leg takes over whichever hart OpenSBI happened to boot on, which is right today only
# by luck.
define tos_pick_hart
  thread 2.1
end

# -- halt ----------------------------------------------------------------------------
# On the board you halt a machine that is already sitting at the U-Boot prompt. Here we
# have to MAKE that moment, and it has to be synchronous: `interrupt` is asynchronous
# and in batch mode gdb never settles, so every following command fails with
# "Cannot execute this command while the target is running" (measured, four ways).
# A temporary breakpoint at the S-mode stub's entry is the synchronous equivalent: let
# firmware run to completion, stop exactly where U-Boot's prompt would be, in S-mode.
# $tos_fw_done is that address — tests/exec/harness/link_smode_idle.ld puts it here.
if !$_isvoid($tos_fw_done) == 0
  set $tos_fw_done = 0x80400000
end
define tos_halt
  eval "tbreak *%#lx", $tos_fw_done
  continue
end

# -- resume --------------------------------------------------------------------------
# `detach`, not `continue`. Detaching means "resume and stop debugging", which is
# precisely the last act of a takeover, and it is the only form that works in batch:
# a trailing `continue` never returns, and over QEMU's gdbstub it races with the stub's
# own resume bookkeeping (the hart is already marked [running] once pc is written), so
# it reports "Cannot execute this command while the target is running" while the guest
# runs anyway. Interactively you would type `continue` and keep ^C — same effect.
# Both inferiors: leaving the E51 attached and stopped would keep the VM from running.
define tos_resume
  detach inferiors 1-2
end

source tests/gdb/unmatched_takeover.gdb
tos_takeover _start
