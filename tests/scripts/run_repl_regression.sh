#!/bin/bash
# RETIRED: worry_dream C guest deleted.
echo "error: run_repl_regression retired (worry_dream deleted); use run_repl_holyc_regression.sh" >&2
exit 2
# Hard regression gate for the bare-metal REPL. Unlike run_repl_smoke.sh (which can stay
# "green" while Src only FileWrite's without opening an editor), this script *requires*
# Src/Man/editor/trap/livedrv behaviors that users notice when broken.
#
# Fail loud: each expect_* greps the QEMU log; on miss, print the needle and a log tail.
# No pipefail traps for oracles — we always kill QEMU and judge the log file.
#
# See tests/REGRESSION.md for claimed-vs-real inventory and fix priorities.
set -eu
export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOT="$ROOT/bootstrap"
QEMU="${QEMU_SYSTEM_RISCV:-qemu-system-riscv64}"
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
else
  echo "error: need timeout or gtimeout" >&2
  exit 2
fi

make -C "$BOOT" -f Makefile.repl repl.elf >/dev/null

FAILS=0
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

expect_text() {
  local needle="$1"
  if ! grep -qF -- "$needle" "$log"; then
    echo "FAIL REPL regression — missing: $needle" >&2
    FAILS=$((FAILS + 1))
  fi
}

expect_re() {
  local re="$1"
  local desc="$2"
  if ! grep -qE -- "$re" "$log"; then
    echo "FAIL REPL regression — missing ($desc): /$re/" >&2
    FAILS=$((FAILS + 1))
  fi
}

# Reject the broken Src stub that only wrote Name.hc and returned (no editor).
reject_text() {
  local needle="$1"
  if grep -qF -- "$needle" "$log"; then
    echo "FAIL REPL regression — forbidden (Src stub regression): $needle" >&2
    FAILS=$((FAILS + 1))
  fi
}

input=""
add() { input+="$1"$'\n'; }

# ---- session ---------------------------------------------------------------
# Print + Atoi/Str2I64
# HolyC Print/StrPrintJoin/PjPutHex must work (aggressive Tier-1 peep once
# miscompiled `b[n++]=A+d-10` in PjPutHex → store-to-value / FAULT on Uf/Print).
add '"%s %d\n", "hi", 42;'
add 'Print("hello\n");'
add 'Print("%X\n", 255);'
add 'Uf("Print");'
add 'Atoi("123");'
add 'Atoi("-42");'
add 'Str2I64("0x10");'
add 'Str2I64("0b1010");'

# Ctrl-C interrupts a busy eval (early in session so the pipe still feeds RX).
# Catchable path: Break; throws 'Break' (same except_ch Ctrl-C uses inside try/catch).
add 'I64 __brk; for(__brk=0;;__brk++) {}'
input+=$'\x03'
add '"after-ctrlc\n";'
add 'try { Break; } catch { "caught-break\n"; };'

# SrcFile / Man for HolyC seeds (must name the originating unit)
add '"SymFile Print=%s\n", SymFile("Print");'
add '"SymFile print=%s\n", SymFile("print");'
add '"SymFile CLINT=%s\n", SymFile("CLINT");'
add '"SymFile Clint=%s\n", SymFile("Clint");'
add '"SrcFile Dir=%s\n", SrcFile("Dir");'
add '"SrcFile Print=%s\n", SrcFile("Print");'
add '"SrcFile Run=%s\n", SrcFile("Run");'
add '"SrcFile StrLen=%s\n", SrcFile("StrLen");'
add '"SrcFile MAlloc=%s\n", SrcFile("MAlloc");'
add 'Man("Dir");'
add 'Man("Print");'
add 'Man("Run");'
# Hardware/symbol topics (man_topics.hc): case-insensitive CLINT + programming needles
add 'Man("Clint");'
add 'Man("CLINT");'
add 'Man("MEM_CLINT");'
add 'Man("TimerArm");'
# PLIC/UART/Virtio MMIO pages exist (Man("PLIC") etc.); needles also on CLINT SEE ALSO

