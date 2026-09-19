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
     # Write a function at the HolyC prompt first: the asm REPL can then trace the code the
     # compiler produced for it, which is the whole point of having both in one image.
     "U0 TraceMe() { I64 q = 7; q = q + 1; }",
     "AsmRepl;",
     "addi a0, a0, 0x10",
     "\x01aui\t a1, 0x1\n",
     "\x01\e[A\e[A\n",
     # t6 doubles as the wrapper base register: it used to be clobbered before it was saved,
     # so `li t6,3` ran and left nothing behind. A float register must survive a step too.
     "li t6, 3",
     "fmv.d.x fa0, t6",
     "d 0x87000400",
     # Tab from the documentation catalog: "sfen" completes to sfence.vma, which the old
     # hand-written word list did not contain. Ctrl-U kills the line rather than stepping it —
     # Ctrl-C would LEAVE the asm REPL, and everything after it would go to the HolyC prompt.
     "\x01sfen\t\x15\n",
     # ...and after a question mark, which ends a word: "?sfen" is the question and then "sfen".
     "\x01?sfen\t\x15\n",
     # ...and the doc for one mnemonic, without leaving the stepper
     "? sd",
     # A real double this time: 0x4010000000000000 is 4.0, so the decomposition has something to
     # say beyond "subnormal".
     "li t1, 0x401",
     "slli t1, t1, 52",
     "fmv.d.x fa0, t1",
     "f 10",
     # ...and disassemble a symbol, which is how you find an idiom worth copying
     "u AsmStep",
     "t TraceMe",
     "t",
     "t",
     "? sd",
     # Program PMP entry 0 as a 64 KiB NAPOT region at 0x80000000, so the decoder is exercised
     # rather than just reporting every entry OFF. addr = base>>2 | (size/8 - 1); cfg = NAPOT
     # (A=3) with rwx. Safe to do from here: an UNLOCKED entry does not apply to M-mode, so this
     # cannot wall the debugger off from its own memory.
     # Work through a family one instruction at a time: p starts it, p again moves on, and each
     # step is that instruction as a man page for you to type yourself.
     "p shift",
     "p",
     # t2, not a0: a0 carries a value a later assertion checks, and practising on it moved it
     "slli t2, t2, 2",
     "li t0, 0x20001FFF",
     "csrw 0x3B0, t0",
     "li t0, 0x1F",
     "csrw 0x3A0, t0",
     "?",
     "q",
     # The same catalog as REPL functions at the HolyC prompt
     # The BCPL rule at the prompt: no semicolons on these two, and they must still work.
     # 40+3 rather than 40+2 because the feed types 40+2; elsewhere, and an assertion that
     # passes on either spelling would prove nothing.
     "40+3",
     "AsmClasses",
     "AsmDoc(\"addi\");",
     "AsmList;",
     # The CSR decoders, now one shared copy: fcsr had no reader anywhere in the tree, and satp
     # was decoded only by the seed datasheet the kernel image does not link.
     "Csr(\"fcsr\");",
     "Csr(\"satp\");",
     # The stopped machine, read from the widened freeze rather than from the hardware now
     "Machine;",
     "Plic;",
     "Pmp;",
     "Pt;",
     # No & here: HolyC reads `x & (-4096)` as an address-of and says "Invalid lval". Round up
     # with arithmetic instead — the tables have to be page-aligned for the PPN shift to mean
     # anything.
     # Walk a real three-level Sv39 table. It has to be one we build: this machine runs with
     # paging off, so satp is Bare and there is no live table to walk. Each REPL line is its own
     # scope, so the table is built by PtDemo in the image rather than by a run of lines here.
     "PtWalk;",
     # A call in an argument list used to corrupt the arguments around it: the backend walked
     # back to the nearest IC_CALL_START to find them and found the INNER one. Both spellings
     # must now deliver the same three values.
     # (No apostrophes in here: this block is inside perl -e single quotes.)
     "ArgEcho(0x11, 0x22, 0x33);",
     "ArgEcho(ArgOne, 0x22, 0x33);",
     # ...and the call that found it: three arguments, the first of them a call
     "PgAt(PtDemo, 0x40403024, 3);",
     # evidence for the note above: a two-argument pub gets only its first argument
     "Dm(0x87000400, 32);",
     # Back at the HolyC prompt, with enough output to scroll its region right through. The
     # panes are live here too, so this is where a layout that only existed inside AsmRepl
     # would be scribbled over and then look frozen.
     ("40+2;") x 8,
     # A line that prints a word nothing else prints: the screen before the resize has to be
     # checked against the size it was laid out for, and after it against the new one.
     "\"resize-mark\";",
     # The window was dragged: 30 rows by 100 columns, reported in band (mode 2048). The sidebar
     # has to move with it — column 56 now, not 76 — and the float block no longer fits.
     "\x01\e[48;30;100;0;0t",
     "40+2;",
     "40+2;",
     "q",
    );
    # The guest asks the terminal how big it is (CSI 6n) before it lays anything out. Answer as
    # a 120x40 screen: the reply sits in the UART queue until the probe reads it, and a smoke
    # that never answers would only ever exercise the 80x25 default.
    print "\e[40;120R";
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

