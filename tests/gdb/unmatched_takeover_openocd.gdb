# Board leg of the FU740 takeover, over OpenOCD.
#
# *** NOT VERIFIED ON HARDWARE. *** Read this before running it.
#
# What IS known, measured on a live Unmatched through its on-board FT2232H:
#   works        : the TAP scans (IDCODE 0x20000913), and raw `riscv dmi_write`/`dmi_read`
#                  pairs come back 0-bad-out-of-30.
#   DOES NOT     : a full OpenOCD target examine, or a halt, does not reliably complete.
#   why          : a ~2-3% per-scan DMI corruption floor that no setting reaches zero on.
#                  Over 300+ alternating dmstatus/abstractcs/dmcontrol scans per setting:
#                    10 MHz falling  9 stray | 8 MHz falling 6 | 8 MHz rising 8 (+1 error)
#                    6 MHz falling   7       | 3 MHz asserts   | 1-2 MHz total collapse
#                  An examine or a halt issues HUNDREDS of DMI ops and OpenOCD treats ONE
#                  bad status as fatal with no retry, so at that floor it fails ~every time.
#                  Small probes LIE: 60-op probes look perfect, which is why an earlier
#                  "24/24 clean, found 5 harts" was true and still misleading.
#
# So: everything this script DOES to machine state is verified — in emulation, by
# tests/scripts/run_unmatched_takeover_smoke.sh with OpenSBI in the chain and four negative
# controls. What is unverified is whether this board's debug link can carry it at all.
# The QEMU twin is the only place the sequence itself is proven today.
#
# ---------------------------------------------------------------------------------------
# PRE-FLIGHT. Do not skip it: the failure mode is a fatal abort mid-load, and OpenOCD 0.12
# asserts (`riscv-013.c:499: info->abits != 0`) rather than reporting a bad link.
#
#   openocd -f tests/openocd/hifive_unmatched_hart1.cfg &     # hart1-only, 10 MHz, falling
#   tests/scripts/unmatched_jtag_floor_check.sh 300 0          # 300 dmstatus scans
#
# Any stray reads mean an examine/halt will probably not complete. DO NOT lower the adapter
# speed in response — below ~4 MHz this link collapses outright, and the original
# hifive_unmatched.cfg's 1 MHz default was itself the bug. Try tdo_sample_edge falling at
# 8-10 MHz, a different micro-USB cable, and failing that the external Olimex
# ARM-USB-TINY-H on header J18: an independent JTAG path that bypasses the on-board
# FT2232H entirely (use hifive_unmatched.cfg, but at 10 MHz falling, not its 1 MHz).
# ---------------------------------------------------------------------------------------
#
# SETUP
#   openocd -f tests/openocd/hifive_unmatched_hart1.cfg
#   screen /dev/cu.usbserial-<loc>1 115200    # channel B of the SAME micro-USB bridge
#   riscv64-elf-gdb -q -batch \
#       -ex 'set $tos_elf = "build/kernels/hifive_unmatched/hello.elf"' \
#       -x tests/gdb/unmatched_takeover_openocd.gdb
#
# Start with hello.elf, not the kernel: 745 bytes that print before touching any CSR, so
# they survive being entered at the wrong privilege level, and that name "wrong hart"
# instead of hanging.
#
# PRECONDITION: a WARM board whose own firmware has already trained DDR. Never
# `monitor reset halt` a cold FU740 — you would halt it before DDR exists and `load` would
# write into nothing.
#
# WHICH WARM STATE, and this matters more than it sounds:
#   at the U-Boot prompt  <- prefer this, strongly. One hart active, MMU off (satp=0), so
#                            gdb's `load` writes the physical addresses it claims to, and
#                            nothing else is using the machine.
#   under Linux           <- attaches, but:
#       * Linux runs SMP on all four U74s. Steal one and three keep running Linux; expect
#         RCU stalls, then a hang or a panic.
#       * A getty owns the console, so its output interleaves with ours.
#       * The MMU is ON. `satp` is non-zero and gdb's memory accesses go through it, so a
#         `load` to 0x80200000 may not land at physical 0x80200000. Check `p/x $satp`.
#       * 0x80200000 holds the running kernel image. Fine only because we are taking the
#         machine for good.
#   a hart left halted    <- possible, and it does not look like it. dmstatus 0x30382
#                            (allhalted|resumeack) means an earlier session halted a hart
#                            and never resumed it. The floor-check script names this.

set $tos_port = 3333
eval "target extended-remote :%d", $tos_port

# -- hart selection ------------------------------------------------------------------
# Nothing to do, and that is a property of the cfg rather than luck:
# hifive_unmatched_hart1.cfg exposes hart 1 only. Hart 0 is the S7 — rv64imac, no F, no D
# — and cannot execute this rv64imafdc/lp64d image at all, so there is nothing to gain by
# exposing it and a real mistake to be made. tos_show_inherited still prints a misa.D
# check and says so loudly if that ever changes.
define tos_pick_hart
  echo [takeover] hart: :3333 is hart 1 (U74); the S7 is not a target in this cfg\n
end

# -- halt ----------------------------------------------------------------------------
# Through OpenOCD because it is idempotent: the hart may already be halted (see dmstatus
# 0x30382 above), and gdb's `interrupt` on an already-stopped target is an error that
# aborts a batch script. `halt`, NOT `reset halt` — see the precondition.
# This is also the step most likely to fail on this link: it is hundreds of DMI ops.
define tos_halt
  monitor halt
end

# -- resume --------------------------------------------------------------------------
# One inferior here, so a plain detach: "resume and stop debugging", the last act of a
# takeover. Interactively type `continue` instead to keep ^C and the register view.
define tos_resume
  detach
end

source tests/gdb/unmatched_takeover.gdb
tos_takeover _start

# If `set $priv = 3` is rejected by this OpenOCD build, the same write is available as
#   (gdb) monitor reg priv 3
# on a halted hart (dcsr is writable in debug mode). If NEITHER works, stop and report it:
# entering in S-mode is not a fallback. OpenSBI's PMP denies S/U access to the CLINT at
# 0x02000000 and the kernel reads it immediately after the UART — docs/HIFIVE_UNMATCHED.md §3.
