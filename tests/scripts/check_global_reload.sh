#!/bin/bash
# A GLOBAL READ IN A LOOP IS RE-LOADED EVERY ITERATION. This is the property that makes the
# absence of `volatile` in HolyC harmless, and it is asserted here rather than believed.
#
# WHY IT MATTERS. cFE spins on shared state: CFE_ES_Global.SystemState is written by
# cfe_es_start.c as the core comes up and read in a loop by CFE_ES_WaitForSystemState from
# another task, and NASA declares it `volatile sig_atomic_t`. HolyC has no `volatile`. If this
# compiler ever hoisted that load out of the loop, the wait would never end -- and nothing else
# in the gate set could see it: check_padding compares the field's WIDTH and can say nothing
# about how it is read.
#
# WHY IT IS TRUE TODAY, measured rather than assumed: the IC optimizer's passes are constant
# folding, cmp-to-branch, bool elide, const branch, if/else and call tail merge, dead-after-jmp
# and a frame-access peephole. There is no common-subexpression elimination, no loop-invariant
# code motion and no load elimination; every constant pass tests `!(ic_flags & ICF_GLBL_ADDR)`
# and so skips globals by construction; and the register slot cache (O1Slot*) is keyed by FRAME
# OFFSET, which a global does not have.
#
# So this gate is not defending against a bug. It is pinning a property that a future
# optimization pass would silently break, which is the one thing a passing transcript could not
# tell anyone. Run with -v to see the disassembly it is reading.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPILER="$ROOT/holyc-riscv"
OBJDUMP="${RISCV_OBJDUMP:-riscv64-unknown-elf-objdump}"
VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

command -v "$OBJDUMP" >/dev/null 2>&1 || {
  echo "FAIL global-reload — missing $OBJDUMP; cannot read the generated code" >&2; exit 1; }
[ -x "$COMPILER" ] || { echo "FAIL global-reload — build holyc-riscv first" >&2; exit 1; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

cat > "$T/spin.hc" <<'HC'
I32 SystemState;
I64 Spin()
{
  I64 n = 0;
  while (SystemState != 7)
    n++;
  return n;
}
I64 main() { return Spin(); }
HC

if ! HOLYC_MAP="$T/spin.map" "$COMPILER" "$T/spin.hc" -o "$T/spin.bin" >"$T/cc.log" 2>&1; then
  echo "FAIL global-reload — the probe did not compile" >&2
  tail -5 "$T/cc.log" | sed 's/^/  /' >&2
  exit 1
fi

off=$(awk '$2=="Spin"{print $1}' "$T/spin.map" | head -1)
gbl=$(awk '$2=="SystemState"{print $1}' "$T/spin.map" | head -1)
if [ -z "$off" ] || [ -z "$gbl" ]; then
  echo "FAIL global-reload — Spin or SystemState missing from the HOLYC_MAP; the probe's shape" >&2
  echo "  changed and this gate is no longer looking at what it describes." >&2
  exit 1
fi

python3 - "$T/spin.bin" "$off" > "$T/fn.bin" <<'PY'
import sys
off = int(sys.argv[2], 16)
sys.stdout.buffer.write(open(sys.argv[1], 'rb').read()[off:off+160])
PY

"$OBJDUMP" -D -b binary -m riscv:rv64 -M no-aliases "$T/fn.bin" 2>/dev/null \
  | sed -n 's/^ *\([0-9a-f]*\):\t[0-9a-f]* *\(.*\)$/\1 \2/p' > "$T/dis.txt"
[ "$VERBOSE" = 1 ] && sed 's/^/  /' "$T/dis.txt"

# THE PROPERTY, stated as two facts about the disassembly:
#   1. there is a BACKWARD jump -- the loop's back edge -- and its target is T;
#   2. the load that reads the global sits at an address >= T, i.e. INSIDE the loop.
# A hoisted load would sit before T.
python3 - "$T/dis.txt" <<'PY'
import re, sys
lines = [l.split(None, 1) for l in open(sys.argv[1]) if l.strip()]
rows = [(int(a, 16), b.strip()) for a, b in lines if len(_ := (a, b)) == 2]

# The back edge: a jalr/jal whose resolved target (objdump prints "# 0xNN") is BEFORE it.
back = None
for addr, text in rows:
    m = re.search(r'#\s*0x([0-9a-f]+)', text)
    if m and re.match(r'(jalr|jal)\b', text):
        tgt = int(m.group(1), 16)
        if tgt < addr:
            back = (addr, tgt)
if back is None:
    print("FAIL global-reload — no backward jump in Spin; the probe compiled to something", file=sys.stderr)
    print("  without a loop and this gate is asserting nothing.", file=sys.stderr)
    sys.exit(1)
_, target = back

# The global's load: an lw/ld whose base was just materialised by auipc+addi.
loads = []
for i, (addr, text) in enumerate(rows):
    if re.match(r'l[wd]\b', text) and i >= 2 and re.match(r'addi\b', rows[i-1][1]) \
            and re.match(r'auipc\b', rows[i-2][1]):
        loads.append(rows[i-2][0])      # the auipc, where the sequence starts
if not loads:
    print("FAIL global-reload — no auipc/addi/load sequence found; the way this compiler reaches",
          file=sys.stderr)
    print("  a global has changed and this gate no longer recognises it.", file=sys.stderr)
    sys.exit(1)

inside = [a for a in loads if a >= target]
if not inside:
    print("FAIL global-reload — THE GLOBAL'S LOAD IS OUTSIDE THE LOOP.", file=sys.stderr)
    print("  The back edge targets 0x%x; every global load is before it: %s"
          % (target, ", ".join("0x%x" % a for a in loads)), file=sys.stderr)
    print("  Some pass now hoists a loop-invariant load, which makes the missing `volatile`", file=sys.stderr)
    print("  in Kernel/Cfs/cfe/cfe_es_global.HC a real defect: CFE_ES_WaitForSystemState would", file=sys.stderr)
    print("  spin forever. See docs/HOLYC_STRUCT_LIMITS.md #18.", file=sys.stderr)
    sys.exit(1)

print("global-reload: the back edge targets 0x%x and the global's load is at 0x%x -- inside the "
      "loop, re-read every iteration" % (target, inside[0]))
PY