# Keep the raw stream: when an assertion about a pane fails, the only way to see why is to
# replay it by hand.
printf '%s' "$out" > "$OUTDIR/asm_repl_ui.out"

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
ROWS, COLS = 40, 120
scr = [[" "]*COLS for _ in range(ROWS)]
top, bot = 0, ROWS-1   # DECSTBM, 0-based inclusive
r = c = 0
i = 0

sr, sc = 0, 0          # DECSC/DECRC: what ESC 7 saved

def scroll():
    # scroll the region up one line, exactly as a terminal does. Without this the replay never
    # scrolls and a pane looks pinned whether or not the scroll region actually pinned it.
    del scr[top]
    scr.insert(bot, [" "]*COLS)
while i < len(d):
    if d[i] == "\x1b" and i+1 < len(d) and d[i+1] == "[":
        j = i+2
        while j < len(d) and not d[j].isalpha():
            j += 1
        if j < len(d):
            if d[j] == "J" and d[i+2:j] in ("2", "3"):
                scr = [[" "]*COLS for _ in range(ROWS)]
                r = c = 0
            if d[j] == "r":
                a = d[i+2:j].split(";")
                try:
                    top = int(a[0])-1 if a[0] else 0
                    bot = int(a[1])-1 if len(a) > 1 and a[1] else ROWS-1
                except ValueError:
                    top, bot = 0, ROWS-1
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
    if d[i] == "\x1b" and i+1 < len(d):
        # A two-character escape, not CSI. ESC 7 / ESC 8 are how a pane repaint puts the cursor
        # back at the prompt; a replay that skipped them printed a stray "7"/"8" into the pane
        # and left the cursor wherever the pane finished.
        if d[i+1] == "7":
            sr, sc = r, c
        elif d[i+1] == "8":
            r, c = sr, sc
        i += 2
        continue
    ch = d[i]
    if ch == "\n":
        if r == bot:
            scroll()
        else:
            r += 1
        c = 0
    elif ch == "\r":
        c = 0
    elif ch >= " " and 0 <= r < ROWS and 0 <= c < COLS:
        scr[r][c] = ch; c += 1
    i += 1
num = os.environ.get("NUM", "")
for i, row in enumerate(scr):
    line = "".join(row).rstrip()
    if num:
        print("%02d|%s" % (i+1, line))
    elif line:
        print(line)
'
}
# Same replay, but every row, numbered — assertions about WHERE something is need the blank rows
# counted, and `screen` drops them.
screen_num() { NUM=1 screen "${1:-}"; }

need_screen() {
  if ! screen "${2:-}" | grep -qF -- "$1"; then
    echo "FAIL asm-repl smoke -- not on screen: $1" >&2
    fail=1
  fi
}

