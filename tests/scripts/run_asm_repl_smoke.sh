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
     "\x01g",
     "DbgViewCost;",
     "DbgDisasmCost;",
     "_MCAUSE;",
     "G;",
     "D(_SP, 32);",
     "Da(_SP, 8);",
     "*(0(I64 *)) = 2;",
     "s",
     "Cls;",
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
# With the in-trap debugger installed, a fault is handled BEFORE the REPL's recovery: the hook
# paints the view and waits for a key, so "fault in that line" must NOT appear — `g` resumes the
# line instead and it returns a value like any other. That is the whole point of G.
need "[dbg] g=go"
# A fault the operator does not answer must give the line back rather than hang or eat input:
# either the wait expires ("nobody there") or the next keystroke is not a debugger key
# ("leaving"). The second fault below is followed by an ordinary REPL line, so it takes the
# second path — and the REPL's own recovery then reports the fault as usual.
if ! printf '%s\n' "$out" | grep -qE '\[dbg\] (nobody there|leaving)'; then
  echo "FAIL asm-repl smoke -- an unanswered fault neither timed out nor released the line" >&2
  fail=1
fi
need "fault in that line"
# D numbers from zero (structure layout); Da names code addresses on the stack, which is what
# makes a stack readable. Both render into the memory tile.
# D paints into an empty tile, so its title is contiguous in the byte stream. Da then overwrites
# the SAME tile, so only the changed cells go out and its title is split across cursor moves —
# it has to be checked on the reconstructed screen, where it is also the one that survives.
# DolDoc markup on printed output must arrive as escape codes, not as source: a bad line prints
# "$LTRED$$BK,1$ERROR:$FG$..." unless RVDolAnsiInstall translated it.
if printf '%s\n' "$out" | grep -qF '$LTRED$'; then
  echo "FAIL asm-repl smoke -- DolDoc markup reached the terminal untranslated" >&2
  fail=1
fi
need_screen "ERROR:" "> Cls;"
# On the SCREEN, not in the stream: with the paged pane there are rows left for a memory pane
# at 80x25, so D draws a tile — and a tile's text is not contiguous in the output, because the
# renderer sends only the cells that changed.
need_screen "D (offsets from 0)" "> Da(_SP, 8);"
# Cls wipes the terminal and the renderer's shadows. The prompt keeps printing afterwards, so
# the screen is not blank — what must be gone is the debugger view that was there before.
if screen | grep -qF "Da (addresses)"; then
  echo "FAIL asm-repl smoke -- Cls left the debugger view on screen" >&2
  fail=1
fi
# Da as of the next fault: entering the debugger repaints the tiles and leaving it clears them.
need_screen "Da (addresses)" "> *(0(I64 *)) = 2;"
# ...and the disasm tile as of the in-trap prompt: the tiles are painted first, then that line
# is printed, and leaving the debugger with `g` clears the view — which is the point of it.
need_screen "disasm at _PC" "[dbg] g=go"
# (An unanswered fault DOES fall through to the REPL's recovery — that is asserted above.
# What must not happen is the first fault, which we answer with `g`, being recovered instead
# of resumed; the ans=1 check below covers that.)
dbgv=$(printf '%s\n' "$out" | grep -A1 'DbgViewCost;' | grep -o 'ans=[0-9]*' | head -1 | cut -d= -f2)
if [ -z "${dbgv:-}" ] || [ "${dbgv:-0}" -le 0 ]; then
  echo "FAIL asm-repl smoke -- Dbg view did not paint after a fault (DbgViewCost=$dbgv)" >&2
  fail=1
fi
if ! printf '%s\n' "$out" | grep -qx 'ans=7'; then
  echo "FAIL asm-repl smoke -- _MCAUSE did not read the store access fault (ans=7)" >&2
  fail=1
fi
# The disasm tile: Dbg captures U()'s output through a StdOut sink and renders it as a document
# under the status pane, so the view shows registers + fault + code without a second UI.
# Cost must clear the HEADER alone. A first cut asserted > 0 and passed while the tile showed
# only its title: the capture sink was registered behind the console (KeyDevAdd runs lowest
# priority first), so U()'s output never reached it. Eight disassembled instructions are ~300+
# bytes; the bare header is well under 100.
dis=$(printf '%s\n' "$out" | grep -A1 'DbgDisasmCost;' | grep -o 'ans=[0-9]*' | head -1 | cut -d= -f2)
if [ -z "${dis:-}" ] || [ "${dis:-0}" -lt 200 ]; then
  echo "FAIL asm-repl smoke -- Dbg disassembly tile looks header-only (DbgDisasmCost=$dis)" >&2
  fail=1
fi
# and the instruction text must actually be on screen
if ! printf '%s\n' "$out" | grep -q 'disassembly @'; then
  echo "FAIL asm-repl smoke -- no disassembly text in the view" >&2
  fail=1
fi
if [ "$fail" -ne 0 ]; then
  printf '%s\n' "$out" | grep -E 'A2|ExePutS|ans=|Except|Error|FAIL|OK|probe|Cmp|Compiler_RV' | head -40 | sed 's/^/  /' >&2
  printf '%s\n' "$out" | tail -30 | sed 's/^/  /' >&2
  exit 1
fi

echo "Asm-REPL smoke: OK (AsmStep runs a line with the debugger register file; only changed regs print)"