# Leftover holy_rt Man orphans must not pretend callability (GetRAX etc.)
add 'Man("GetRAX");'
add 'Man(0);'
add 'Man("");'
add '"FnAddr GetRAX=%d\n", FnAddr("GetRAX");'
# EdC is a live once-indirect repair hatch (ed.hc), not a doc-only c_api page
add '"SrcFile EdC=%s\n", SrcFile("EdC");'
add 'Man("EdC");'
add '"FnAddr EdC=0x%X\n", FnAddr("EdC");'

# FnSize must be >0 for HolyC-migrated symbols (smoke only grepped the label)
add '"FnSize Print=%d\n", FnSize("Print");'
add '"FnSize StrLen=%d\n", FnSize("StrLen");'
add '"FnSize MAlloc=%d\n", FnSize("MAlloc");'
add '"FnSize Run=%d\n", FnSize("Run");'
add '"FnSize TermKeyGet=%d\n", FnSize("TermKeyGet");'
add '"FnSize Src=%d\n", FnSize("Src");'
add '"FnSize Dir=%d\n", FnSize("Dir");'

# StrIMatch must be live HolyC (Funs filter hung on unresolved CALL_IMPORT before seed-owned Str*).
add '"FnAddr StrIMatch=%d\n", FnAddr("StrIMatch");'
add '"StrIMatch ab=%d\n", StrIMatch("ab","xxabxx",0)!=0;'
# Funs("Print") is filter-only (no Esc). Interactive Funs; still needs Esc — hang = QEMU timeout.
add 'Funs("Print");'
# Keep a brief interactive Funs+Esc regression; filter dump is the smoke-critical path.
add $'Funs();\n\x1b'

# Non-interactive Fun*/Callers (+ FileWrite name integrity for .funlist)
add 'FunsList();'
add 'FunWrite();'
add '"funlist len=%d\n", FileLen(".funlist");'
add 'Cat(".funlist");'
add '"FunSec Dir=%d Print=%d\n", FunSec("Dir"), FunSec("Print");'
add 'I64 B(){return 7;}'
add 'I64 A(){return B();}'
add 'A();'
add 'Callers("B");'
add '"Caller0=%s CallerCnt=%d\n", CallerName(0), CallerCnt();'

# for-init decl must see function params (BCPL ';' must not split signature from body)
add 'U32 dot_prod(U32 *a, U32 *b, U32 n)'
add '{'
add '  U32 sum = 0;'
add '  for (U32 i = 0; i < n; i++)'
add '    sum += a[i] * b[i];'
add '  return sum;'
add '}'
add 'U32 dp_a[4]; U32 dp_b[4]; dp_a[0]=1; dp_a[1]=2; dp_a[2]=3; dp_a[3]=4;'
add 'dp_b[0]=1; dp_b[1]=1; dp_b[2]=1; dp_b[3]=1;'
add 'dot_prod(dp_a, dp_b, 4);'

# MemMap/Regs/StkRep must be live C (not hollow HolyC label stubs)
add 'MemMap();'
add 'Regs();'
add 'StkRep();'
add 'Reg("mstatus");'
add 'Reg("sp");'
add 'Reg("a0");'
add 'Reg("x10");'
add 'Reg("fp");'
add 'Man("ABI");'
add 'Man("Reg");'
add '"MEM_HEAP=%X\n", MEM_HEAP;'
add '"GetMStatus=%X\n", GetMStatus();'
add 'RegHelp();'

# Inline asm{} must assemble and run (was silent no-op for unlabeled blocks).
# Imm subtract = addi with -imm (no subi). Same-line Reg/Regs so a7 snap is before REPL C clobber.
add 'I64 AsmS2Probe(){asm{li s2,0 addi s2,s2,3 mv a0,s2}}'
add '"asm_inline_s2=%d\n", AsmS2Probe();'
add 'asm { li s2, 10 }'
add 'asm { addi s2,s2,3 }'
add '"asm_repl_s2=%d\n", Reg("s2");'
add 'asm { li a0, 5 }; "asm_repl_a0=%d\n", Reg("a0");'
add 'asm { li a7, 20 addi a7,a7,-4 }; "asm_repl_a7=%d\n", Reg("a7");'
# ';' separators (TempleOS/gas) + li pseudo + R-type sub; same-line Regs must show a7=3 s2=1.
add 'Regs; asm { li s2,1; li a7,4; sub a7,a7,s2 }; Regs'
add 'asm { li s2,1; li a7,4; sub a7,a7,s2 }; "asm_semi_a7=%d asm_semi_s2=%d\n", Reg("a7"), Reg("s2");'
# After Regs restore, stub-entry a7 must still be readable by Reg on the same line.
add 'asm { li a7, 5 }; Regs; "post_regs_a7=%d\n", Reg("a7");'
# Encode-only system ops (do not execute sret/mret/ecall/ebreak unlabeled in M-mode).
add 'asm { SretEnc:: sret ret }'
add '"asm_sret_sz=%d\n", FnSize("SretEnc");'