fail=0
need() {
  if ! printf '%s\n' "$out" | grep -qF -- "$1"; then
    echo "FAIL asm-repl smoke -- missing: $1" >&2
    fail=1
  fi
}
need "asm REPL: instructions are stepped"
# Tab completed "aui" to the only word that starts with it. This is echoed text, not pane
# content, so it is checked in the stream: pane repaints move the cursor around, and echoed
# characters land wherever it happens to be.
need "asm> auipc"
need "asm REPL: out"
# The catalog, enabled in both prompts: Tab completes from it, ? explains one entry inside the
# stepper, and AsmDoc/AsmList are callable HolyC functions at the REPL prompt.
need "asm> sfence.vma"
# AsmDoc is a man page now: sections, an example, and why you would reach for the instruction
need "SYNOPSIS"
need "store doubleword"
need "MOTIVATION"
need "sd ra, 8(sp)             # save the return address"
need "12-bit signed immediate"
need "addi sp, sp, -32         # open a stack frame"
need "documented asm{} mnemonics"
# A line typed without a semicolon: the newline ended the statement (guest lexer, REPL input)
need "ans=43"
need "instruction classes"
# fcsr: read at all for the first time, and decoded. The flags are STICKY — by the time the
# prompt is up the compiler has done its own float work, so this asserts the decode, not a
# pristine value (it reads 0x3: inexact and underflow, accumulated since reset).
need "frm=0 RNE (nearest, ties to even)"
need "(sticky)"
need "NX inexact"
# satp: MODE/ASID/PPN, from the decoder both images now share
need "MODE=0 (Bare"
# Machine(): the freeze carries ten more CSRs than it used to, and the shared decoders read them
need "trap came from"
need "mtvec   ="
need "mideleg ="
need "nothing delegated (all traps taken in M-mode)"
# The interrupt controller, which nothing could read before. The uart is source 10 on virt and
# the REPL enables it, so it must show as enabled — and claim is never read, because reading it
# would acknowledge an interrupt the system was about to service.
need "PLIC @ 0xC000000"
need "claim/complete not read"
# PMP, which is a build option (CONFIG_HAS_PMP): these CSRs are optional in the ISA and reading
# one on a hart without them faults. virt has 16 entries, so this build reads them.
need "PMP: 16 entries"
# The page-table walker, on a table built at the prompt a moment earlier: three levels, a leaf
# with rwx, and the offset carried through. 0x80003024 is the answer if the walk is right.
need "level 2  index 1"
need "level 0  index 3"
need "0x40403024 -> 0x80003024"   # no leading dash: grep would read it as an option
# A call in an argument list delivers the arguments around it (guest codegen; it used to give
# b=0x1 c=0x0 here, and shifted them by one when the fix was half done).
need "ArgEcho: a=0x11 b=0x22 c=0x33"
need "ArgEcho: a=0x1111 b=0x22 c=0x33"
# The float block is not silently gone when memory has the rows — the heading says how to get it
need "(f: float regs)"
# ...and the NAPOT decode of the entry the asm REPL just programmed: the trailing ones of the
# address are the size, which is the part worth testing.
need "pmp0 rwx NAPOT 0x80000000..0x80010000 (65536 bytes)"
# t6 survives a step now: it is the wrapper base register, and it used to be clobbered before it
# was ever saved, so this line ran and the value vanished.
need "t6   0000000000000000 -> 0000000000000003"
# ...and so do the float registers: fmv.d.x moves t6's bits into fa0, and the stepper says so.
need "fa0  0000000000000000 -> 0000000000000003"
# Tab straight after a question mark completes what AsmDoc can explain
need "asm> ?sfence.vma"
# Practice mode: the family, the instruction, and its man page — then you type it
need "-- shift 1 --"
need "-- shift 2 --"
# The float register as a NUMBER and as its fields, not just 16 hex digits
need "fa0  4010000000000000  4"
need "sign=0  exp=0x401 (2^2 x 1.mantissa)  mantissa=0x0000000000000"
# Disassembly from inside the stepper: a symbol resolved and instructions printed
need "asm> u AsmStep"
# ...and tracing a function this session compiled, instruction by instruction
need "asm REPL: tracing from 0x"
need "asm> t TraceMe"

