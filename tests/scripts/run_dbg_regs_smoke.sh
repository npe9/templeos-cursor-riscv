#!/bin/bash
# Debugger register labels (plan D-1): _X0.._X31 / _RA / _A0 / _PC … are planted as ordinary
# I64 globals whose storage IS the fault-freeze slot (Compiler/RVExePubs.HC
# RVExePubsWireDbgRegs), so stock TempleOS usage works: read them in expressions and ASSIGN
# them. Feeds the guest-Compiler REPL write/read pairs and checks the aliases line up:
#   _X9 and _S1 are the same register; _PC and _MEPC are the same CSR slot.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_repl_exepubs_demo.hc"
EXPECT="A2 ExePutS loop: OK"
EXPECT_PROBE="probe ans=42"
EXPECT_ANS="ans=42"
EXPECT_CMP_OWN="A2: Compiler_RV owns ExePutS"
EXPECT_CMP_DONE="A2: Cmp compiled 40+2"

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-repl-exepubs smoke — missing $t" >&2; exit 0; }
done

make -C "$ROOT" holyc-riscv >/dev/null
mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-repl-exepubs smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-repl-exepubs smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-repl-exepubs smoke — compile error" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$SRC" -o /dev/null 2>&1 | tail -30 >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv \
    --rename-section .data=.data,alloc,load,code,contents,readonly \
    blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exepubs.ld" -nostdlib --no-warn-mismatch \
    -o kp.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-repl-exepubs smoke — link error" >&2; exit 1; }

cp "$T/kp.elf" "$OUTDIR/repl_exepubs.elf"
# Product alias: Interactive guest Cmp REPL (not the thin hc_repl Jit bridge).
mkdir -p "$ROOT/build"
# repl-cmp.elf is installed by kernel-repl-exepubs-smoke; this smoke only reads

# Probe already ran ExePutS(40+2). Delay stdin until after CInit/probe so the
# UART RX FIFO is not overrun while the guest is still booting (lost lines → hang),
# and pace each line (the REPL line-editor drops chars on unpaced input). We also
# assemble a mixed base+RVC+call block and Disasm it, proving the debugger surface
# (Disasm/Uf, planted via RVExePubsWireDbg) closes the assemble→disassemble loop.
feed() {
  perl -e '
    $|=1;
    my @l=(
     "_X9 = 0x51;",
     "_S1;",
     "_A0 = 7;",
     "_A0 + 1;",
     "_PC = 0x1234;",
     "_MEPC;",
     "q",
    );
    select(undef,undef,undef,5);
    for my $x (@l){ print $x,"\n"; select(undef,undef,undef,0.8); }
    select(undef,undef,undef,2);
  '
}
out="$(feed | $TIMEOUT 180 "$QEMU" -M virt -m 128M -bios none \
  -kernel "$T/kp.elf" -nographic 2>&1 | LC_ALL=C tr -d '\r')"

fail=0
need() {
  if ! printf '%s\n' "$out" | grep -qF "$1"; then
    echo "FAIL kernel-repl-exepubs smoke — missing: $1" >&2
    fail=1
  fi
}
need "A2 dbg pubs wired"
ansq() {
  if ! printf '%s\n' "$out" | grep -qx "ans=$1"; then
    echo "FAIL dbg-regs smoke — $2 (want ans=$1)" >&2
    fail=1
  fi
}
ansq 81 "_S1 did not read what _X9 wrote (same register, two names)"
ansq 8 "_A0 assignment then use in an expression"
ansq 4660 "_MEPC did not alias _PC (same CSR slot)"

if [ "$fail" -ne 0 ]; then
  printf '%s\n' "$out" | grep -E 'A2|ExePutS|ans=|Except|Error|FAIL|OK|probe|Cmp|Compiler_RV' | head -40 | sed 's/^/  /' >&2
  printf '%s\n' "$out" | tail -30 | sed 's/^/  /' >&2
  exit 1
fi

echo "Dbg-regs smoke: OK (_X0.._X31 / _A0 / _PC planted as assignable globals on the fault freeze)"