# TermKeyGet / arrow constants (arrows must not be raw bytes that eat input)
add '"KEY_UP=%d KEY_DOWN=%d\n", KEY_UP, KEY_DOWN;'
add 'TermRows();'
add 'TermCols();'
# HolyC geometry (term.hc) Vi/EditHoly read after TermProbe (piped UART keeps 80x24; SetSize must stick)
add 'TermSetSize(40,100); TermRows()*1000+TermCols();'
add 'TermSetSize(24,80);'
add 'TermSize(100,40); TermRows()*1000+TermCols();'
add 'TermSize(80,24);'

# **** Src opens Vi on originating file and seeks to the def (JumpIdent + VCenter) ****
# Broken stub printed "Src: wrote Dir.hc" and returned — that is a hard fail below.
add 'Src("Dir");'
add $':q\r'
add 'Dir;'
add 'Cd("Tutorials");'
add 'Pwd();'
add 'Cat("A01_RV64I.hc");'
add 'Cd("/");'
add 'Cat("Lib/print.hc");'
add 'Src("Print");'
add $':q\r'
add '"after-Src-Print\n";'
add 'Src("TimerArm");'
add $':q\r'
add '"after-Src-TimerArm\n";'
add 'Src("Run");'
add $':q\r'
add '"after-Src-Run\n";'

# print.hc is 260 lines — windowed Vi/Edit must scroll past the 256-line buffer.
add $'Vi("print.hc");\nG\x1b:wq\r'
add $'Vi("dir.hc");\nG\x1b:wq\r'
add '"after-vi-G-dir\n";'
# Keys must follow a newline after `;` — same-line bytes are consumed by REPL readline.
add $'Edit("print.hc");\n'"$(printf '\x1b[6~%.0s' {1..15})"$'\030'

# Edit save path (scr.hc) + Vi save
add $'Edit("scr.hc");\nVisual editor works\017\030'
add 'Cat("scr.hc");'
add $'Vi("vf.hc");\niUartStr("vsmoke ");\x1b:wq\r'
add '"vf.hc len=%d\n", FileLen("vf.hc");'
add 'Run("vf.hc");'
add '"after-vsmoke\n";'

# Nested gd: jump to UartPut source, :q pops to jmp.hc, second :q leaves Vi
add $'Ed("jmp.hc");\na\nUartPut(65);\n.\nw\nq'
add $'Vi("jmp.hc");\ngd:q\r:q\r'
add '"after-nested-gd\n";'

# Same-file gd: def in buffer — seek in place (one :q exits Vi), no nest.
# `0gd` starts on whitespace before the call (forward WordIdent), not on the ident.
add $'Ed("samegd.hc");\na\nU0 SameGdFn()\n{\n}\nU0 SameGdCall()\n{\n  SameGdFn();\n}\n.\nw\nq'
add 'Run("samegd.hc");'
add $'Vi("samegd.hc");\n/SameGdFn();\r0gd:q\r'
add '"after-same-gd\n";'

# K = Man under cursor (vim keywordprg); any key dismisses, then :q
add $'Ed("mank.hc");\na\nPrint(1);\n.\nw\nq'
add $'Vi("mank.hc");\nKx:q\r'
add '"after-K-man\n";'

# Explicit Fmt: HolyC FileWrite is raw; Fmt must rewrite + print confirmation (not a stub).
add 'FileWrite("fmt_raw.hc","I64 Z(){return 1;}",18);'
add 'Cat("fmt_raw.hc");'
add 'Fmt("fmt_raw.hc");'
add 'Cat("fmt_raw.hc");'