# The layout, checked on the reconstructed screen: values in a column on the right, the REPL on
# the left. The terminal answered the size probe with 120x40, so the sidebar starts at column 76
# (120 - 44) and the text column is everything left of it.
# The layout, twice: at the terminal's first size and again after it was resized under us. The
# panes are repainted at the PROMPT, so each screen is true as of the last one before the marker;
# the lines printed after the loop exits (and QEMU's own exit message, which is the host talking
# and is wrapped to nothing) scroll the sidebar with no prompt left to put it back. That is the
# known cost of a sidebar on a terminal that scrolls whole rows.
check_layout() { # check_layout <sidebar-column> <stop-marker> <what> <float|memory>
if ! screen_num "$2" | SIDE="$1" EXPECT="$4" python3 -c '
import sys, os, re
side = int(os.environ["SIDE"])
rows = {}
for ln in sys.stdin.read().split("\n"):
    if not ln:
        continue
    n, _, text = ln.partition("|")
    rows[int(n)] = text
bad = []

def at(name):
    """(row, col) of a pane entry printed as name + padding + 16 hex digits."""
    pat = re.compile(r"\b" + re.escape(name) + r" +[0-9A-F]{16}")
    for r in sorted(rows):
        m = pat.search(rows[r])
        if m:
            return r, m.start()
    return None, None

GPR = ("zero ra sp gp tp t0 t1 t2 s0 s1 a0 a1 a2 a3 a4 a5 a6 a7 "
       "s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 t3 t4 t5 t6").split()
CSR = ["mcause", "mepc", "mtval", "mstatus"]
last_reg = 0
for nm in GPR + CSR:
    r, c = at(nm)
    if r is None:
        bad.append("register %s is not on screen" % nm)
    elif c < side:
        bad.append("%s is at column %d, left of the sidebar (%d)" % (nm, c, side))
    else:
        last_reg = max(last_reg, r)

# a0 was stepped twice by 0x10, and the pane says so
r, c = at("a0")
if r is not None and "0000000000000020" not in rows[r][c:c+40]:
    bad.append("a0 does not show 0000000000000020: %r" % rows[r][c:c+40])

# pc rides with the registers, where a debugger puts it
r, c = at("pc")
if r is None:
    bad.append("pc is not on screen")
elif c < side:
    bad.append("pc is at column %d, left of the sidebar (%d)" % (c, side))

# The blocks are RANKED by the rows available: registers and machine state always, then the 32
# float registers, and memory only if there is still room. So which of the two is on screen is
# itself the assertion — at 40 rows the floats displace memory, at 30 they do not fit at all.
mem = [r for r in sorted(rows) if rows[r][side:side+7].strip() == "memory"]
flt = [r for r in sorted(rows) if rows[r][side:side+6].strip() == "float"]
want = os.environ.get("EXPECT", "")
if want == "float":
    if not flt:
        bad.append("no float block in the sidebar")
    else:
        for nm in ("ft0", "fa0", "ft11"):
            r, c = at(nm)
            if r is None:
                bad.append("float register %s is not on screen" % nm)
            elif r < flt[0]:
                bad.append("%s at row %d is above the float heading (row %d)" % (nm, r, flt[0]))
    if mem:
        bad.append("memory pane is on screen with no rows to spare for it")
elif want == "memory":
    if not mem:
        bad.append("no memory pane in the sidebar")
    elif mem[0] <= last_reg:
        bad.append("memory pane at row %d is not below the registers (row %d)"
                   % (mem[0], last_reg))
    if flt:
        bad.append("float block is on screen at a size that cannot hold it")

# ...and the REPL text stayed in its own column. A row legitimately holds text on the left and
# pane on the right, so what must be clean is the gutter between them: the text column wraps one
# column short of the sidebar, so column side-1 is written by neither and must be blank on every
# row. A line of output that ran past its column would show up here first.
for r in sorted(rows):
    text = rows[r]
    if len(text) >= side and text[side-1] != " ":
        bad.append("row %d has %r in the gutter column %d: %r"
                   % (r, text[side-1], side-1, text[max(0, side-30):side+20]))
if bad:
    for b in bad:
        print("  " + b)
    sys.exit(1)
' >&2; then
  echo "FAIL asm-repl smoke -- the sidebar layout is wrong $3 (screen above)" >&2
  screen_num "$2" | sed -n 1,30p >&2
  fail=1
fi
}
check_layout 76 "resize-mark" "at 120x40" memory
# After the resize the terminal is 100 columns, so the sidebar starts at 56. Nothing else about
# the layout changes shape — which is the point: the same code laid it out at a size it was
# never told about at boot.
check_layout 56 "qemu-system-riscv64" "after the resize to 100 columns" memory

if [ "$fail" -ne 0 ]; then
  printf '%s\n' "$out" | grep -E 'A2|ExePutS|ans=|Except|Error|FAIL|OK|probe|Cmp|Compiler_RV' | head -40 | sed 's/^/  /' >&2
  printf '%s\n' "$out" | tail -30 | sed 's/^/  /' >&2
  exit 1
fi

echo "Asm-REPL-UI smoke: OK (history, Tab completion, register + memory panes, clean exit)"
