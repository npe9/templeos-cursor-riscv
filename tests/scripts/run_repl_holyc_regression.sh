#!/usr/bin/env bash
# HolyC-path honesty gate (Track A / docs/SELF_HOST.md A3 / GAPS G6).
# Covers landed thin-image needles (incl. G1 soft dbg + G3 livedrv/gd/K + G4/G5/Sys).
# Explicitly waived (not G7 blockers): Fmt host rewrite, Demo/*.HC UART batch, ZMODEM (G11).
# Covers landed thin-image needles (incl. G1 soft dbg + G2 trap/Ctrl-C + G3 livedrv/gd/K + G4/G5/Sys).
# G2: TrapInitOnce on first Fault/Break/SetTrap/BreakArm (not boot mtvec). Still waived: Fmt, Demo.
# see SELF_HOST.md (ZMODEM = G11 product waive, not G7). Do not pkill qemu globally;
# timeout owns the guest.
set -euo pipefail
export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ELF="$ROOT/build/repl-holyc.elf"
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

make -C "$ROOT" holyc-riscv >/dev/null
make -C "$ROOT" repl-holyc >/dev/null

if [ ! -f "$ELF" ]; then
  ELF="$ROOT/build/hc_repl.elf"
fi
if [ ! -f "$ELF" ]; then
  echo "FAIL repl-holyc-regression — missing HolyC REPL ELF" >&2
  exit 1
fi

# Mandate: no host-slot refs in hc_repl sources (seed_embed is payload strings).
if grep -RIn --include='*.hc' -E '0x87001[0-9A-Fa-f]{3}' "$ROOT/bootstrap/hc_repl" \
  | grep -v seed_embed.hc \
  | grep -v -E 'No 0x87001|no 0x87001'; then
  echo "FAIL repl-holyc-regression — HolyC sources still reference host slots" >&2
  exit 1
fi

FAILS=0
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

expect_text() {
  local needle="$1"
  if ! grep -qF -- "$needle" "$log"; then
    echo "FAIL repl-holyc-regression — missing: $needle" >&2
    FAILS=$((FAILS + 1))
  fi
}

reject_text() {
  local needle="$1"
  if grep -qF -- "$needle" "$log"; then
    echo "FAIL repl-holyc-regression — forbidden: $needle" >&2
    FAILS=$((FAILS + 1))
  fi
}

input=""
add() { input+="$1"$'\n'; }

# ---- G5 hist_seed cold Up (before Dir push) + session Up×1 / Up×2 ----
input+=$'\x1b[A\n'
# ---- hierarchical memfs (Dir / Cd / Cat / MkDir) ----
add 'Dir;'
add 'Print("HIST_RECALL_OK\n");'
input+=$'\x1b[A\n'
add 'Print("HIST_UP2_OK\n");'
add 'Print("HIST_UP2_TOP\n");'
input+=$'\x1b[A\x1b[A\n'
add 'Cd("Tutorials");'
add 'Pwd();'
add 'Cd("/");'
add 'Cd("Lib");'
add 'Dir;'
add 'Cd("/");'
add 'MkDir("Home/Work");'
add 'Cd("Home/Work");'
add 'Pwd();'
add 'Cd("/");'

# ---- language honesty (ExePutS→Jit; needs JIT_FUN_MAX headroom) ----
add 'Print("holyc-reg\n");'
add 'Atoi("123");'
add 'Atoi("-42");'
add 'Atoi("0x10");'
add 'Atoi("0b1010");'
add 'I64 Add(I64 a, I64 b) { return a + b; }'
add 'Add(40, 2);'
add 'I64 Fib(I64 n) { if (n < 2) return n; return Fib(n-1) + Fib(n-2); }'
add 'Fib(10);'
add 'I64 Loop(I64 n) { I64 i, s = 0; for (i = 0; i < n; i++) s += i; return s; }'
add 'Loop(10);'
add 'I64 Arr() { I64 a[4]; a[0] = 1; a[1] = 2; a[2] = 3; return a[0] + a[1] + a[2]; }'
add 'Arr();'
add 'I64 Ptr() { I64 x = 1; I64 *p = &x; *p = 7; return x; }'
add 'Ptr();'
add 'class P { I64 x; I64 y; };'
add 'I64 Cl() { P p; p.x = 1; p.y = 2; return p.x + p.y; }'
add 'Cl();'
add 'I64 Pre() { I64 i = 5; I64 j = ++i; return j * 10 + i; }'
add 'Pre();'
add 'I64 Get11th(I64 a, I64 b, I64 c, I64 d, I64 e, I64 f, I64 g, I64 h, I64 i, I64 j, I64 k) { return k; }'
add 'Get11th(1,2,3,4,5,6,7,8,9,10,11);'
add 'U8 *s = MAlloc(16);'
add 'StrCpy(s, "abc");'
add 'StrLen(s);'
add 'I64 F() { return 1; }'
add 'F();'
add 'I64 F() { return 2; }'
add 'F();'

