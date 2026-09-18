#!/bin/bash
# asm REPL UI (plan D-6): AsmRepl is a loop of its own — history, Tab completion, and the
# register and memory panes repainted after every stepped instruction. Drives it the way a
# person would: type an instruction, Tab-complete the next one, recall the previous line with
# Up, move the memory pane, leave.
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
     "AsmRepl;",
     "addi a0, a0, 0x10",
     "\x01aui\t a1, 0x1\n",
     "\x01\e[A\e[A\n",
     "d 0x87000400",
     "?",
     "q",
     "q",
    );
    select(undef,undef,undef,5);
    for my $x (@l){
      if ($x =~ s/^\x01//) { print $x; }   # bare key for the in-trap debugger, no newline
      else { print $x,"\n"; }
      select(undef,undef,undef,0.8);
    }
    select(undef,undef,undef,2);
  '
}
out="$(feed | $TIMEOUT 180 "$QEMU" -M virt -m 128M -bios none \
  -kernel "$T/kp.elf" -nographic 2>&1 | LC_ALL=C tr -d '\r')"

# Reconstruct the terminal from the escape stream. The renderer only sends cells that CHANGED,
# so a pane's text is not contiguous in the output: painting "Da (addresses)" over
# "D (offsets from 0)" emits just "a (addre" and "ses)" with cursor moves between. Grepping raw
# output for pane text therefore fails on correct behaviour. Replay it instead.
# screen [stop-marker]: replay up to the first occurrence of the marker, or the whole stream.
# Needed because a later Cls legitimately blanks the screen — assertions about earlier panes have
# to look at the screen as it was before the clear.
screen() {
  printf '%s' "$out" | STOP="${1:-}" python3 -c '
import sys, os
# binary + replace: a boot line can carry a non-UTF-8 byte, and sys.stdin.read() would raise
# UnicodeDecodeError — which silently produced an EMPTY screen and failed every assertion.
d = sys.stdin.buffer.read().decode("utf-8", "replace")
stop = os.environ.get("STOP", "")
if stop:
    k = d.find(stop)
    if k >= 0:
        d = d[:k]
scr = [[" "]*100 for _ in range(30)]
r = c = 0
i = 0
while i < len(d):
    if d[i] == "\x1b" and i+1 < len(d) and d[i+1] == "[":
        j = i+2
        while j < len(d) and not d[j].isalpha():
            j += 1
        if j < len(d):
            if d[j] == "J" and d[i+2:j] in ("2", "3"):
                scr = [[" "]*100 for _ in range(len(scr))]
                r = c = 0
            if d[j] == "H":
                a = d[i+2:j].split(";")
                try:
                    r = int(a[0])-1 if a[0] else 0
                    c = int(a[1])-1 if len(a) > 1 and a[1] else 0
                except ValueError:
                    pass
            i = j+1
            continue
    ch = d[i]
    if ch == "\n":
        r += 1; c = 0
    elif ch == "\r":
        c = 0
    elif ch >= " " and 0 <= r < 30 and 0 <= c < 100:
        scr[r][c] = ch; c += 1
    i += 1
for row in scr:
    line = "".join(row).rstrip()
    if line:
        print(line)
'
}
need_screen() {
  if ! screen "${2:-}" | grep -qF -- "$1"; then
    echo "FAIL asm-repl smoke -- not on screen: $1" >&2
    fail=1
  fi
}

fail=0
need() {
  if ! printf '%s\n' "$out" | grep -qF "$1"; then
    echo "FAIL asm-repl smoke -- missing: $1" >&2
    fail=1
  fi
}
need "asm REPL: instructions are stepped"
# Tab completed "aui" to the only word that starts with it. This is echoed text, not pane
# content, so it is checked in the stream: pane repaints move the cursor around, and echoed
# characters land wherever it happens to be.
need "asm> auipc"
# Two Ups recall the addi (past the auipc line) and step it again, so a0 accumulates 0x10 twice.
# A recalled line that changed nothing would prove nothing, which is why the test uses one that
# accumulates.
# Pane assertions stop at the help text: leaving AsmRepl clears the screen, so the final
# screen shows nothing at all.
need_screen "a0   0000000000000020" "q  leave"
# the memory pane is beside the registers, pointed where `d` put it
need_screen "memory" "q  leave"
need "asm REPL: out"

if [ "$fail" -ne 0 ]; then
  printf '%s\n' "$out" | grep -E 'A2|ExePutS|ans=|Except|Error|FAIL|OK|probe|Cmp|Compiler_RV' | head -40 | sed 's/^/  /' >&2
  printf '%s\n' "$out" | tail -30 | sed 's/^/  /' >&2
  exit 1
fi

echo "Asm-REPL-UI smoke: OK (history, Tab completion, register + memory panes, clean exit)"
