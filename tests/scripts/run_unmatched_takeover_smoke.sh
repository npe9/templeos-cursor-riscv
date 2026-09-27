#!/bin/bash
# Apples-to-apples FU740 bring-up rehearsal: the exact gdb takeover that will be run on
# the hardware, run first under QEMU with OpenSBI actually in the chain.
#
#   board:  reset -> boot ROM -> U-Boot SPL (clocks+DDR) -> OpenSBI -> U-Boot proper
#           -> [JTAG attach + halt] -> load ELF -> pc=_start -> M-mode -> resume -> UART
#   here:   qemu -M sifive_u (default -bios = opensbi-...-fw_dynamic.bin) -s
#           -> [gdb attach + interrupt] -> load ELF -> pc=_start -> M-mode -> resume -> UART
#
# Same ELF, same load address, same gdb script (tests/gdb/unmatched_takeover.gdb).
# Only the port and the hart-selection idiom differ, and both are in the wrappers.
#
# Usage: run_unmatched_takeover_smoke.sh [hello|plat|repl]   (default: hello)
#   hello - tests/exec/harness/hello_unmatched.S, 745 bytes of asm; isolates
#           "can we get code running at all" from "does the kernel work"
#   plat  - build/kernels/hifive_unmatched/plat.elf (the HolyC platform demo)
#   repl  - build/exec/repl_unmatched.elf (the HolyC REPL), if built
#
# TWO MODES, matching the two ways the image can reach DDR on hardware:
#   TOS_TAKEOVER_LOAD=gdb  (default)  gdb `load`s the image over the debug link.
#   TOS_TAKEOVER_LOAD=pre             the image is ALREADY in DDR and gdb only halts, forces
#                                     M-mode, sets pc and resumes -- a dozen operations.
# `pre` is the mode the Unmatched will actually use, and it is not a shortcut: that board's
# on-board FT2232H debug path has a measured 1-5% per-DMI-scan corruption floor that no
# OpenOCD setting removes, and OpenOCD treats one bad DMI status as fatal with no retry. A
# `load` of a multi-megabyte image is hundreds of thousands of DMI ops and does not complete;
# a dozen can be retried by hand. On hardware U-Boot puts the image in DDR (tftp or SD);
# here QEMU's `-device loader` stands in for that, so the privilege switch -- the step JTAG
# will still have to do either way -- is exercised exactly as it will be.
#
# NEGATIVE CONTROLS: TOS_TAKEOVER_BREAK=badpc|nopriv|wronghart|nofirmware. Each must make the
# gate FAIL; `make unmatched-takeover-controls` runs all four and fails if any passes.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WHICH="${1:-hello}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
GDB="${RISCV_GDB:-riscv64-elf-gdb}"
PORT="${TOS_GDB_PORT:-1234}"
BREAK="${TOS_TAKEOVER_BREAK:-}"
LOADMODE="${TOS_TAKEOVER_LOAD:-gdb}"
case "$LOADMODE" in gdb|pre) : ;; *) echo "TOS_TAKEOVER_LOAD must be gdb|pre" >&2; exit 2 ;; esac
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

command -v "$QEMU" >/dev/null 2>&1 || { echo "FAIL takeover — missing $QEMU" >&2; exit 1; }
command -v "$GDB" >/dev/null 2>&1 || { echo "FAIL takeover — missing $GDB (brew: riscv64-elf-gdb)" >&2; exit 1; }

# OpenSBI is QEMU's own default -bios for this machine; assert it exists so a silent
# fallback to "no firmware" cannot masquerade as a passing apples-to-apples run.
SBI=""
for d in "$(dirname "$(command -v "$QEMU")")/../share/qemu" /opt/homebrew/share/qemu /usr/share/qemu; do
  if [ -f "$d/opensbi-riscv64-generic-fw_dynamic.bin" ]; then
    SBI="$d/opensbi-riscv64-generic-fw_dynamic.bin"; break
  fi
done
[ -n "$SBI" ] || { echo "FAIL takeover — no opensbi-riscv64-generic-fw_dynamic.bin found" >&2; exit 1; }

