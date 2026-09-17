#!/bin/bash
# asm REPL coupled to the JIT (plan D-6): AsmStep wraps one asm line in a load/store of the
# debugger's freeze array and runs it through ExePutS, so each line starts from the registers
# the previous line left behind and only the CHANGED registers print. Also checks the coupling
# both ways: _A0 (a debugger label) and the asm REPL share one register file.
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
     "AsmClr;",
     "AsmStep(\"addi a0,a0,7\");",
     "AsmStep(\"add a1,a0,a0\");",
     "AsmStep(\"nop\");",
     "_A0 = 0x20;",
     "AsmStep(\"addi a0,a0,1\");",
     "_A0;",
     "Dr;",
     "RegPaneCost;",
     "AsmStep(\"addi a2,a2,3\");",
     "RegPaneCost;",
     "*(0(I64 *)) = 1;",
     "DbgViewCost;",
     "_MCAUSE;",
     "G;",
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
    echo "FAIL asm-repl smoke -- missing: $1" >&2
    fail=1
  fi
}
need "A2 dbg pubs wired"
# a0 = 0 + 7: only a0 moved, and the line prints the before -> after pair
need "a0   0000000000000000 -> 0000000000000007"
# the next line starts from THAT a0: a1 = a0 + a0 = 14
need "a1   0000000000000000 -> 000000000000000E"
# a line that changes nothing says so (not a silent success)
need "(no register changed)"
# the debugger label and the asm REPL are one register file, both ways: _A0 = 0x20 then step
need "a0   0000000000000020 -> 0000000000000021"
# ... and reading _A0 back sees what the stepped instruction wrote (0x21 = 33)
if ! printf '%s\n' "$out" | grep -qx 'ans=33'; then
  echo "FAIL asm-repl smoke -- _A0 did not read the value the stepped instruction left" >&2
  fail=1
fi
# Dr reads the same array: a0 shows the stepped value, and the CSR line is present
need "a0  =0000000000000021"
need "mcause="
# Live register pane (Kernel/RVRegPane.HC) in THIS image: DolDoc must actually be alive here
# (it was not until RVExePubs.HC stopped declaring the kernel's `doldoc` extern). The pane is
# repainted by AsmStep's watch hook; a step that moves one register must cost far less than the
# first paint, because the renderer only sends the cells that differ.
need "A2 reg pane wired"
# By the time the first cost is sampled the pane is already warm, so both samples are
# incremental. A full 32-register pane paint is ~1364 bytes (measured by kernel-doctext-smoke);
# a step that moves one register — and un-highlights the previous one — must stay an order of
# magnitude under that, or the diff has stopped working.
pane_costs=$(printf '%s\n' "$out" | grep -A2 'RegPaneCost;' | grep -o 'ans=[0-9]*' | cut -d= -f2)
for c in $pane_costs; do
  if [ "$c" -le 0 ]; then
    echo "FAIL asm-repl smoke -- register pane never painted (RegPaneCost=$c)" >&2
    fail=1
  elif [ "$c" -ge 300 ]; then
    echo "FAIL asm-repl smoke -- a one-register step cost $c bytes (full pane is ~1364; diff broken?)" >&2
    fail=1
  fi
done
if [ -z "${pane_costs:-}" ]; then
  echo "FAIL asm-repl smoke -- no RegPaneCost readings" >&2
  fail=1
fi
# A faulting line must land in the Dbg view: the REPL paints registers + the decoded fault and
# returns to this prompt (stock TempleOS Dbg(), no modal UI). _MCAUSE then reads 7 (store access
# fault) straight out of the freeze through a register label.
need "fault in that line"
dbgv=$(printf '%s\n' "$out" | grep -A1 'DbgViewCost;' | grep -o 'ans=[0-9]*' | head -1 | cut -d= -f2)
if [ -z "${dbgv:-}" ] || [ "${dbgv:-0}" -le 0 ]; then
  echo "FAIL asm-repl smoke -- Dbg view did not paint after a fault (DbgViewCost=$dbgv)" >&2
  fail=1
fi
if ! printf '%s\n' "$out" | grep -qx 'ans=7'; then
  echo "FAIL asm-repl smoke -- _MCAUSE did not read the store access fault (ans=7)" >&2
  fail=1
fi
if [ "$fail" -ne 0 ]; then
  printf '%s\n' "$out" | grep -E 'A2|ExePutS|ans=|Except|Error|FAIL|OK|probe|Cmp|Compiler_RV' | head -40 | sed 's/^/  /' >&2
  printf '%s\n' "$out" | tail -30 | sed 's/^/  /' >&2
  exit 1
fi

echo "Asm-REPL smoke: OK (AsmStep runs a line with the debugger register file; only changed regs print)"