# Vi INSERT Enter must split (not delete); Tab inserts 2-space indent (holyc_fmt)
add $'Vi("vsplit.txt");\niVSPLIT_AVSPLIT_B\x1b0lllllllli\r\x1b:wq\r'
add 'Cat("vsplit.txt");'
# Multi-line Enter: following lines must survive VInsL shift (single-line needle misses this)
add $'Vi("vsplit2.txt");\niKEEP_A\x1boKEEP_B\x1boKEEP_C\x1bggA\r\x1b:wq\r'
add 'Cat("vsplit2.txt");'
# Append a/A + typed text + Enter must keep rows below (truncate-before-VInsL used to clobber).
# Use single-quoted FileWrite so bash does not expand \n into real newlines mid-statement.
add 'FileWrite("vappA.txt","KEEP_A\nKEEP_B\nKEEP_C\n",21);'
add 'FileWrite("vappa.txt","KEEP_A\nKEEP_B\nKEEP_C\n",21);'
add $'Vi("vappA.txt");\nA_XX\rAPPENDED\x1b:wq\r'
add 'Cat("vappA.txt");'
add $'Vi("vappa.txt");\nja_YY\rAPP_A\x1b:wq\r'
add 'Cat("vappa.txt");'
add $'Vi("vtab.txt");\ni\tVTAB_MARK\x1b:wq\r'
add 'Cat("vtab.txt");'
# Case-insensitive Tab completion: REPL `man`→Man; Vi/Edit mid-token → Print
add $'man\t("Print");'
add $'Vi("vcomp.txt");\nipri\t_VCI\x1b:wq\r'
add 'Cat("vcomp.txt");'
add $'Edit("ecomp.txt");\npri\t_ECI\017\030'
add 'Cat("ecomp.txt");'
# MEM_* #define Tab: live define_table (csr.hc) — prompt fill + CompCollectSyms probe + Vi
add $'Print("MEM_PLIC=%X\\n", MEM_PL\t);'
add $'Print("MEM_UART=%X\\n", MEM_UA\t);'
# CompCollectSyms returns CompN (ans=); +const avoids colliding with other ans=1
add 'CompCollectSyms("MEM_UART", 8)+1000;'
add 'CompCollectSyms("MEM_PL", 6)+2000;'
add $'Vi("vmem.txt");\niMEM_CL\t\x1b:wq\r'
add 'Cat("vmem.txt");'
# Asm{} Tab: unique fills (slli/a7/mst) + list needles from add\t / a\t
# Note: $'...' expands \n — keep format strings free of \n (use plain add for those).
add $'I64 AsmTabOp(){asm{slli\t a0,zero,0 addi a0,a0,3}} "asm_tab_op=%d", AsmTabOp();'
add $'I64 AsmTabReg(){asm{li a7\t,7 mv a0,a7}} "asm_tab_reg=%d", AsmTabReg();'
add $'I64 AsmTabCsr(){asm{csrr a0, mst\t}} "asm_tab_csr=%d", AsmTabCsr();'
add $'asm { add\t };'
add $'asm { li a\t };'
add $'Vi("vasm.txt");\niasm { add\ti a0, a0, 1 }\x1b:wq\r'
add 'Cat("vasm.txt");'
# Edit (C) Tab indent + Ed append Tab indent
add $'Edit("etab.txt");\n\tETAB_MARK\017\030'
add 'Cat("etab.txt");'
add $'Ed("edtab.txt");\na\n\tEDTAB_MARK\n.\nw\nq'
add 'Cat("edtab.txt");'
# Multiline REPL (... prompt): Tab → 2sp indent; mid-token Tab still completes
add $'U0 MlTabFn()\n{\n\tpri\tnt("  MLTAB_MARK\\n");\n}\n'
add 'MlTabFn();'
# Vi w word motion + u undo
add $'Vi("vw.txt");\niONE TWO THREE\x1b0wwx\x1b:wq\r'
add 'Cat("vw.txt");'
add $'Vi("vundo.txt");\niUNDO_GONE\x1bu:wq\r'
add '"ulen=%d\n", FileLen("vundo.txt");'
# Vi $ → EOL then x; J joins with a space
add $'Vi("vdollar.txt");\niABCDE\x1b0$x\x1b:wq\r'
add 'Cat("vdollar.txt");'
add $'Vi("vjoin.txt");\niFOO\x1boBAR\x1bkJ\x1b:wq\r'
add 'Cat("vjoin.txt");'
# Counts, yank/put, search, visual delete, :e
add $'Vi("vcount.txt");\niAA BB CC DD\x1b02dw\x1b:wq\r'
add 'Cat("vcount.txt");'
add $'Vi("vyank.txt");\niYANKME\x1b0yyp\x1b:wq\r'
add 'Cat("vyank.txt");'
add $'Vi("vsearch.txt");\nifoo bar foo\x1b0/foo\rn\x1brX\x1b:wq\r'
add 'Cat("vsearch.txt");'
add $'Vi("vvis.txt");\niABCDEF\x1b0lvllld\x1b:wq\r'
add 'Cat("vvis.txt");'
add $'Vi("ve1.txt");\niFROM_E\x1b:wq\r'
add $'Vi("ve2.txt");\niXXXX\x1b:e ve1.txt\ryy:e ve2.txt\rp:wq\r'
add 'Cat("ve2.txt");'