case "$WHICH" in
  hello)
    "$SCRIPT_DIR/run_hello_unmatched_smoke.sh" >/dev/null 2>&1 \
      || { echo "FAIL takeover — hello payload does not build/pass its own smoke" >&2; exit 1; }
    ELF="$ROOT/build/kernels/hifive_unmatched/hello.elf"
    NEEDLES=("hello from the HiFive Unmatched" "hello-unmatched: OK") ;;
  plat)
    "$SCRIPT_DIR/build_kernel_plat.sh" hifive_unmatched >/dev/null 2>&1 \
      || { echo "FAIL takeover — plat image does not build" >&2; exit 1; }
    ELF="$ROOT/build/kernels/hifive_unmatched/plat.elf"
    NEEDLES=("plat-smoke: machine=hifive-unmatched" "plat-smoke: PASS" "ORACLE ") ;;
  repl)
    # Built by run_repl_unmatched_smoke.sh (it applies the board Kconfig, so it is not
    # rebuilt here -- the point of this target is to take over the artifact as it stands).
    ELF="$ROOT/build/exec/repl_unmatched.elf"
    # "A2 ExePutS REPL" alone only proves it printed. ans=42 is the in-image probe having
    # COMPILED and EVALUATED 40+2 through the guest compiler.
    NEEDLES=("A2: Compiler_RV owns ExePutS" "A2 ExePutS REPL" "ans=42") ;;
  *)
    echo "usage: $0 [hello|plat|repl]" >&2; exit 2 ;;
esac
[ -f "$ELF" ] || { echo "FAIL takeover — missing $ELF" >&2; exit 1; }

T="$(mktemp -d)"
cleanup() {
  [ -n "${QPID:-}" ] && kill "$QPID" 2>/dev/null
  rm -rf "$T"
}
trap cleanup EXIT

UART="$T/uart.log"
: >"$UART"

# The S-mode stand-in for U-Boot proper. Without it OpenSBI has nothing to mret into:
# it faults jumping to next-address 0x0 and stays in M-mode, which makes the takeover's
# `set $priv = 3` a silent no-op -- measured, the nopriv control PASSED without this
# stub, i.e. that leg was not testing the one line most likely to matter on hardware.
# With it as -kernel, OpenSBI mrets into S-mode and the emulated hart is in the same
# privilege state as a board at the U-Boot prompt. tests/exec/harness/smode_idle.S.
GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
OBJCOPY_BIN="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
# Read the load address out of the ELF rather than hardcoding it: the image is
# position-independent, so a wrong address produces output just the same and only the ELF
# can say where it was meant to go.
ENTRY_ADDR="$(riscv64-unknown-elf-readelf -h "$ELF" | sed -n 's/.*Entry point address: *//p')"
[ -n "$ENTRY_ADDR" ] || { echo "FAIL takeover -- no entry point in $ELF" >&2; exit 1; }
STUB="$ROOT/build/kernels/hifive_unmatched/smode_idle.elf"
STUB_ENTRY=0x84000000
mkdir -p "$ROOT/build/kernels/hifive_unmatched"
"$GCC" -march=rv64imac -mabi=lp64 -nostdlib -ffreestanding -fno-builtin \
  -c "$ROOT/tests/exec/harness/smode_idle.S" -o "$T/smode_idle.o" \
  || { echo "FAIL takeover -- S-mode stub assemble" >&2; exit 1; }
"$LD" -T "$ROOT/tests/exec/harness/link_smode_idle.ld" -nostdlib -o "$STUB" "$T/smode_idle.o" \
  || { echo "FAIL takeover -- S-mode stub link" >&2; exit 1; }
# The takeover breaks at this address to get a synchronous stop; assert it rather than
# trust the .ld, or the breakpoint would simply never hit and the gate would go quiet.
stub_entry="$(riscv64-unknown-elf-readelf -h "$STUB" | sed -n 's/.*Entry point address: *//p')"
if [ "$((stub_entry))" -ne "$((STUB_ENTRY))" ]; then
  echo "FAIL takeover -- S-mode stub entry $stub_entry != $STUB_ENTRY" >&2; exit 1
fi
# The payload must not reach the stub. A 5.4 MB image at 0x80200000 runs past 0x80400000,
# where the stub used to live, and clobbered it before OpenSBI could enter -- which presents
# as the entire takeover failing with no S-mode banner and no obvious cause.
payload_bytes="$(wc -c <"${ELF%.elf}.bin" 2>/dev/null || echo 0)"
if [ "$payload_bytes" -gt 0 ]; then
  payload_end=$(( $((ENTRY_ADDR)) + payload_bytes ))
  if [ "$payload_end" -gt "$((STUB_ENTRY))" ]; then
    printf 'FAIL takeover -- payload %s..0x%x overlaps the S-mode stub at %s\n' \
      "$ENTRY_ADDR" "$payload_end" "$STUB_ENTRY" >&2
    echo "  move the stub (tests/exec/harness/link_smode_idle.ld) above the payload" >&2
    exit 1
  fi