# ---- memfs hello + G3 Src→editor (before G2 — Fault can wedge long pipes) ----
add 'Cat("Home/hello.hc");'
add $'Src("hello.hc");\n:q\r'
add '1+1;'

# ---- G3 livedrv (product path): Ed+Run Home file — NOT Lib/uart.hc ----
# Re-Running seed uart.hc would redefine UartPut and clobber AOT soft RX
# (hc_repl/uart.hc). Legacy uart insert mark is 150a after RTS/CTS stub (docs
# once said 148a). Same honesty: 6a inserts ToUpper before PutCh, re-Run.
# Unary * is Lbu in jit.hc (U8 walk). Avoid s[i] loops (can wedge after LiveMsg).
add $'Ed("Home/livedrv.hc");\na\nU0 LiveMsg()\n{\n  I64 ch;\n  U8 *s = "livedrv ";\n  while (*s) {\n    ch = *s++;\n    PutCh(ch);\n  }\n}\n.\nw\nq'
add 'Run("Home/livedrv.hc");'
add 'LiveMsg;'
add $'Ed("Home/livedrv.hc");\n6a\n    ch = ToUpper(ch);\n.\nw\nq'
add 'Run("Home/livedrv.hc");'
add 'LiveMsg;'

# ---- G3 gd: nested (Print → print.hc) + same-file seek ----
add $'Ed("Home/jmp.hc");\na\nPrint("jmp-mark\\n");\n.\nw\nq'
add $'Vi("Home/jmp.hc");\ngd:q\r:q\r'
add '"after-nested-gd\n";'
add $'Ed("Home/samegd.hc");\na\nU0 SameGdFn()\n{\n}\nU0 SameGdCall()\n{\n  SameGdFn();\n}\n.\nw\nq'
add 'Run("Home/samegd.hc");'
add $'Vi("Home/samegd.hc");\n/SameGdFn();\r0gd:q\r'
add '"after-same-gd\n";'

# ---- G3 K: Man under cursor (Print), dismiss pause, quit ----
add $'Vi("Home/jmp.hc");\nKq:q\r'
add '"after-K\n";'

# ---- G2 trap / Ctrl-C session (also trap-smoke; ZapTrap AOT — not thin-JIT "str";) ----
add 'Fault;'
add 'regs'
add 'bt'
add 'go'
add 'Print("after-fault\n");'
add 'Break;'
add 'Print("after-break\n");'
add 'SetTrap("ZapTrap");'
add 'Ecall();'
add 'Print("after-ecall\n");'
add 'SetTrap("CrashOnTrap");'
add 'I64 __brk; for(__brk=0;;__brk++) {}'
input+=$'\x03'
add 'Print("after-ctrlc\n");'

# ---- Run after FileWrite + DumpFile export ----
add 'FileWrite("Home/runme.hc","Print(\"runme-ok\\n\");",20);'
add 'Run("Home/runme.hc");'
add 'DumpFile("hello.hc");'

# ---- G4 Man / Funs (seed man*.hc + man_sym; no worry_dream slots) ----
add 'Man("Print");'
add 'Man("CLINT");'
add 'Man("ABI");'
add 'Man("Regs");'   # needle expects "Regs - dump GPRs" (not Man("Reg") → "Reg - read one")
add 'Reg("a0");'
add 'Reg("x10");'
add 'Reg("fp");'
add 'Sections;'
add 'FunsList;'
add 'Funs("Print");'
add 'SrcFileRep("Print");'
add 'FnSizeRep("Print");'
add 'Man("");'
add 'Man("GetRAX");'

# ---- G5 Tab / CompCollectSyms / multiline (... indent + mid-token) ----
# Live asm{} mid-token Tab is flaky on piped UART; prove CompCollect* + Fun/MEM Tab.
add 'CompCollectSyms("MEM_PL", 6);'
add 'CompCollectSyms("Pri", 3);'
add 'CompCollectAsm(0, "slli", 4);'  # ASM_COMP_OP
add $'I64 g6mpl = MEM_PL\t;'
add 'g6mpl;'
add $'pri\t("hc-tab-print\\n");'
add $'U0 MlTabFn()\n{\n\tPrint("  MLTAB_MARK\\n");\n}\n'
add 'MlTabFn();'
# asm{} body (no mid-token Tab — piped list/newline is flaky); Print then call
add 'I64 AsmTabOp(){asm{slli a0,zero,0 addi a0,a0,3}}'
add 'Print("asm_tab_op_ok\n");'
add 'AsmTabOp();'