# Trap / Ecall
add $'Ed("ontrap.hc");\na\nI64 Zap(I64 c,I64 e,I64 t){ "ZAP-HIT "; return 0; }\n.\nw\nq'
add 'Run("ontrap.hc");'
add 'TrapInit();'
add 'SetTrap("Zap");'
add 'Ecall();'

# Memfs change journal (P0/P1): FileWrite after boot FsEpochSeal → FsChanges/FsLog
add 'FileWrite("Home/jlog.hc","z",1);'
add 'FsChanges;'
add 'FsLog(4);'
add 'FsCheckpoint("p1");'
add 'FileWrite(".p1q","n",1);'
add 'FsChanges(-1, 1);'

# Livedrv: edit uart.hc live, prove Run after edit still works
add 'Run("uart.hc");'
add 'UartStr("livedrv ");'
add $'Ed("uart.hc");\n150a\n  if (ch>=97 && ch<=122) ch -= 32;\n.\nw\nq'
add 'Run("uart.hc");'
add 'UartStr("livedrv ");'

# Sentinel
add '4919;'

# Default virt RAM is 128MiB (enough for memfs @0x87800000). Do not require -m 256M.
# Keep stdin open until QEMU exits — a bare pipe EOF mid-session drops unread lines
# (Vi redraw stalls consume input; printf closing the pipe looked like early EOF).
fifo="$(mktemp -u)"
mkfifo "$fifo"
$TIMEOUT_CMD 360 "$QEMU" -M virt -bios none -kernel "$BOOT/repl.elf" -nographic <"$fifo" >"$log" 2>&1 &
qpid=$!
(
  printf '%s' "$input"
  while kill -0 "$qpid" 2>/dev/null; do sleep 0.05; done
) >"$fifo" &
feeder=$!
for ((t = 0; t < 3600; t++)); do
  if grep -q 'ans=0x0000000000001337' "$log" 2>/dev/null; then break; fi
  kill -0 "$qpid" 2>/dev/null || break
  sleep 0.1
done
kill "$qpid" 2>/dev/null || true
wait "$qpid" 2>/dev/null || true
kill "$feeder" 2>/dev/null || true
wait "$feeder" 2>/dev/null || true
rm -f "$fifo"

# Strip ANSI escapes + CR so Vi/Edit status lines still match expect_* greps.
sed 's/\x1b\[[0-9;]*[A-Za-z]//g' "$log" | tr -d '\r' >"${log}.clean"
mv "${log}.clean" "$log"

# ---- oracles ---------------------------------------------------------------
expect_text 'hi 42'
expect_text 'hello'
expect_text 'FF'                         # Print("%X\n", 255) via PjPutHex
expect_text '; Print ('                  # Uf header (Print/PjPutHex live)
expect_text 'ans=0x000000000000007b'   # Atoi 123
expect_text 'ans=0xffffffffffffffd6'   # Atoi -42
expect_text 'ans=0x0000000000000010'   # Str2I64 0x10
expect_text 'ans=0x000000000000000a'   # Str2I64 0b1010