fi
# Break at the stub's idle loop, NOT its entry: at the entry it has not printed yet, and
# its banner is the gate's only evidence that firmware actually mret'd into S-mode.
PROMPT_ADDR="0x$(riscv64-unknown-elf-nm "$STUB" | sed -n 's/^0*\([0-9a-f]*\) [Tt] _at_prompt$/\1/p' | head -1)"
if [ "$PROMPT_ADDR" = "0x" ]; then
  echo "FAIL takeover -- no _at_prompt symbol in the S-mode stub" >&2; exit 1
fi

# Leg 1: firmware, started HALTED. -S is not a shortcut past firmware: the takeover
# script itself runs it, with a temporary breakpoint at the S-mode stub, because
# `interrupt` is asynchronous and never settles in a batch gdb session. No -bios flag:
# this machine's default -bios IS opensbi-riscv64-generic-fw_dynamic.bin, and -bios none
# would remove the very firmware this exercise is about. -smp 2 = 1 E51 + 1 U54, the same
# management-core-plus-application-core split the FU740 has.
# In `pre` mode the image is already in DDR before any debugger touches the machine. The
# two loader devices are QEMU's stand-in for `tftp 0x80200000 plat.bin` at the U-Boot
# prompt: the FIRST writes the bytes, and there is deliberately NO second loader setting a
# reset PC -- firmware still boots normally and gdb still has to redirect the hart. That is
# the whole point of this mode.
PRELOAD=""
if [ "$LOADMODE" = pre ]; then
  BIN="${ELF%.elf}.bin"
  "$OBJCOPY_BIN" -O binary "$ELF" "$T/preload.bin" 2>/dev/null \
    || { echo "FAIL takeover -- could not flatten $ELF for preloading" >&2; exit 1; }
  PRELOAD="-device loader,file=$T/preload.bin,addr=$ENTRY_ADDR"
  echo "takeover: LOAD=pre -- image placed at $ENTRY_ADDR before boot (stands in for U-Boot tftp)"
fi
# shellcheck disable=SC2086
"$QEMU" -M sifive_u -smp 2 -nographic -s -S -kernel "$STUB" $PRELOAD \
  -serial "file:$UART" -monitor none -display none </dev/null >/dev/null 2>&1 &
QPID=$!
sleep 2
if ! kill -0 "$QPID" 2>/dev/null; then
  echo "FAIL takeover -- QEMU did not start" >&2; exit 1
fi

# Leg 2: the takeover. The wrapper is the same file the board leg uses, minus the port.
WRAP="$T/takeover.gdb"
SHARED_DIR="$ROOT"
cp "$ROOT/tests/gdb/unmatched_takeover_qemu.gdb" "$WRAP"
case "$BREAK" in
  badpc)
    # Enter somewhere else entirely. Everything else identical. If the gate still passes,
    # it is not testing the takeover.
    sed -i.bak 's/^tos_takeover _start$/tos_takeover 0x80800000/' "$WRAP"; rm -f "$WRAP.bak"
    echo "takeover: NEGATIVE CONTROL badpc -- entering at 0x80800000 instead of _start" ;;
  nopriv)
    # Skip the privilege raise. With the S-mode stub in the chain this MUST fail: the
    # kernel's first csrw is illegal from S-mode. Without the stub it used to pass, which
    # is why the stub exists.
    SHARED_DIR="$T"
    mkdir -p "$T/tests/gdb"
    sed 's/^  set \$priv = 3$/  echo [control] privilege raise SKIPPED\\n/' \
      "$ROOT/tests/gdb/unmatched_takeover.gdb" >"$T/tests/gdb/unmatched_takeover.gdb"
    grep -q "privilege raise SKIPPED" "$T/tests/gdb/unmatched_takeover.gdb" \
      || { echo "FAIL takeover -- nopriv control failed to patch the script" >&2; exit 1; }
    echo "takeover: NEGATIVE CONTROL nopriv -- no privilege raise" ;;
  wronghart)
    # Take over the E51 instead of a U54: the FPU-less management core. Must fail.
    # Keep the whole structure; change ONLY the hart, so the control fails for the
    # hart reason and not because the script fell apart.
    sed -i.bak 's/^  thread 2\.1$/  thread 1.1/' "$WRAP"
    rm -f "$WRAP.bak"
    grep -q "^  thread 1.1$" "$WRAP" \
      || { echo "FAIL takeover -- wronghart control failed to patch the wrapper" >&2; exit 1; }
    echo "takeover: NEGATIVE CONTROL wronghart -- taking over hart 0 (E51/S7)" ;;
  nofirmware)
    # -bios none: the shortcut this whole exercise exists to avoid. The gate must notice
    # that OpenSBI was not in the chain even though the kernel itself would run fine.
    echo "takeover: NEGATIVE CONTROL nofirmware -- restarting QEMU with -bios none"
    kill "$QPID" 2>/dev/null; sleep 0.5
    : >"$UART"
    "$QEMU" -M sifive_u -smp 2 -nographic -s -S -bios none -kernel "$STUB" \
      -serial "file:$UART" -monitor none -display none </dev/null >/dev/null 2>&1 &
    QPID=$!
    sleep 2 ;;
  "") : ;;
  *) echo "unknown TOS_TAKEOVER_BREAK=$BREAK" >&2; exit 2 ;;