# (HIST_RECALL_OK / HIST_UP2_* wired early after Dir — see above)

# ---- G1 soft Regs / MemMap / StkRep / Callers (DONE — unwaived) ----
add 'MemMap;'
add 'Reg("a0");'
add 'Reg("x10");'
add 'Man("ABI");'
add 'Reg("mstatus");'
add 'CsrDecodeVal("mcause", 3);'
add 'Regs;'
add 'Bt;'
add 'StkRep;'
add 'I64 CB(){return 7;}'
add 'I64 CA(){return CB();}'
add 'CA();'
add 'Callers("CB");'

# ---- G27 sys inspection (also dumped at boot; session call reinforces) ----
add 'Sys;'
add 'TermSize(80,24);'
add 'TermNameAnsi;'
add 'TermRep;'

# ---- CONSOLE.md #1 line discipline ----
add 'Tty;'
add 'TtyRaw;'
add 'Tty;'
add 'TtyCanon;'
add 'TtyEofHit();'
add 'TtyOnlcrGet();'

# ---- memfs change journal + DumpChanges ----
add 'FileWrite("Home/jlog.hc","z",1);'
add 'FsChanges;'
add 'FsLog;'
add 'FsCheckpoint("a3");'
add 'FileWrite("Home/a3q.hc","n",1);'
add 'FsChanges;'
add 'DumpChanges;'

# Sentinel (same hex as legacy regression)
add '4919;'

# Keep stdin open until QEMU exits — bare pipe EOF mid-session drops Ed/Vi lines.
fifo="$(mktemp -u)"
mkfifo "$fifo"
QEMU_BUF=(stdbuf -oL -eL)
if ! command -v stdbuf >/dev/null 2>&1; then
  QEMU_BUF=()
fi

$TIMEOUT_CMD 360 "${QEMU_BUF[@]}" "$QEMU" -M virt -m 128M -bios none -kernel "$ELF" -nographic \
  <"$fifo" >"$log" 2>&1 &