expect_text 'SymFile Print=print.hc'
expect_text 'SymFile print=print.hc'
expect_text 'SymFile CLINT=man_topics.hc'
expect_text 'SymFile Clint=man_topics.hc'
expect_text 'SrcFile Dir=dir.hc'
expect_text 'SrcFile Print=print.hc'
expect_text 'SrcFile Run=run.hc'
expect_text 'SrcFile StrLen=str.hc'
expect_text 'SrcFile MAlloc=mem.hc'
expect_text 'SrcFile EdC=ed.hc'
expect_text 'Man: no such symbol: GetRAX'
expect_text 'Man: nil'
expect_text 'FnAddr GetRAX=0'
expect_text '(HolyC)'                 # Man Dir/Print/EdC header
expect_text 'EdC - C line editor'     # Man EdC from ed.hc
expect_re 'FnAddr EdC=0x[1-9a-fA-F][0-9a-fA-F]*' 'EdC live HTT_FUN'
# Man("Clint")/CLINT topic teaches mtime/mtimecmp + TimerArm (+ raw MMIO)
expect_text 'MEM_MTIME'               # CLINT mtime symbol
expect_text 'MEM_MTIMECMP'            # CLINT mtimecmp symbol
expect_text 'TimerArm'                # programming path / cross-ref
expect_text 'Core-Local Interruptor'  # CLINT NAME line
expect_text 'MEM_CLINT - base address' # Man("MEM_CLINT") topic
expect_text 'TimerArm - program CLINT' # Man("TimerArm") from trap.hc
expect_text 'MEM_MTIME+1000000'       # CLINT MMIO read example
expect_text 'wake when mtime catches up'    # CLINT MMIO alarm poke
expect_text 'MEM_PLIC_CLAIM_OFF'      # PLIC claim/complete MMIO
expect_text 'UART_LSR_THRE'           # 16550 LSR/THR poke
expect_text 'VIRTIO_MAGIC'            # virtio-mmio identity read
# EXAMPLES sections on high-traffic Man pages (plain + copy-paste recipe)
expect_text 'EXAMPLES'                # Man pages include EXAMPLES
expect_text 'Print("hello\n");'       # Man("Print") runnable example
expect_text 'TimerArm(1000000);'      # Man("Clint") / TimerArm examples

expect_re 'FnSize Print=[1-9][0-9]*' 'FnSize Print>0'
expect_re 'FnSize StrLen=[1-9][0-9]*' 'FnSize StrLen>0'
expect_re 'FnSize MAlloc=[1-9][0-9]*' 'FnSize MAlloc>0'
expect_re 'FnSize Run=[1-9][0-9]*' 'FnSize Run>0'
expect_re 'FnSize TermKeyGet=[1-9][0-9]*' 'FnSize TermKeyGet>0'
expect_re 'FnSize Src=[1-9][0-9]*' 'FnSize Src>0'
expect_re 'FnSize Dir=[1-9][0-9]*' 'FnSize Dir>0'

expect_re 'FnAddr StrIMatch=[1-9][0-9]*' 'StrIMatch live HTT_FUN'
expect_text 'StrIMatch ab=1'
expect_text 'Funs  filter: Print'
expect_text 'Funs  filter:'

expect_text 'wrote .funlist'
expect_re 'funlist len=[1-9][0-9]*' 'FileLen(.funlist)>0'
expect_text 'FunPick'
expect_text 'FunsList'
expect_text 'Src-editable'
expect_text 'FunSec Dir=2 Print=3'
expect_text 'ans=0x0000000000000007'
expect_text 'callers of B'
expect_text ') A'
expect_text 'Caller0=A'
expect_re 'CallerCnt=[1-9]' 'CallerCnt>0 after CallersScan'
expect_text 'ans=0x000000000000000a'   # dot_prod 1+2+3+4 after for-init decl