esac

GDB_CWD="$SHARED_DIR"

# The ELF is NOT passed on the command line: gdb would bind it to whichever hart the
# server describes first, which on both targets is the FPU-less management core, and
# refuse with "bfd requires flen 8, but target has flen 0". The script opens it after
# selecting a U74.
( cd "$GDB_CWD" && $TIMEOUT "${TOS_GDB_TIMEOUT:-25}" "$GDB" -q -batch \
    -ex "set \$tos_elf = \"$ELF\"" -ex "set \$tos_fw_done = $PROMPT_ADDR" \
    -ex "set \$tos_skip_load = $([ "$LOADMODE" = pre ] && echo 1 || echo 0)" \
    -x "$WRAP" ) >"$T/gdb.log" 2>&1
gdb_rc=$?
sed 's/^/  gdb: /' "$T/gdb.log" | grep -v "^  gdb: *$" | head -30

# Give the resumed image a moment to talk.
sleep 2
kill "$QPID" 2>/dev/null
QPID=""

POST="$T/post.log"
tr -d '\r' <"$UART" >"$POST"
# Show the TAIL, not the head: firmware's banner is ~60 lines and the whole point is
# what came after the handover. A head -20 window showed only OpenSBI and hid the needles.
echo "takeover: UART, last 22 lines of $(wc -l <"$POST" | tr -d ' ') (firmware banner above):"
tail -22 "$POST" | sed 's/^/  uart: /'

rc=0
for n in "${NEEDLES[@]}"; do
  if ! grep -qF "$n" "$POST"; then
    echo "FAIL takeover ($WHICH) — needle missing after takeover: $n" >&2
    rc=1
  fi
done
# Firmware really has to have been in the chain, or this is just another -bios none
# smoke wearing a costume. Two markers: OpenSBI's own banner, and the S-mode stub it
# mret'd into -- the latter is what proves the hart we took over was in S-mode.
for m in "Firmware Base" "smode-stub: S-mode idle"; do
  if ! grep -aqF "$m" "$POST"; then
    echo "FAIL takeover -- firmware marker missing: '$m'" >&2
    echo "  without it this does not prove OpenSBI ran, nor that the hart was in S-mode" >&2
    rc=1
  fi
done
# gdb exiting 124 is the EXPECTED outcome: tos_takeover ends in `continue`, which never
# returns because the kernel now owns the machine. What must not happen is gdb failing
# BEFORE the handover, so require the takeover's own trace to show the load and resume.
if [ "$LOADMODE" = pre ]; then
  # The point of this mode is that gdb does NOT write the image. Assert that, or the mode is
  # indistinguishable from the default and proves nothing about the hardware path.
  if ! grep -q "load SKIPPED" "$T/gdb.log"; then
    echo "FAIL takeover -- LOAD=pre but gdb did not skip the load" >&2
    rc=1
  fi
  if grep -qE "^Loading section" "$T/gdb.log"; then
    echo "FAIL takeover -- LOAD=pre but gdb wrote sections anyway" >&2
    rc=1
  fi
  need_trace="\[takeover\] entering at 0x"
else
  need_trace="\[takeover\] load"
fi
for m in "$need_trace" "\[takeover\] entering at 0x"; do
  if ! grep -q "$m" "$T/gdb.log"; then
    echo "FAIL takeover -- gdb never got as far as '$m'" >&2
    rc=1
  fi
done

if [ "$rc" -eq 0 ]; then
  echo "unmatched-takeover ($WHICH, load=$LOADMODE): OK — OpenSBI ran, gdb took the hart, kernel spoke"
else
  echo "unmatched-takeover ($WHICH, load=$LOADMODE): FAIL" >&2
fi
exit "$rc"