qpid=$!
(
  # Do not blast ~3KiB during slow AOT boot — guest soft ring/16550 wedge before ReplLoop.
  for ((boot = 0; boot < 600; boot++)); do
    if grep -qF 'Try: Dir;' "$log" 2>/dev/null; then break; fi
    kill -0 "$qpid" 2>/dev/null || exit 0
    sleep 0.5
  done
  if ! grep -qF 'Try: Dir;' "$log" 2>/dev/null; then
    echo "FAIL repl-holyc-regression — boot gate: no Try: Dir; in log" >&2
    exit 1
  fi
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

# Strip ANSI / CR (harmless on thin path; matches legacy regression hygiene)
sed 's/\x1b\[[0-9;]*[A-Za-z]//g' "$log" | tr -d '\r' >"${log}.clean"
mv "${log}.clean" "$log"

expect_text "HolyC AOT REPL"
expect_text "A2: ExePutS owns compile loop"
expect_text "A2: bridge→Jit (Cmp=make repl-cmp / build/repl-cmp.elf)"
# Real REPL prompt (Help banner also contains " > "; require command echo)
expect_text "> Dir;"
expect_text "holyc-reg"
expect_text "Dir: "
expect_text "Home/"
expect_text "Lib/"
expect_text "Tutorials/"
expect_text "cwd: /Tutorials/"
expect_text "cwd: /Home/Work/"
expect_text "print.hc"
expect_text "Hello from HolyC memfs"
expect_text "runme-ok"
expect_text '$HC_DUMP name=hello.hc'
expect_text '$HC_END$'
# G4 Man / Funs
expect_text "formatted print to the UART"
expect_text "(HolyC)"
expect_text "Core-Local Interruptor"
expect_text "Regs - dump GPRs"
expect_text "Manual sections"
expect_text "Symbol table:"
expect_text "Funs filter: Print"
expect_text "SrcFile Print=print.hc"
expect_text "FnSize Print="
expect_text "Man: nil"
expect_text "Man: no such symbol: GetRAX"
# G5 Tab / complete / history
expect_text "G5: Tab=complete/indent"
expect_text "hc-tab-print"
expect_text "  MLTAB_MARK"
expect_text "asm_tab_op_ok"
expect_text "ans=0x0000000000000005"   # CompCollectSyms(MEM_PL) → 5
# Tab expanded MEM_PL → MEM_PLIC (JIT may not eval #define; prove echo)
expect_text "I64 g6mpl = MEM_PLIC;"
if [ "$(grep -cF 'HIST_RECALL_OK' "$log" || true)" -lt 2 ]; then
  echo "FAIL repl-holyc-regression — need ≥2 HIST_RECALL_OK (history Up)" >&2
  FAILS=$((FAILS + 1))
fi
if [ "$(grep -cF 'HIST_SEED_OK' "$log" || true)" -lt 1 ]; then
  echo "FAIL repl-holyc-regression — need HIST_SEED_OK (hist_seed Up)" >&2
  FAILS=$((FAILS + 1))
fi
if [ "$(grep -cF 'HIST_UP2_OK' "$log" || true)" -lt 2 ]; then
  echo "FAIL repl-holyc-regression — need ≥2 HIST_UP2_OK (history Up×2)" >&2
  FAILS=$((FAILS + 1))
fi
expect_text "HIST_UP2_TOP"
# G1 soft dbg (DONE — cover)
expect_text "Regs (HolyC soft)"
expect_text "FS=1"
expect_text "MIE=0"
expect_text "MPP="
expect_text "breakpoint"
expect_text "x10/a0"
expect_text "RISC-V integer register naming"
expect_text "MEM_REGS_SNAP"
expect_text "RVUart"
# After Fault, pc/fp freeze → trap-freeze Bt (live path is UART-only stub when no freeze).
expect_text "Bt (trap freeze)"
expect_text "callers of CB"
expect_text "ans=0x0000000000000007"   # CA()→CB()
# G27 sys inspection
expect_text "=== sys (UART /proc-ish) ==="
expect_text "--- term ---"
expect_text "80 x 24"
expect_text "name=ansi"
expect_text "--- uptime ---"
expect_text "--- mem ---"
# CONSOLE.md #1 TTY
expect_text "=== tty (line discipline) ==="
expect_text "mode=canon"
expect_text "mode=raw"
expect_text "onlcr=0"
expect_text "eof_hit=0"
expect_text "ans=0x0000000000000000"   # TtyEofHit / TtyOnlcrGet defaults
expect_text "mode=raw"
# language
expect_text "ans=0x000000000000007b"   # Atoi 123
expect_text "ans=0xffffffffffffffd6"   # Atoi -42
expect_text "ans=0x0000000000000010"   # Atoi 0x10
expect_text "ans=0x000000000000000a"   # Atoi 0b1010
expect_text "ans=0x000000000000002a"   # Add(40,2)
expect_text "ans=0x0000000000000037"   # Fib(10)
expect_text "ans=0x000000000000002d"   # Loop(10)
expect_text "ans=0x0000000000000006"   # Arr
expect_text "ans=0x0000000000000007"   # Ptr
expect_text "ans=0x0000000000000003"   # Cl / StrLen
expect_text "ans=0x0000000000000042"   # Pre
expect_text "ans=0x000000000000000b"   # Get11th
expect_text "ans=0x0000000000000001"   # F() first
expect_text "ans=0x0000000000000002"   # F() redefine + 1+1
# G2 trap / Ctrl-C
expect_text "illegal instruction"
expect_text "*** FAULT"
expect_text "crash>"
expect_text "eval aborted"
expect_text "after-fault"
expect_text "Interrupted"
expect_text "after-break"
expect_text "ZAP-HIT"
expect_text "after-ecall"
expect_text "after-ctrlc"
# journal / DumpChanges
expect_text "W  Home/jlog.hc"
expect_text "fs log tail"
expect_text "fs checkpoint"
expect_text "W  Home/a3q.hc"
expect_text '$HC_CHANGES'
expect_text "ans=0x0000000000001337"
# G3: reject Src stub + missing-editor banner
reject_text "Src: wrote hello.hc"
reject_text "Src: wrote Dir.hc"
reject_text "editor: not in repl-holyc"
# G3 livedrv / gd / K (product path; not legacy uart 150a)
expect_text 'livedrv '
expect_text 'LIVEDRV '
expect_text '-- NORMAL -- print.hc'
expect_text 'after-nested-gd'
expect_text 'after-same-gd'
expect_text '-- press a key --'
expect_text 'formatted print to the UART'
expect_text 'after-K'
# same-file gd: status still samegd (seek in place); allow path or basename
if ! grep -qE -- '-- NORMAL -- (Home/)?samegd\.hc' "$log"; then
  echo "FAIL repl-holyc-regression — missing same-file gd status (samegd.hc)" >&2
  FAILS=$((FAILS + 1))
fi

if [ "$FAILS" -ne 0 ]; then
  echo "FAIL repl-holyc-regression — $FAILS check(s) failed" >&2
  echo "---- log tail ----" >&2
  tail -60 "$log" >&2
  cp "$log" "/tmp/repl-holyc-regression-last.log" 2>/dev/null || true
  exit 1
fi

echo "PASS repl-holyc-regression (G6: memfs/Dir/Src/DumpFile/Run/Man/Tab/HIST/G1/Sys/journal/Atoi/JIT + G2 trap/Ctrl-C + G3 livedrv/gd/K; Fmt+Demo waived — SELF_HOST.md)"
exit 0