# Live MemMap/Regs/StkRep (reject hollow HolyC stubs that printed labels only)
reject_text 'see C MemMap for live bytes'
reject_text 'Regs (HolyC stub'
reject_text '(StkRep stub)'
expect_text 'code_mem'
expect_re 'MEM_CODE.*/[0-9]+ B used' 'MemMap live JIT usage'
expect_text 'MEM_HEAP'
# MemMap driver column (region ↔ HolyC Drv)
expect_re 'RVUart|16550' 'MemMap UART driver'
expect_re 'RVTimer|CLINT' 'MemMap CLINT/RVTimer'
expect_text 'RVPlic'
expect_text 'Dig-down'
expect_text 'mstatus'
expect_text 'stack pointer'
expect_text 'return address'
expect_text 'x10/a0'
expect_text 'arg/ret (caller-saved)'
expect_text 'saved / frame ptr (fp)'
expect_text '(fp is alias for s0/x08)'
expect_text 'RISC-V integer register naming'
expect_text 'caller-saved'
expect_text 'callee-saved'
expect_text 'a0..a7'
expect_text 'Reg - read one GPR'
expect_text 'GetMStatus'
expect_text 'RegHelp'
expect_text 'asm_inline_s2=3'
expect_text 'asm_repl_s2=13'
expect_text 'asm_repl_a0=5'
expect_text 'asm_repl_a7=16'
expect_text 'asm_semi_a7=3 asm_semi_s2=1'
# Same-line Regs after semicolon asm (a7 is caller-saved across REPL line boundaries).
expect_text '  x17/a7 = 0x0000000000000003  arg/ret (caller-saved)'
expect_text '  x18/s2 = 0x0000000000000001  saved (callee-saved)'
expect_text 'post_regs_a7=5'
expect_re 'asm_sret_sz=[1-9]' 'labeled sret encodes'
expect_re 'MEM_HEAP=0*86000000' 'MEM_HEAP symbol'
expect_text 'stack:'

expect_text 'KEY_UP=256 KEY_DOWN=257'
expect_text 'ans=0x0000000000000018'  # TermRows 24
expect_text 'ans=0x0000000000000050'  # TermCols 80
expect_text 'ans=0x0000000000009ca4'  # TermSetSize(40,100) → rows*1000+cols
expect_text 'ans=0x0000000000009ca4'  # TermSize(100,40) cols-first same geometry

# Src opened Vi on the real seed file and sought the def (not Ln 1 / stub write)
reject_text 'Src: wrote Dir.hc'
reject_text 'Src: wrote Print.hc'
reject_text 'Src: wrote Run.hc'
expect_text '-- NORMAL -- dir.hc'
expect_text '-- NORMAL -- print.hc'
expect_re '-- NORMAL -- print\.hc Ln 24[0-9]/' 'Src(Print) on U0 Print def'
expect_re '-- NORMAL -- dir\.hc Ln 5[0-9][0-9]/' 'Src(Dir) windowed seek past 256'
expect_re '-- NORMAL -- print\.hc Ln 260/' 'Vi(print.hc) G reaches last line'
expect_re 'print\.hc  ln 260/260' 'Edit(print.hc) PGDN reaches last line'
expect_text '-- NORMAL -- trap.hc'
expect_re '-- NORMAL -- trap\.hc Ln 17[0-9]/' 'Src(TimerArm) on TimerArm def'
expect_text '-- NORMAL -- run.hc'
expect_text 'after-Src-Print'
expect_text 'after-Src-TimerArm'
expect_text 'after-Src-Run'
# Dir listing still works after Src(Dir) — hierarchical (Lib/ not a flat dir.hc line)
expect_text ' Lib/'
expect_text ' Tutorials/'
expect_text 'cwd: /Tutorials/'
expect_text 'A01_RV64I.hc -- Part A1'

expect_text 'wrote scr.hc'
expect_text 'Visual editor works'
expect_re 'vf.hc len=[1-9][0-9]*' 'FileLen(vf.hc)>0'
# vsmoke must appear from Run, not only from the Vi insert screen paint
expect_text 'vsmoke '
expect_text 'after-vsmoke'
expect_text '-- NORMAL -- uart.hc'   # nested gd opened UartPut's file
expect_text '-- NORMAL -- jmp.hc'    # :q restored parent buffer
expect_text 'after-nested-gd'
expect_re '-- NORMAL -- samegd\.hc Ln 1/' 'same-file 0gd: forward ident + seek to def'
expect_text 'after-same-gd'          # same-file gd: one :q left Vi
expect_re '-- NORMAL -- dir\.hc Ln 53[0-9]/53[0-9]' 'Vi G scrolls to EOF past 256-line window'
expect_text 'after-vi-G-dir'
expect_text 'Print - formatted print to the UART'  # Vi K → Man("Print")
expect_text 'after-K-man'
expect_text 'I64 Z(){return 1;}'
expect_text 'Fmt: fmt_raw.hc (24 bytes, rewritten)'
expect_text $'I64 Z()\n{\n  return 1;\n}'
expect_text 'VSPLIT_A'
expect_text 'VSPLIT_B'
expect_text 'KEEP_A'
expect_text 'KEEP_B'
expect_text 'KEEP_C'
expect_text 'KEEP_A_XX'            # A + type + Enter: prefix line
expect_text 'APPENDED'             # A + type + Enter: new line
expect_text 'K_YY'                 # a mid-line + Enter: prefix of KEEP_B
expect_text 'APP_AEEP_B'           # a mid-line + Enter: typed + suffix
expect_text '  VTAB_MARK'
expect_text 'Print - formatted print to the UART'  # man\t → Man("Print") and/or Vi K
expect_text 'Print_VCI'
expect_text 'Print_ECI'
expect_re 'MEM_PLIC=[Cc]000000' 'Tab MEM_PL → MEM_PLIC'
expect_re 'MEM_UART=10000000' 'Tab MEM_UA → MEM_UART'
expect_text 'ans=0x00000000000003e9' # CompCollectSyms(MEM_UART)+1000 → 1001
expect_re 'ans=0x00000000000007d[0-9a-fA-F]' 'CompCollectSyms(MEM_PL)+2000 (≥1 PLIC*)'
expect_text 'MEM_CLINT'            # Vi Tab MEM_CL → MEM_CLINT (or longer common pfx)
expect_text 'asm_tab_op=3'
expect_text 'asm_tab_reg=7'
expect_text 'asm_tab_csr='          # csrr mstatus completed+ran
expect_text '  addi'                # add\t listed addi among opcodes
expect_text '  a0'                  # a\t listed a0 among regs
expect_text 'addi a0, a0, 1'        # Vi asm Tab → addi
expect_text '  ETAB_MARK'
expect_text '  EDTAB_MARK'
expect_text '  MLTAB_MARK'
expect_text 'ONE TWO HREE'
expect_re 'ulen=[01]' 'Vi u cleared insert (empty or lone newline)'
expect_text 'ABCD'
expect_text 'FOO BAR'
expect_text 'CC DD'
expect_text 'YANKME'
expect_re 'YANKME.*YANKME' 'yy/p duplicated line'
expect_re 'foo bar Xoo|Xoo bar foo' 'Vi /foo n rX (IRQ timing may hit 1st or 2nd match)'
expect_text 'AF'
expect_text 'FROM_E'
expect_text 'ZAP-HIT'
expect_text 'W  Home/jlog.hc'
expect_text 'fs log tail'
expect_text 'fs checkpoint 1'
expect_text 'W  .p1q'
expect_text 'Interrupted'
expect_text 'after-ctrlc'
expect_text 'caught-break'
expect_text 'livedrv '
expect_text 'LIVEDRV '

expect_text 'ans=0x0000000000001337'

if [ "$FAILS" -ne 0 ]; then
  echo "FAIL REPL regression — $FAILS check(s) failed" >&2
  echo "--- log tail ---" >&2
  tail -n 120 "$log" >&2
  cp "$log" "/tmp/repl-regression-last.log" 2>/dev/null || true
  exit 1
fi

echo "OK   REPL regression: Src/Man/SrcFile, Atoi, Fun*/Callers/CallerName, MemMap/Regs/Reg/CSR, StkRep, Trap, Ctrl-C, Edit/Vi/Ed (Tab CI complete/indent/asm{}/split/w/\$/J/u), livedrv, FnSize>0"
echo "REPL regression: OK"
